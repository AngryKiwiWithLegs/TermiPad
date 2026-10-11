// M1 local network listener service (docs/m0-m1-mobile-entry-design.md §3.2-§3.3).
// The only file in the whole repository allowed to use NWListener/NWConnection (global allowlist in verify-macos.sh).
// Red-line implementation: off by default (state starts as .off); the listener is created only after the user turns it on in Settings;
// the Bonjour service type is fixed and not configurable; a pairing is accepted only if the pairing code matches the one shown on the Mac — otherwise
// any host on the same network could silently become a "paired device" during the pairing window.
// All connection-level I/O happens on listenerQueue; only Sendable pairing results hop back to the main thread.
import CryptoKit
import Foundation
import Network
import SwiftData

@MainActor
final class MobilePairingService: ObservableObject {
    /// Fixed M1 listening port. A fixed port lets the TXT carry the full address before the listener starts,
    /// so the phone can connect directly, bypassing Bonjour service resolution (iOS 26 gets stuck in preparing when resolving .service endpoints).
    nonisolated static let listenerPort: UInt16 = MobilePairingCrypto.listenerPort
    /// M2b defense line 2: maximum lifetime of pairing credentials (30 days) — a key obtained by a phone thief
    /// lives at most 30 days; for a normal user any successful resume renews it (pairedAt is refreshed).
    nonisolated static let pairingCredentialLifetime: TimeInterval = 30 * 24 * 3600

    /// M2b defense line 3: sliding-window rate limiter for write operations (≤10 per minute). Protected by an NSLock —
    /// the handshake runs on a non-main queue; tests can inject the now/isAllowed window parameters.
    final class WriteRateLimiter: @unchecked Sendable {
        private let lock = NSLock()
        private var timestamps: [Date] = []
        private let window: TimeInterval
        private let maxCount: Int

        init(window: TimeInterval = 60, maxCount: Int = 10) {
            self.window = window
            self.maxCount = maxCount
        }

        func allow(now: Date = Date()) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            timestamps.removeAll { now.timeIntervalSince($0) > window }
            guard timestamps.count < maxCount else { return false }
            timestamps.append(now)
            return true
        }

        func reset() {
            lock.lock()
            timestamps.removeAll()
            lock.unlock()
        }
    }

    nonisolated private static let rateLimiter = WriteRateLimiter()

    /// Renewal throttle gate (companion to defense line 2): at most one Keychain write per device per day.
    /// Protected by an NSLock — the handshake runs on a non-main queue; tests can inject now/the interval.
    final class RenewalGate: @unchecked Sendable {
        private let lock = NSLock()
        private var lastRenewals: [UUID: Date] = [:]
        private let minimumInterval: TimeInterval

        init(minimumInterval: TimeInterval = 24 * 3600) {
            self.minimumInterval = minimumInterval
        }

        func shouldRenew(
            deviceID: UUID, lastRenewedAt: Date?, now: Date = Date()
        ) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            // Two gates: an in-process memory gate (this process already wrote) + a record-level gate (the record's
            // lastConnectedAt — after an app restart it keeps throttling based on that).
            if let inProcess = lastRenewals[deviceID],
               now.timeIntervalSince(inProcess) < minimumInterval {
                return false
            }
            if let persisted = lastRenewedAt,
               now.timeIntervalSince(persisted) < minimumInterval {
                return false
            }
            lastRenewals[deviceID] = now
            return true
        }

        func reset() {
            lock.lock()
            lastRenewals.removeAll()
            lock.unlock()
        }
    }

    nonisolated private static let renewalGate = RenewalGate()

    /// Enumerate the first private IPv4 on the en* interfaces (192.168/10./172.16-31).
    /// No Process and no shell dependency — getifaddrs is a libc-level system call.
    nonisolated static func lanIPv4Address() -> String? {
        var address: String?
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else {
            return nil
        }
        defer { freeifaddrs(ifaddrPtr) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = cursor {
            cursor = ifa.pointee.ifa_next
            guard let name = String(cString: ifa.pointee.ifa_name, encoding: .utf8),
                  name.hasPrefix("en"),
                  let sa = ifa.pointee.ifa_addr,
                  sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            var addr = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &addr.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN))
            guard let ip = String(cString: buffer, encoding: .utf8) else { continue }
            let octets = ip.split(separator: ".").compactMap { UInt8($0) }
            guard octets.count == 4 else { continue }
            let isPrivate = octets[0] == 192 && octets[1] == 168
                || octets[0] == 10
                || (octets[0] == 172 && (12...31).contains(octets[1]))
            if isPrivate {
                address = ip
                break
            }
        }
        return address
    }

    enum ServiceState: Equatable {
        case off
        case listening(pairingCode: String, fingerprint: String)
        case failed(String)
    }

    @Published private(set) var state: ServiceState = .off
    @Published private(set) var pairedDevices: [PairedDeviceRecord] = []

    var activePairedDevices: [PairedDeviceRecord] {
        pairedDevices.filter { $0.revokedAt == nil }
    }

    private var listener: NWListener?
    private let listenerQueue = DispatchQueue(label: "com.termipad.mobile-pairing", qos: .userInitiated)
    private let store: MobileSecureKeyValueStore
    /// Shared store for the M2a tunnel's resume-only entry point (static — the tunnel handshake has no instance context;
    /// it uses the same Keychain backend as the instance store and reads/writes the same set of device records).
    nonisolated private static let tunnelResumeStore: MobileSecureKeyValueStore = KeychainMobileSecureStore()

    init(store: MobileSecureKeyValueStore = KeychainMobileSecureStore()) {
        self.store = store
        // The first Keychain read must leave the main thread: PreferencesView's @StateObject initializer
        // runs on the main-thread body chain, and Task { @MainActor } merely moves the call onto the main thread's
        // concurrency queue — SecItemCopyMatching would still run on the MainActor (2026-09-09,
        // confirmed by two rounds of spindump: all 422 samples were stuck in MainActor→SecItem; the first access has to go through
        // the security daemon and can take 15s+ in the non-interactive UI test environment, leaving the app unresponsive and accessibility
        // never loading). Changed to read on a background thread and refresh @Published on the main thread when done.
        let store = store
        Task.detached(priority: .userInitiated) { [weak self] in
            let devices = PairedDeviceStore.list(store: store)
            await MainActor.run { [weak self] in
                self?.pairedDevices = devices
            }
        }
    }

    /// Inject the SwiftData context (MainActor domain) — the read-only data source for listTools responses.
    /// Static handler functions cannot reach instance state, so it is shared through a class-level static member.
    func configure(modelContext: ModelContext) {
        Self.sharedModelContext = modelContext
    }

    @MainActor private static var sharedModelContext: ModelContext?

    func refreshPairedDevices() {
        refreshPairedDevicesOffMain()
    }

    /// The user turns pairing on: load/generate the local identity, show the pairing code and fingerprint, and start Bonjour advertising.
    /// Race on a quick off→on (2026-09-10, repeatedly observed by the user as "enabling pairing fails again"):
    /// the old NWListener.cancel() is asynchronous — the new listener binds 57146 right away and collides with
    /// the old socket that has not been released, NWListener goes to .failed(EADDRINUSE) → red error text in the UI.
    /// allowLocalEndpointReuse only resolves TIME_WAIT; it cannot resolve "the old object has not finished closing".
    /// Fix: on a bind failure wait and retry automatically (3 times × 1 second) instead of reporting an error right away.
    func startPairing() {
        guard listener == nil else { return }
        isPairingEnabledIntent = true
        do {
            let identity = try PairedDeviceStore.MobilePairingIdentityStore.loadOrCreate(store: store)
            attemptStartPairing(identity: identity, attempt: 0)
        } catch {
            isPairingEnabledIntent = false
            Self.diagMac("Failed to start pairing: error loading identity \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
        }
    }

    private func attemptStartPairing(identity: MobilePairingIdentity, attempt: Int) {
        // Exponential backoff (1/2/4 seconds): after a failed listener is cancelled, kernel cleanup
        // (TCP dual-stack listen+backlog) is much slower than a normal close. When attempt>0, back off first
        // and then bind; the bind attempt itself is in attemptStartPairingImmediate — the failed callback
        // advances attempt+1 and enters this method again. **Structural warning**: the earlier implementation wrote the backoff
        // branch as a recursive call to itself without advancing attempt, creating an infinite backoff loop —
        // the bind never ran again and pairing "died quietly" (observed three times in a row on 2026-09-19).
        if attempt > 0 {
            let backoffNanos = UInt64(pow(2.0, Double(attempt)) * 1_000_000_000)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: backoffNanos)
                guard let self, self.listener == nil, self.isPairingEnabledIntent else { return }
                self.attemptStartPairingImmediate(identity: identity, attempt: attempt)
            }
            return
        }
        attemptStartPairingImmediate(identity: identity, attempt: attempt)
    }

    private func attemptStartPairingImmediate(identity: MobilePairingIdentity, attempt: Int) {
        let fingerprint = MobilePairingCrypto.fingerprint(forPublicKeyData: try! identity.publicKeyData())
        let pairingCode = MobilePairingCrypto.generatePairingCode()
        // Wi-Fi pinned + fixed port + TXT carrying the LAN address: the phone gets IP:port directly while browsing
        // and connects via hostPort, bypassing iOS 26's stuck preparing when resolving .service endpoints.
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .wifi
        // On stop → quick restart of pairing the old socket is still in TIME_WAIT / closing asynchronously, and the fixed port
        // would report "address already in use" (the UI shows a string of red errors). Allow local endpoint reuse;
        // this is a necessary companion to M1's fixed-port design.
        parameters.allowLocalEndpointReuse = true
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: MobilePairingService.listenerPort)!)
        } catch {
            // Port not released yet (the old listener is still closing asynchronously): wait and retry, at most 3 times.
            if attempt < 3 {
                Self.diagMac("Pairing port temporarily unavailable (attempt \(attempt + 1)), retrying in 1 second")
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard let self, self.listener == nil, self.isPairingEnabledIntent else { return }
                    self.attemptStartPairing(identity: identity, attempt: attempt + 1)
                }
                return
            }
            Self.diagMac("Failed to start pairing: port still unavailable after 3 retries \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
            return
        }
        var txtDictionary = MobilePairingCrypto.bonjourTXTRecord(fingerprint: fingerprint)
        if let lanAddress = MobilePairingService.lanIPv4Address() {
            txtDictionary["a"] = lanAddress
            txtDictionary["p"] = String(MobilePairingService.listenerPort)
            Self.diagMac("TXT carries LAN address \(lanAddress):\(MobilePairingService.listenerPort)")
        } else {
            Self.diagMac("No LAN IPv4 found — TXT has no address, the phone takes the service-endpoint fallback path")
        }
        // The instance name carries the LAN address (TermiPad-192-168-2-81): on iOS 26 the phone's
        // browse results carry no TXT (metadata is always .none), and .service resolution gets stuck in
        // preparing. Encoding the address in the instance name is the only channel the phone can read by itself; the port is the fixed
        // listenerPort. The instance name only affects "how to connect"; identity is still decided by the MacHello fingerprint.
        let serviceName: String
        if let lanAddress = MobilePairingService.lanIPv4Address() {
            serviceName = "\(MobilePairingCrypto.bonjourServiceName)-\(lanAddress.replacingOccurrences(of: ".", with: "-"))"
            Self.diagMac("Instance name carries LAN address: \(serviceName)")
        } else {
            serviceName = MobilePairingCrypto.bonjourServiceName
            Self.diagMac("No LAN IPv4 found — falling back to an instance name without an address")
        }
        listener.service = NWListener.Service(
            name: serviceName,
            type: MobilePairingCrypto.bonjourServiceType,
            domain: "local.",
            txtRecord: NWTXTRecord(txtDictionary))
        listener.stateUpdateHandler = { [weak self] (newState: NWListener.State) in
            guard let self else { return }
            Task { @MainActor in
                if case .failed(let error) = newState {
                    // **Asynchronous failures are retried too**: NWListener binds in two stages — after init
                    // succeeds synchronously, the listen stage can still collide with an unreleased old socket
                    // (EADDRINUSE delivered asynchronously, confirmed 2026-09-10 18:55:49: the previous version's
                    // retry only covered the synchronous init, and the user still got an error when toggling again). Wait 1 second and retry likewise.
                    guard self.listener === listener, self.isPairingEnabledIntent else { return }
                    if attempt < 3 {
                        Self.diagMac("Pairing listener failed asynchronously (attempt \(attempt + 1)): \(error.localizedDescription), retrying in 1 second")
                        self.discardListenerQuietly(listener)
                        Task { @MainActor [weak self] in
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                            guard let self, self.listener == nil, self.isPairingEnabledIntent else { return }
                            self.attemptStartPairing(identity: identity, attempt: attempt + 1)
                        }
                        return
                    }
                    Self.diagMac("Failed to start pairing: still unavailable after 3 asynchronous retries \(error.localizedDescription)")
                    self.stopPairingInternal()
                    self.state = .failed("The port is in use. Wait 10 seconds and then click “Enable Local Network Pairing” again. \(error.localizedDescription)")
                }
            }
        }
        listener.newConnectionHandler = { [weak self] (connection: NWConnection) in
            guard let self else { return }
            MobilePairingService.beginHandshake(
                on: connection,
                queue: self.listenerQueue,
                identity: identity,
                pairingCode: pairingCode,
                store: self.store) { result in
                    Task { @MainActor in self.finishPairing(result) }
                }
        }
        listener.start(queue: listenerQueue)
        self.listener = listener
        state = .listening(pairingCode: pairingCode, fingerprint: fingerprint)
    }

    /// Retry path only: discard the failed listener but do **not** touch the intent flag / state machine —
    /// stopPairingInternal clears the allowlist and writes diagnostics, neither of which should happen during a retry.
    private func discardListenerQuietly(_ listener: NWListener) {
        guard self.listener === listener else { return }
        listener.cancel()
        self.listener = nil
    }

    /// Intent flag for the user having turned pairing on: the user may have clicked off during retries — a retry
    /// continues only while the intent still holds.
    private var isPairingEnabledIntent = false

    func stopPairing() {
        isPairingEnabledIntent = false
        stopPairingInternal()
        state = .off
    }

    /// Keychain reads always go through a background thread + main-thread backfill (same discipline as init —
    /// the first SecItemCopyMatching access can take 15s+ in a non-interactive environment and must not run on the MainActor).
    private func refreshPairedDevicesOffMain() {
        let store = store
        Task.detached(priority: .userInitiated) { [weak self] in
            let devices = PairedDeviceStore.list(store: store)
            await MainActor.run { [weak self] in
                self?.pairedDevices = devices
            }
        }
    }

    /// Red line "every permission is revocable": a revocation is written to the Keychain immediately and the list is refreshed.
    /// Revocation does not affect already-established old connections — in this commit the connection is dropped once pairing completes, so no long-lived connection can remain.
    func revoke(id: UUID) {
        try? PairedDeviceStore.revoke(id: id, store: store)
        refreshPairedDevicesOffMain()
    }

    private func stopPairingInternal() {
        listener?.cancel()
        listener = nil
        // Turning the listener off clears the session allowlist — the lifetime of the confirmation-free cache never exceeds the period the listener is on.
        MobileLaunchSession.shared.invalidateAll()
        // M3: linked to pairing off/revocation — the remote window is invalidated immediately (design §3.2 revocation linkage).
        RemoteAllowWindow.shared.close()
    }

    private func finishPairing(_ result: Result<PairedDeviceRecord, Error>) {
        // Failures (scanners, version mismatch, wrong pairing code) drop the connection silently; diagnostic events will be wired in later.
        if case .success = result {
            refreshPairedDevicesOffMain()
        }
    }

    // MARK: - Diagnostics

    /// Mac-side diagnostics: NSLog + ~/Library/Logs/termipad-pairing.log (the unified log is
    /// unreliable under local ad hoc signing; the file log guarantees it can be inspected).
    nonisolated static func diagMac(_ message: String) {
        NSLog("termipad-pairing: \(message)")
        let line = "[\(Date())] \(message)\n"
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/termipad-pairing.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Connection-level handshake (listenerQueue context, does not touch MainActor state)

    nonisolated private static func beginHandshake(
        on connection: NWConnection,
        queue: DispatchQueue,
        identity: MobilePairingIdentity,
        pairingCode: String,
        store: MobileSecureKeyValueStore,
        completion: @escaping @Sendable (Result<PairedDeviceRecord, Error>) -> Void
    ) {
        var didComplete = false
        func complete(_ result: Result<PairedDeviceRecord, Error>) {
            guard !didComplete else { return }
            didComplete = true
            connection.cancel()
            completion(result)
        }

        connection.stateUpdateHandler = { newState in
            switch newState {
            case .ready:
                runHandshake(
                    on: connection,
                    identity: identity,
                    expectedPairingCode: pairingCode,
                    store: store,
                    complete: complete)
            case .failed(let error):
                complete(.failure(error))
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    /// Entry point dedicated to the M2a tunnel listener: accepts only resume handshakes from already-paired devices. First-time pairing must
    /// stay on the same network (comparing fingerprints by eye is a design premise) — any PhoneHello appearing on the tunnel is disconnected.
    nonisolated static func beginResumeOnlyHandshake(
        on connection: NWConnection,
        queue: DispatchQueue
    ) {
        do {
            let identity = try PairedDeviceStore.MobilePairingIdentityStore.loadOrCreate(store: tunnelResumeStore)
            connection.stateUpdateHandler = { newState in
                guard case .ready = newState else {
                    if case .failed = newState { connection.cancel() }
                    return
                }
                runResumeOnlyHandshake(on: connection, identity: identity, store: tunnelResumeStore)
            }
            connection.start(queue: queue)
        } catch {
            connection.cancel()
        }
    }

    nonisolated private static func runResumeOnlyHandshake(
        on connection: NWConnection,
        identity: MobilePairingIdentity,
        store: MobileSecureKeyValueStore
    ) {
        let macNonce = MobilePairingCrypto.generateNonce()
        guard let frame = try? MobilePairingFrame.encode(JSONEncoder().encode(
            MobilePairingHandshake.makeMacHello(identity: identity, macNonce: macNonce))) else {
            connection.cancel()
            return
        }
        send(frame, on: connection)
        receiveOneMessage(on: connection, buffer: Data()) { data in
            guard let data,
                  case .resume(let hello) = MobilePairingHandshake.decodeIncomingHello(from: data) else {
                // Pairing hello / unparsable frame: the tunnel does not accept first-time pairing, disconnect immediately.
                connection.cancel()
                return
            }
            handleResumeHello(hello, connection: connection, identity: identity, macNonce: macNonce, store: store)
        }
    }

    nonisolated private static func runHandshake(
        on connection: NWConnection,
        identity: MobilePairingIdentity,
        expectedPairingCode: String,
        store: MobileSecureKeyValueStore,
        complete: @escaping (Result<PairedDeviceRecord, Error>) -> Void
    ) {
        do {
            let macNonce = MobilePairingCrypto.generateNonce()
            let macHello = try MobilePairingHandshake.makeMacHello(identity: identity, macNonce: macNonce)
            send(MobilePairingFrame.encode(try JSONEncoder().encode(macHello)), on: connection)

            receiveOneMessage(on: connection, buffer: Data()) { data in
                guard let data else {
                    complete(.failure(MobilePairingError.handshakeFailed))
                    return
                }
                switch MobilePairingHandshake.decodeIncomingHello(from: data) {
                case .pairing(let hello):
                    Self.handlePairingHello(
                        hello,
                        connection: connection,
                        identity: identity,
                        expectedPairingCode: expectedPairingCode,
                        macNonce: macNonce,
                        store: store,
                        complete: complete)
                case .resume(let hello):
                    Self.handleResumeHello(hello, connection: connection, identity: identity, macNonce: macNonce, store: store)
                case nil:
                    complete(.failure(MobilePairingError.handshakeFailed))
                }
            }
        } catch {
            complete(.failure(error))
        }
    }

    /// Pairing path: compare with the on-screen pairing code → accept → persist → send the encrypted ack → disconnect.
    nonisolated private static func handlePairingHello(
        _ hello: MobilePairingHandshake.PhoneHello,
        connection: NWConnection,
        identity: MobilePairingIdentity,
        expectedPairingCode: String,
        macNonce: Data,
        store: MobileSecureKeyValueStore,
        complete: @escaping (Result<PairedDeviceRecord, Error>) -> Void
    ) {
        do {
            // The Mac must check that the pairing code matches the one on screen — this is the key defense against "a same-network host pairing silently".
            guard hello.pairingCode == expectedPairingCode else {
                diagMac("Pairing rejected: pairing code does not match the one on screen (length \(hello.pairingCode.utf8.count))")
                complete(.failure(MobilePairingError.invalidPairingCode))
                return
            }
            let accepted = try MobilePairingHandshake.acceptPhoneHello(
                hello, identity: identity, macNonce: macNonce)
            // Reuse the record of an active device with the same fingerprint, so repeated pairing does not create duplicate entries.
            let record: PairedDeviceRecord
            if let existing = PairedDeviceStore.findActive(
                byPublicKeyHash: accepted.phonePublicKeyHash, store: store) {
                try PairedDeviceStore.markConnected(id: existing.id, store: store)
                record = existing
                diagMac("Pairing accepted: reusing existing record \(existing.displayName)")
            } else {
                record = try PairedDeviceStore.add(
                    displayName: accepted.deviceName,
                    publicKeyData: hello.phonePublicKey,
                    store: store)
                diagMac("Pairing accepted: new device \(accepted.deviceName)")
            }
            let key = SymmetricKey(data: accepted.sessionKeyData)
            let ack = MobilePairingAck(accepted: true, deviceID: record.id)
            let ackFrame = MobilePairingFrame.encode(try MobilePairingEnvelope.seal(ack, using: key))
            connection.send(content: ackFrame, completion: .contentProcessed { sendError in
                if let sendError {
                    complete(.failure(sendError))
                } else {
                    complete(.success(record))
                }
            })
        } catch {
            complete(.failure(error))
        }
    }

    /// Resume path (§3.3.1): verify the record is active + public-key fingerprint binding → send the plaintext MacResumeHello →
    /// wait for the encrypted request → one request, one response → disconnect. Failures disconnect silently (the peer cannot tell rejection reasons apart,
    /// which avoids giving scanners probing information).
    nonisolated private static func handleResumeHello(
        _ hello: MobilePairingHandshake.PhoneResumeHello,
        connection: NWConnection,
        identity: MobilePairingIdentity,
        macNonce: Data,
        store: MobileSecureKeyValueStore
    ) {
        do {
            guard let record = PairedDeviceStore.find(id: hello.deviceID, store: store) else {
                diagMac("resume rejected: device record not found \(hello.deviceID)")
                throw MobilePairingError.handshakeFailed
            }
            guard record.revokedAt == nil else {
                diagMac("resume rejected: device revoked \(record.displayName)")
                throw MobilePairingError.handshakeFailed
            }
            guard MobilePairingCrypto.fingerprint(forPublicKeyData: hello.phonePublicKey)
                == record.publicKeyHash else {
                diagMac("resume rejected: public-key fingerprint mismatch")
                throw MobilePairingError.handshakeFailed
            }
            // M2b defense line 2 (design §4): 30-day lifetime of pairing credentials — resume is rejected once they are too old,
            // and the phone has to return to the same network and pair again. For a normal user any successful resume renews them.
            guard Date().timeIntervalSince(record.pairedAt) <= Self.pairingCredentialLifetime else {
                diagMac("resume rejected: pairing is past its 30-day lifetime \(record.displayName)")
                throw MobilePairingError.handshakeFailed
            }
            // M2b defense line 2 renewal: a successful resume refreshes pairedAt, but **throttled** — at most one Keychain write per device
            // per day. Writing on every round of 3-second polling would (a) trigger the system keychain authorization
            // prompt like crazy (2026-09-10 user test: "more and more frequent"), and (b) when the write
            // authorization is denied, push the UI state into failed (a false "pairing service error" alarm).
            // The 30-day lifetime semantics are unchanged: the window counts from the most recent renewal, once a day in everyday use
            // is enough to renew; the 30-day cap in the lost-phone scenario still holds.
            let deviceID = record.id
            let storeRef = store
            let shouldRenew = Self.renewalGate.shouldRenew(
                deviceID: deviceID, lastRenewedAt: record.lastConnectedAt)
            if shouldRenew {
                Task.detached(priority: .utility) {
                    try? PairedDeviceStore.markConnected(
                        id: deviceID, at: Date(), store: storeRef)
                }
            }
            let sessionKeyData = try MobilePairingHandshake.deriveResumeSessionKey(
                hello, identity: identity, macNonce: macNonce)
            // M2a: while the tunnel is on, the remote endpoint is issued along with MacResumeHello (bootstrapped on the same network;
            // once the phone persists it, nothing needs to be done when leaving home). Plaintext is acceptable — see the field comment in the protocol layer.
            let macResume = MobilePairingHandshake.MacResumeHello(
                protocolVersion: MobilePairingHandshake.currentProtocolVersion,
                macPublicKey: try identity.publicKeyData(),
                macNonce: macNonce,
                tailnetEndpoint: TailnetTunnelService.endpointHolder.get())
            diagMac("resume accepted: \(record.displayName), sending MacResumeHello (tailnet=\(macResume.tailnetEndpoint ?? "off"))")
            send(MobilePairingFrame.encode(try JSONEncoder().encode(macResume)), on: connection)
            receiveOneMessage(on: connection, buffer: Data()) { requestData in
                guard let requestData else {
                    connection.cancel()
                    return
                }
                handleSealedRequest(requestData, connection: connection, sessionKeyData: sessionKeyData)
            }
        } catch {
            connection.cancel()
        }
    }

    /// Decrypt the request → dispatch through the operation allowlist. Undecryptable requests (unpaired peer / tampering) and operations outside the allowlist
    /// are always disconnected immediately, with no error details returned.
    nonisolated private static func handleSealedRequest(
        _ data: Data,
        connection: NWConnection,
        sessionKeyData: Data
    ) {
        let key = SymmetricKey(data: sessionKeyData)
        guard let request = try? MobilePairingEnvelope.openRequest(data, using: key) else {
            diagMac("Failed to decrypt the encrypted request — \(data.count) bytes")
            connection.cancel()
            return
        }
        diagMac("Received request op=\(request.operation.rawValue) toolID=\(request.toolID?.uuidString ?? "nil")")
        // M2b defense line 3 (design §4): rate limit on write operations — ≤10 per device per minute
        // (submissions + launches combined). Over the limit, fixed copy is returned (prevents automated abuse; an attacker with a lost phone
        // cannot probe at high frequency). Read-only operations and heartbeats are not limited.
        switch request.operation {
        case .requestLaunch, .requestTaskProposal, .cancelTask:
            guard rateLimiter.allow() else {
                diagMac("Rate limit: more than 10 write operations per minute")
                Task { @MainActor in
                    Self.sendSealed(
                        MobileTaskProposalResponse(
                            status: .rejected, reason: "Too many requests. Please try again later.", taskIntentID: nil),
                        on: connection, using: key)
                }
                return
            }
        default:
            break
        }
        switch request.operation {
        case .listTools:
            Task { @MainActor in
                let summaries = buildToolSummaries()
                guard let response = try? MobilePairingEnvelope.seal(summaries, using: key) else {
                    connection.cancel()
                    return
                }
                connection.send(content: MobilePairingFrame.encode(response), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        case .requestLaunch:
            Task { @MainActor in
                guard let toolID = request.toolID else {
                    Self.sendLaunchResponse(
                        MobileLaunchResponse(status: .rejected, reason: "The request is missing a target tool."),
                        on: connection, using: key)
                    return
                }
                await Self.handleLaunchRequest(
                    toolID: toolID, requestID: request.requestID, connection: connection, sessionKey: key)
            }
        case .listScopes:
            Task { @MainActor in
                let summaries = Self.sharedModelContext.map {
                    MobileTaskConsoleService.shared.scopeSummaries(modelContext: $0)
                } ?? []
                Self.sendSealed(summaries, on: connection, using: key)
            }
        case .listFixedTasks:
            Task { @MainActor in
                let language = AppLanguage.current
                let summaries = MobileTaskConsoleService.shared.fixedTaskSummaries(language: language)
                Self.sendSealed(summaries, on: connection, using: key)
            }
        case .getTaskStatus:
            Task { @MainActor in
                let entries = MobileTaskConsoleService.shared.sessionEntries()
                Self.sendSealed(entries, on: connection, using: key)
            }
        case .requestTaskProposal:
            Task { @MainActor in
                let response = await MobileTaskConsoleService.shared.handleTaskProposal(
                    taskKind: request.taskKind,
                    projectScopeID: request.projectScopeID,
                    modelContext: Self.sharedModelContext
                        ?? ModelContext(try! ModelContainer(for: TaskIntent.self, TaskProjectScope.self, TaskReviewWindow.self)),
                    confirm: { taskTitle in
                        await MobileLaunchPromptCenter.shared.requestConfirmation(
                            toolName: taskTitle, deviceName: "Paired device")
                    })
                DiagnosticsStore.shared.record(.mcpTaskProposed)
                Self.sendSealed(response, on: connection, using: key)
            }
        case .cancelTask:
            Task { @MainActor in
                let response = request.taskIntentID.map {
                    MobileTaskConsoleService.shared.cancelTask(taskIntentID: $0)
                } ?? MobileTaskProposalResponse(
                    status: .rejected, reason: "The request is missing a task reference.", taskIntentID: nil)
                Self.sendSealed(response, on: connection, using: key)
            }
        case .openTaskStream:
            Task { @MainActor in
                // M4: precondition for stream subscription = the daily remote window is open (design §2.3).
                guard RemoteAllowWindow.shared.isOpen, let taskID = request.taskIntentID else {
                    Self.sendSealed(
                        MobileStreamResponse(
                            status: .rejected,
                            reason: RemoteAllowWindow.shared.isOpen
                                ? "The request is missing a task reference."
                                : "Today's remote window is not open. Open it on the Mac and try again.",
                            resumeOffset: nil),
                        on: connection, using: key)
                    return
                }
                let connectionID = request.requestID
                // M4-2: resume offset declared by the phone (resume from the breakpoint after a reconnect).
                let resumeOffset = request.streamResumeOffset
                // **Frame order is critical**: the subscription receipt must be the first frame the phone receives — the phone starts
                // its push receive loop only after handling the receipt; if backlog were pushed / the sink registered first,
                // the replayed chunk would be parsed by the phone as the receipt (confirmed on a real device 2026-09-19).
                // Order: send the receipt first → then register the sink → then subscribe (the backlog replay inside the subscription
                // goes through the registered sink, by which time the phone is already in its push loop).
                Self.sendSealed(
                    MobileStreamResponse(status: .accepted, reason: nil, resumeOffset: 0),
                    on: connection, using: key,
                    keepConnectionOpen: true)
                TaskOutputStreamService.shared.registerSink(connectionID) { chunk in
                    guard let sealed = try? MobilePairingEnvelope.seal(chunk, using: key) else {
                        diagMac("Stream push: chunk encryption failed")
                        return
                    }
                    connection.send(
                        content: MobilePairingFrame.encode(sealed),
                        completion: .contentProcessed { error in
                            if let error { diagMac("Stream push send failed: \(error.localizedDescription)") }
                        })
                }
                _ = TaskOutputStreamService.shared.subscribe(
                    connectionID: connectionID, taskID: taskID, resumeOffset: resumeOffset) { chunk in
                    guard let sealed = try? MobilePairingEnvelope.seal(chunk, using: key) else {
                        diagMac("Stream replay: chunk encryption failed")
                        return
                    }
                    connection.send(
                        content: MobilePairingFrame.encode(sealed),
                        completion: .contentProcessed { error in
                            if let error { diagMac("Stream replay send failed: \(error.localizedDescription)") }
                        })
                }
                // M4-3 interaction requests use a separate frame type (the phone tells them apart by field names).
                TaskOutputStreamService.shared.addInteractionHandler { [weak connection] targetConnectionID, interaction in
                    guard targetConnectionID == connectionID, let connection else { return }
                    guard let sealed = try? MobilePairingEnvelope.seal(interaction, using: key) else { return }
                    connection.send(
                        content: MobilePairingFrame.encode(sealed),
                        completion: .contentProcessed { _ in })
                }
            }
        case .respondInteraction:
            Task { @MainActor in
                // M4-3: write the option selected on the phone back to the task's stdin.
                guard let taskID = request.taskIntentID,
                      let selection = request.interactionSelection else {
                    connection.cancel()
                    return
                }
                TaskExecutionCoordinator.shared.respondInteraction(
                    intentID: taskID, selection: selection)
                // Disconnect silently (a request/response link needs no receipt — the stream will show the task continuing).
                connection.cancel()
            }
        case .closeTaskStream:
            Task { @MainActor in
                if let taskID = request.taskIntentID {
                    TaskOutputStreamService.shared.unsubscribe(connectionID: request.requestID)
                    _ = taskID
                }
                // Request/response path: disconnect naturally after the unsubscribe receipt.
                Self.sendSealed(
                    MobileStreamResponse(status: .accepted, reason: nil, resumeOffset: nil),
                    on: connection, using: key)
            }
        default:
            // The remaining operations are enabled one by one at the design doc's pace; anything not enabled is rejected and disconnected.
            connection.cancel()
        }
    }

    /// Generic encrypted reply frame: the return path for the three read-only task session operations (their data shapes all differ,
    /// but they all go through the AEAD envelope + the existing frame format).
    @MainActor
    private static func sendSealed(
        _ value: some Encodable,
        on connection: NWConnection,
        using key: SymmetricKey,
        keepConnectionOpen: Bool = false
    ) {
        guard let sealed = try? MobilePairingEnvelope.seal(value, using: key) else {
            connection.cancel()
            return
        }
        connection.send(content: MobilePairingFrame.encode(sealed), completion: .contentProcessed { _ in
            guard !keepConnectionOpen else { return }
            connection.cancel()
        })
    }

    /// §3.3.2 launch request execution chain (the order cannot be swapped):
    /// eligibility pre-check → local confirmation (60s timeout = denied) → handoff via TerminalLauncher → return the result.
    @MainActor
    private static func handleLaunchRequest(
        toolID: UUID,
        requestID: UUID,
        connection: NWConnection,
        sessionKey: SymmetricKey
    ) async {
        // 0. Reject while locked (patch for M2b defense line 3, found in the 2026-09-10 acceptance: the lock-screen check
        // previously only covered the task submission chain and missed the tool launch chain — a thief who picks up the phone could still tap
        // tools remotely. Same check and same copy family as task submission).
        if MobileTaskConsoleService.isLoginSessionLocked() {
            DiagnosticsStore.shared.record(.remoteTaskBlockedScreenLocked)
            sendLaunchResponse(
                MobileLaunchResponse(status: .rejected, reason: "The Mac is locked. The remote launch was rejected."),
                on: connection, using: sessionKey)
            return
        }
        // 1. Eligibility pre-check
        guard let tool = fetchTool(id: toolID),
              tool.showInMobileEntry,
              tool.allowMobileLaunchRequest,
              tool.revokeMobilePermissionAt == nil,
              CommandTemplate.variables(in: tool.commandTemplate).isEmpty else {
            sendLaunchResponse(
                MobileLaunchResponse(status: .rejected, reason: "This tool is not allowed to be launched from the phone, or it requires parameters to be filled in."),
                on: connection, using: sessionKey)
            return
        }
        // 2. Local confirmation (§3.3.2, added 2026-09-08): a perSession/lowRisk session allowlist
        //    hit launches directly without confirmation (an audit event is recorded); the same applies while the M3 daily remote window is open
        //    (design §3.3 — the T0 / lock-screen / rate-limit checks are not exempted on this path); everything else shows the 60s confirmation prompt.
        let launchSession = MobileLaunchSession.shared
        if launchSession.canSkipConfirmation(
            policy: tool.mobileLocalConfirmPolicy,
            toolID: tool.id,
            commandTemplate: tool.commandTemplate) {
            DiagnosticsStore.shared.record(.mobileLaunchAutoConfirmed)
            diagMac("Session allowlist hit, launching directly without confirmation policy=\(tool.mobileLocalConfirmPolicy.rawValue)")
        } else if RemoteAllowWindow.shared.allowsSkipConfirmation() {
            DiagnosticsStore.shared.record(.remoteAllowWindowUsed)
            diagMac("Daily remote window hit, launching directly without confirmation")
        } else {
            let accepted = await MobileLaunchPromptCenter.shared.requestConfirmation(
                toolName: tool.mobileDisplayName ?? tool.name,
                deviceName: "Paired device")
            guard accepted else {
                sendLaunchResponse(
                    MobileLaunchResponse(status: .rejected, reason: "This launch was denied on the Mac."),
                    on: connection, using: sessionKey)
                return
            }
            // A successful confirmation refreshes the session timestamp — perSession/lowRisk count 5 minutes from this confirmation.
            launchSession.recordConfirmation(toolID: tool.id)
        }
        // 3. Go through the existing terminal launch path — no new execution entry point; the command comes from the template saved on the Mac
        let target = TerminalTarget(
            rawValue: UserDefaults.standard.string(forKey: "TermiPad.terminalTarget") ?? ""
        ) ?? .systemTerminal
        let contextualCommand = ToolLaunchContext.command(
            tool.commandTemplate, inWorkingDirectory: tool.workingDirectoryPath)
        do {
            let result = try TerminalLauncher.launch(command: contextualCommand, target: target)
            switch result {
            case .launched(let launchTarget):
                DiagnosticsStore.shared.record(.launchSucceeded, terminalTarget: launchTarget)
                tool.lastLaunchedAt = Date()
                // M2b-1: tool launch events enter the phone's session entry feed (launched/failed only;
                // the terminal handoff path has no exit code and no output — the red line is unchanged).
                MobileTaskConsoleService.shared.recordToolLaunch(
                    id: requestID,
                    title: tool.mobileDisplayName ?? tool.name,
                    succeeded: true)
            default:
                DiagnosticsStore.shared.record(.launchFailed, terminalTarget: target)
                MobileTaskConsoleService.shared.recordToolLaunch(
                    id: requestID,
                    title: tool.mobileDisplayName ?? tool.name,
                    succeeded: false)
            }
        } catch {
            DiagnosticsStore.shared.record(.launchFailed, terminalTarget: target)
            MobileTaskConsoleService.shared.recordToolLaunch(
                id: requestID,
                title: tool.mobileDisplayName ?? tool.name,
                succeeded: false)
        }
        // 4. Result (accepted as soon as the launch handoff completes; whether a terminal actually pops up is up to the terminal side,
        // the same semantics as a manual launch on the Mac)
        sendLaunchResponse(
            MobileLaunchResponse(status: .accepted, reason: nil),
            on: connection, using: sessionKey)
    }

    @MainActor
    private static func fetchTool(id: UUID) -> TerminalTool? {
        guard let modelContext = sharedModelContext else { return nil }
        var descriptor = FetchDescriptor<TerminalTool>(
            predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    @MainActor
    private static func sendLaunchResponse(
        _ response: MobileLaunchResponse,
        on connection: NWConnection,
        using key: SymmetricKey
    ) {
        guard let sealed = try? MobilePairingEnvelope.seal(response, using: key) else {
            connection.cancel()
            return
        }
        connection.send(content: MobilePairingFrame.encode(sealed), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    /// Read-only catalog: only tools with showInMobileEntry == true, with a 4-field allowlist
    /// (id / displayName / displayDescription / iconSymbolName).
    /// Commands, paths, and variable values never enter this response — the MobileToolSummary field set is locked down by tests.
    @MainActor
    private static func buildToolSummaries() -> [MobileToolSummary] {
        guard let modelContext = sharedModelContext else { return [] }
        let descriptor = FetchDescriptor<TerminalTool>(
            predicate: #Predicate { $0.showInMobileEntry == true })
        let tools = (try? modelContext.fetch(descriptor)) ?? []
        return tools.map { tool in
            MobileToolSummary(
                id: tool.id,
                displayName: tool.mobileDisplayName ?? tool.name,
                displayDescription: tool.mobileDescription,
                iconSymbolName: tool.iconSymbol)
        }
    }

    nonisolated private static func send(_ frame: Data, on connection: NWConnection) {
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    /// Recursively receive bytes into the buffer and call back once the first frame is decoded; on error / peer close call back with nil.
    nonisolated private static func receiveOneMessage(
        on connection: NWConnection,
        buffer: Data,
        handler: @escaping @Sendable (Data?) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { content, _, isComplete, error in
            var accumulated = buffer
            if let content {
                accumulated.append(content)
            }
            if error != nil {
                handler(nil)
                return
            }
            switch MobilePairingFrame.decodeOne(from: accumulated) {
            case .message(let message, _):
                handler(message)
            case .incomplete:
                if isComplete {
                    handler(nil)
                    return
                }
                receiveOneMessage(on: connection, buffer: accumulated, handler: handler)
            case .invalid:
                handler(nil)
            }
        }
    }
}
