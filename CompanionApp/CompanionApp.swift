// iPhone companion app entry point (docs/m0-m1-mobile-entry-design.md §3.2-§3.3 + §3.3.1).
// Two handshake paths:
//   pairing — first connection: enter the 6-digit pairing code shown on the Mac + compare fingerprints by eye
//   resume — an already-paired phone reconnects: persisted identity + two-way public-key fingerprint binding, no code
import SwiftUI
import Network
import CryptoKit
import LocalAuthentication

@main
struct TermiPadCompanionApp: App {
    @StateObject private var client = CompanionPairingClient()
    @StateObject private var appLock = CompanionAppLock()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(client)
                // M2b defense line 1 (design §4): Face ID / device passcode when returning to the foreground.
                // While locked, the whole UI is covered — a phone thief cannot get past biometrics.
                .fullScreenCover(isPresented: $appLock.isLocked) {
                    CompanionLockView(appLock: appLock)
                }
        }
    }
}

/// M2b defense line 1: app foreground lock. On by default (on the lock screen the user can skip it once,
/// after which it stays unlocked for the session — device-level security falls back to the iOS system lock; the pairing credentials are already
/// WhenUnlockedThisDeviceOnly).
@MainActor
final class CompanionAppLock: ObservableObject {
    @Published var isLocked = true
    /// Authentication failure notice (shown on the lock screen; nil means no notice).
    @Published var authNotice: String?

    func requestUnlock() {
        let context = LAContext()
        var error: NSError?
        // Device passcode fallback: devices without Face ID / Touch ID fall back to the passcode.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // Devices with no biometric or passcode protection at all (rare in theory) — do not lock the user out.
            isLocked = false
            return
        }
        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Once verified, you can view Mac task status and send actions"
        ) { [weak self] success, authError in
            Task { @MainActor in
                if !success, let laError = authError as? LAError,
                   laError.code == .biometryLockout {
                    // Face ID was locked by the system after repeated failures — only the passcode can unlock it (enforced by the system).
                    self?.authNotice = "Face ID is locked. Enter your device passcode to unlock."
                }
                self?.isLocked = !success
            }
        }
    }
}

/// Lock screen overlay: full-screen cover + unlock button (tapping triggers Face ID).
struct CompanionLockView: View {
    @ObservedObject var appLock: CompanionAppLock

    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.shield")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("TermiPad Companion is locked")
                    .font(.headline)
                Button("Unlock") {
                    appLock.requestUnlock()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("companion-applock-unlock")
            }
        }
        // Do not trigger Face ID automatically in onAppear — the system auth prompt races the overlay in the same frame
        // and gets hidden behind it (observed by the user on 2026-09-24). The user taps "Unlock" to bring it up.
    }
}

struct DiscoveredMac: Equatable {
    let serviceName: String
}

@MainActor
final class CompanionPairingClient: ObservableObject {
    enum Phase: Equatable {
        case idle
        case noCredentials                // first use — pairing required
        case paired(credentials: CompanionPairingCredentials)  // credentials exist, resume is possible
        case browsing                     // NWBrowser is searching
        case connecting(DiscoveredMac)
        case verifyFingerprint(DiscoveredMac, fingerprint: String, isResume: Bool)
        case awaitingAck(isResume: Bool)
        case listingTools(DiscoveredMac)
        case toolSummaries([MobileToolSummary])
        case requestingLaunch(String)
        case launchResult(accepted: Bool, message: String?)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published var pairingCodeInput = ""
    @Published var deviceName = "iPhone"
    /// M2b-1 task session page data (docs/m2b-remote-task-console-design.md §6):
    /// render the session page whenever it is non-empty — data-driven rather than phase-driven, so that during polling
    /// the browsing/connecting states do not make the view flicker. In memory only, never written to disk (defense line 1).
    @Published private(set) var consoleEntries: [MobileSessionEntry] = []

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var pendingMacHello: MobilePairingHandshake.MacHello?
    private var pendingIdentity: MobilePairingIdentity?
    private var pendingPairingCode: String?
    private var pendingPhoneNonce: Data?
    private var pendingSessionKey: SymmetricKey?
    private var capturedServiceName: String?
    /// When non-nil, send requestLaunch after resume (instead of listTools).
    private var pendingLaunchRequest: (toolID: UUID, name: String)?
    /// M2b-1: when non-nil, send getTaskStatus after resume (session polling request).
    private var pendingConsoleRequest = false
    // M2b-1 session polling state (design §6: 3-second interval, serial — the next round is scheduled only after the previous
    // response (or timeout), so requests never overlap; active only while the app is in the foreground).
    private var consolePollWorkItem: DispatchWorkItem?
    private var consolePollingActive = false
    /// Set after a manual "back" or when the page is hidden; restarted on entering the session page.
    private var consoleDismissed = false
    // M2a connection orchestration state (LAN first / tailnet fallback / explicit timeout copy).
    private var tailnetFallbackWorkItem: DispatchWorkItem?
    private var browseTimeoutWorkItem: DispatchWorkItem?
    private var lanConnectStarted = false
    private var tailnetAttemptInFlight = false
    /// Pseudo service name for the tunnel path — connect() uses it to choose parameters without an interface constraint (tailnet traffic goes through
    /// Tailscale's utun interface, which M1's .wifi constraint would block). ContentView also uses it
    /// to pick the "connecting" copy.
    static let tailnetServiceName = "TermiPad-tailnet"
    private let queue = DispatchQueue(label: "com.termipad.companion.network", qos: .userInitiated)

    init() {
        if let credentials = CompanionPairingStore.loadCredentials() {
            phase = .paired(credentials: credentials)
        } else {
            phase = .noCredentials
        }
    }

    // MARK: - Public actions

    func startBrowsing() {
        stopAll()
        startBrowsingInternal()
    }

    // MARK: - M2b-1 task sessions (docs/m2b-remote-task-console-design.md §6)

    /// Enter the session page: fetch one round immediately, then poll every 3 seconds on success. Once data arrives,
    /// consoleEntries is non-empty — the session page renders itself from that.
    func openTaskConsole() {
        consoleDismissed = false
        guard !consolePollingActive else { return }
        startConsolePollCycle()
    }

    /// Leave the session page: stop polling (the connection closes naturally under the "one connection, one request" model).
    func closeTaskConsole() {
        consoleDismissed = true
        consolePollWorkItem?.cancel()
        consolePollWorkItem = nil
    }

    private func startConsolePollCycle() {
        consolePollingActive = true
        guard let credentials = currentCredentials,
              let endpoint = credentials.tailnetEndpoint, !endpoint.isEmpty
                || phaseIsConnectedOrBrowsing else {
            // No endpoint and not in near-field range — fall back to the existing browse flow.
            consolePollingActive = false
            startBrowsing()
            return
        }
        pollConsoleOnce()
    }

    private func pollConsoleOnce() {
        guard consolePollingActive, !consoleDismissed else { return }
        let serviceName = Self.tailnetServiceName
        let directAddress = currentCredentials?.tailnetEndpoint
        // Connection orchestration reuses the existing path: resume handshake → getTaskStatus request/response.
        // The session polling request is sent after resume completes (pendingConsoleRequest).
        pendingConsoleRequest = true
        connect(to: serviceName, directAddress: directAddress)
        Self.diag("Session polling: connecting to Mac (\(directAddress ?? "LAN"))")
    }

    /// Called after the previous round's response/failure: schedule the next round 3 seconds later (serial, never overlapping).
    private func scheduleNextConsolePoll() {
        guard consolePollingActive, !consoleDismissed else { return }
        consolePollWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.pollConsoleOnce() }
        }
        consolePollWorkItem = work
        queue.asyncAfter(deadline: .now() + 3, execute: work)
    }

    private var phaseIsConnectedOrBrowsing: Bool {
        if case .browsing = phase { return true }
        if case .connecting = phase { return true }
        return false
    }

    private func startBrowsingInternal() {
        let browser = NWBrowser(
            for: .bonjour(type: MobilePairingCrypto.bonjourServiceType, domain: nil),
            using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Self.diag("browse results=\(results.count) metadata=\(results.first?.metadata)")
            guard let self else { return }
            // Race guard (2026-09-10): ignore new browse results during the fingerprint-confirmation and awaiting-ack phases
            // — a reconnect would overwrite pendingMacHello/pendingIdentity/pendingNonce,
            // and the pairing the user then submits would mix key material from two connection rounds (real-device test: the Mac's
            // "pairing accepted" and the phone's decryption failure appeared in the same second — that is this race). phase is
            // a MainActor-isolated property — the closure runs on the queue and reads it via the main thread.
            Task { @MainActor [weak self] in
                guard let self else { return }
                if case .verifyFingerprint = self.phase { return }
                if case .awaitingAck = self.phase { return }
                self.handleBrowseResults(results)
            }
        }
        browser.stateUpdateHandler = { [weak self] newState in
            Self.diag("browser state=\(newState)")
            guard let self else { return }
            Task { @MainActor in
                if case .failed(let error) = newState {
                    self.stopAll()
                    self.phase = .failed(error.localizedDescription)
                }
            }
        }
        browser.start(queue: queue)
        self.browser = browser
        Self.diag("browsing started for \(MobilePairingCrypto.bonjourServiceType)")
        phase = .browsing
        // M2a: LAN first, tailnet fallback, explicit copy on timeout — no endless spinner.
        lanConnectStarted = false
        tailnetAttemptInFlight = false
        scheduleTailnetFallbackIfNeeded()
        scheduleBrowseTimeout()
    }

    /// Main-thread handling of browse results (extracted from the closure on 2026-09-10 — the closure runs on the queue,
    /// and the phase check must hop back to the MainActor). On iOS 26 browse results carry no TXT (metadata
    /// is always .none); resolving the .service endpoint gets stuck in preparing. The Mac encodes its LAN address in
    /// the instance name (TermiPad-192-168-2-81), so here we recover the IP from the name and connect directly.
    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        guard let first = results.first,
              case .service(let name, _, _, _) = first.endpoint else { return }
        guard let directAddress = Self.directAddress(fromServiceName: name) else {
            Self.diag("Instance name has no LAN address (\(name)) — waiting for the Mac to restart its pairing advertisement")
            return
        }
        Self.diag("Recovered direct address \(directAddress) from the instance name")
        connect(to: name, directAddress: directAddress)
    }

    /// M2a connection orchestration (docs/m2-secure-remote-session-design.md §3):
    /// if 6 seconds of browsing find nothing and the credentials hold a remote endpoint → give up LAN browsing and connect directly over the tailnet.
    private func scheduleTailnetFallbackIfNeeded() {
        tailnetFallbackWorkItem?.cancel()
        guard let endpoint = currentCredentials?.tailnetEndpoint, !endpoint.isEmpty else { return }
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.fallbackToTailnet(endpoint: endpoint) }
        }
        tailnetFallbackWorkItem = work
        queue.asyncAfter(deadline: .now() + 6, execute: work)
    }

    private func fallbackToTailnet(endpoint: String) {
        // Only precondition: the LAN is not connected yet (lanConnectStarted is set only when the LAN TCP connection is ready)
        // and no tailnet attempt is in flight. Do not decide by phase — for the immediate switch triggered by .waiting,
        // phase is already .connecting at this point, so checking for browsing would block the dial forever
        // (observed 2026-09-09: the log fired twice but no dial ever went out).
        guard !lanConnectStarted, !tailnetAttemptInFlight else { return }
        Self.diag("LAN unavailable, switching to the remote tailnet \(endpoint)")
        tailnetFallbackWorkItem?.cancel()
        tailnetFallbackWorkItem = nil
        browseTimeoutWorkItem?.cancel()
        browseTimeoutWorkItem = nil
        browser?.cancel()
        browser = nil
        tailnetAttemptInFlight = true
        connect(to: Self.tailnetServiceName, directAddress: endpoint)
    }

    /// Still in .browsing after 10 seconds (and no tailnet fallback in flight) → explicit failure copy.
    private func scheduleBrowseTimeout() {
        browseTimeoutWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, case .browsing = self.phase, !self.tailnetAttemptInFlight else { return }
                let hasTailnet = !(self.currentCredentials?.tailnetEndpoint ?? "").isEmpty
                self.stopAll()
                self.phase = .failed(hasTailnet
                    ? "No Mac found on the same Wi-Fi, and the remote tailnet channel did not connect either. Make sure the Mac is on, TermiPad is running, and Tailscale is online on both devices."
                    : "No Mac found on the same Wi-Fi, and remote access is not enabled. Make sure both devices are on the same Wi-Fi and pairing is enabled on the Mac; to use it away from home, turn on “Settings → Mobile Companion → Remote Access” on the Mac (requires Tailscale).")
            }
        }
        browseTimeoutWorkItem = work
        queue.asyncAfter(deadline: .now() + 10, execute: work)
    }

    func stopBrowsing() {
        stopAll()
        refreshFromKeychain()
    }

    /// A paired user tapped "Refresh Tool Catalog" — use the resume handshake.
    func resumeAndFetchTools() {
        guard case .paired(let credentials) = phase else {
            startBrowsing()
            return
        }
        guard let identity = CompanionPairingStore.loadIdentity() else {
            // Credentials are corrupted: clear them and go back to first-time pairing.
            CompanionPairingStore.clear()
            phase = .noCredentials
            return
        }
        startBrowsing()
    }

    /// A first-time user tapped "Start Searching" — use the pairing handshake.
    func confirmFingerprintAndPair() {
        guard case .verifyFingerprint(_, _, isResume: false) = phase,
              let macHello = pendingMacHello,
              let identity = pendingIdentity else { return }
        let code = pairingCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.utf8.count == MobilePairingCrypto.pairingCodeDigitCount,
              code.allSatisfy(\.isNumber) else {
            phase = .failed("The pairing code must be 6 digits.")
            return
        }
        let name = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            phase = .failed("The device name cannot be empty.")
            return
        }
        let phoneNonce = MobilePairingCrypto.generateNonce()
        pendingPairingCode = code
        pendingPhoneNonce = phoneNonce
        let hello = MobilePairingHandshake.PhoneHello(
            protocolVersion: MobilePairingHandshake.currentProtocolVersion,
            phonePublicKey: (try? identity.publicKeyData()) ?? Data(),
            phoneNonce: phoneNonce,
            pairingCode: code,
            deviceName: name)
        do {
            let frame = MobilePairingFrame.encode(try JSONEncoder().encode(hello))
            phase = .awaitingAck(isResume: false)
            guard let connection else {
                phase = .failed("The connection was lost.")
                return
            }
            connection.send(content: frame, completion: .contentProcessed { [weak self] error in
                Task { @MainActor in
                    guard let self else { return }
                    if error != nil {
                        self.phase = .failed("Failed to send the pairing request.")
                        self.stopConnection()
                        return
                    }
                    self.receiveOneMessage { data in
                        Task { @MainActor in self.handlePairingAck(data) }
                    }
                }
            })
        } catch {
            phase = .failed(error.localizedDescription)
            stopConnection()
        }
    }

    /// The phone taps a tool card to send a launch request (§3.3.2) — via the resume channel.
    /// Mind the order: stopAll inside startBrowsing clears pendingLaunchRequest,
    /// so the flag must be written again after stopAll (in the returned closure).
    func requestLaunch(_ summary: MobileToolSummary) {
        let launch = (toolID: summary.id, name: summary.displayName)
        stopAll()
        pendingLaunchRequest = launch
        startBrowsingInternal()
    }

    // MARK: - M2b-3 new task submission (docs/m2b-remote-task-console-design.md §6)

    /// Catalog data (listScopes / listFixedTasks results) — in memory only.
    @Published private(set) var consoleScopes: [MobileScopeSummary] = []
    @Published private(set) var consoleFixedTasks: [MobileFixedTaskSummary] = []
    /// Catalog fetch in progress (the UI shows a progress bar — 2026-09-10 user feedback: "no response for a long time"
    /// with no visual feedback at all).
    @Published private(set) var isFetchingCatalog = false
    /// When non-nil, send requestTaskProposal (kind + scopeID) after resume.
    private var pendingTaskProposal: (kind: String, scopeID: UUID, title: String)?

    /// Open the "New Task" page: fetch the catalog in two rounds, scopes + fixedTasks.
    /// Uses the full LAN-first → tailnet-fallback orchestration (2026-09-10 user feedback: connecting directly
    /// to the tailnet pseudo service name may fail on the same Wi-Fi with no fallback — no response for a long time).
    func openNewTaskForm() {
        stopAll()
        pendingCatalogRequests = 2
        isFetchingCatalog = true
        startBrowsingInternal()
    }

    /// Catalog rounds: after listScopes returns, fetch listFixedTasks next (one connection, one request).
    private var pendingCatalogRequests = 0

    /// Submit a task (the submit button on the New Task page).
    func submitTaskProposal(kind: String, scopeID: UUID, title: String) {
        stopAll()
        pendingTaskProposal = (kind, scopeID, title)
        startBrowsingInternal()
    }

    /// Task submission receipt → check status directly on the session page (the task shows up in polling).
    @Published private(set) var lastTaskProposalResult: MobileTaskProposalResponse?

    /// Reconnect entry point for the second catalog round (listFixedTasks) — the new round goes through the full browse
    /// orchestration (LAN first → tailnet fallback) and does not connect straight to the tailnet (on the same Wi-Fi utun
    /// may be unreachable with no fallback — 2026-09-10 user test: "no response for a long time").
    private func fetchNextCatalogRound() {
        guard pendingCatalogRequests > 0 else { return }
        startBrowsingInternal()
    }

    /// "What to send this round" for the catalog fetch: pendingCatalogRequests==2 → listScopes
    /// (first round), ==1 → listFixedTasks (second round). Derived from the same round counter, so rounds cannot get crossed.
    private var pendingCatalogOperation: PairedDeviceOperation? {
        switch pendingCatalogRequests {
        case 2: return .listScopes
        case 1: return .listFixedTasks
        default: return nil
        }
    }

    /// M2c: task cancellation from the phone (the stop button on a running entry in the session page).
    private var pendingCancelTask: (taskIntentID: UUID, title: String)?
    private var pendingStreamRequest = false
    private var pendingStreamClose = false
    private var pendingStreamCloseTaskID: UUID?

    /// M4-3 submit an interaction choice: uses one short-lived connection (the long-lived stream connection stays up — on the Mac,
    /// respondInteraction is a separate request/response).
    func submitInteractionSelection(_ selection: String) {
        guard let taskID = streamingTaskID else { return }
        pendingInteraction = nil
        pendingInteractionResponse = (taskID, selection)
        // The long-lived stream connection is kept; the response goes over startBrowsing's new connection.
        startBrowsingInternal()
    }

    // MARK: M4 interactive session stream (docs/m4-interactive-session-design.md §6)

    /// Streamed output buffer (in memory only; cleared when the window closes or on unsubscribe).
    @Published private(set) var streamText: String = ""
    /// Stream state (updates the UI when the task-finished push arrives).
    @Published private(set) var streamState: String?
    /// Stream connecting (thin progress bar at the top of the detail page).
    @Published private(set) var isStreaming = false
    /// Current stream task (detail page context).
    private(set) var streamingTaskID: UUID?
    /// Bytes consumed so far (for resuming after a reconnect).
    private var streamConsumedOffset = 0
    /// Reference to the long-lived stream connection (distinct from the request/response connection — closed explicitly on unsubscribe / screen lock).
    private var streamConnection: NWConnection?
    /// Stream receive buffer (handles coalesced frames during decoding).
    private var streamReceiveBuffer = Data()
    /// M4-3 pending interaction point (the detail page renders a choice card).
    @Published private(set) var pendingInteraction: MobileStreamInteraction?
    /// Interaction response sent flag.
    private var pendingInteractionResponse: (taskID: UUID, selection: String)?

    /// Start a task cancellation: via the resume channel (one connection, one request, one response).
    func cancelTask(taskIntentID: UUID, title: String) {
        stopAll()
        pendingCancelTask = (taskIntentID, title)
        startBrowsingInternal()
    }

    // MARK: M4 stream subscription (called on entering/leaving the session detail page)

    /// Enter the detail page: subscribe to the task output stream (precondition = the daily remote window is open).
    func openStream(taskID: UUID) {
        // Note: **do not use stopAll** — it clears pendingIdentity, which the resume flow
        // needs; once it was cleared, handleMacResumeHello(nil) wrongly concluded "credentials were revoked"
        // and wiped the keychain credentials too (2026-09-19 real device: the root cause of every detail-page subscription dropping).
        // Here we only need to stop the browser/connection and keep the identity state.
        browser?.cancel()
        browser = nil
        stopConnection()
        // Cancel the old long-lived stream connection too — otherwise its auto-reconnect races the new subscription
        // (observed 2026-09-22: two subscription acceptances alternated).
        streamConnection?.cancel()
        streamConnection = nil
        streamReceiveBuffer.removeAll()
        streamingTaskID = taskID
        streamText = ""
        streamState = nil
        streamConsumedOffset = 0
        pendingStreamRequest = true
        isStreaming = true
        startBrowsingInternal()
    }

    /// Leave the detail page: unsubscribe and clear the buffer.
    func closeStream() {
        guard let taskID = streamingTaskID else { return }
        streamingTaskID = nil
        isStreaming = false
        streamText = ""
        streamState = nil
        // Unsubscribe over one short-lived connection (if the stream connection is already dead).
        if streamConnection == nil {
            pendingStreamClose = true
            pendingStreamCloseTaskID = taskID
            startBrowsingInternal()
        } else {
            sendStreamClose(on: streamConnection!, taskID: taskID)
        }
    }

    /// Unpair — clear the Keychain and go back to first-time pairing.
    func unpair() {
        CompanionPairingStore.clear()
        stopAll()
        phase = .noCredentials
    }

    // MARK: - Connection and handshake

    private func connect(to serviceName: String, directAddress: String?) {
        let endpoint: NWEndpoint
        if let directAddress,
           let separatorIndex = directAddress.lastIndex(of: ":"),
           let port = UInt16(directAddress[directAddress.index(after: separatorIndex)...]) {
            // TXT direct path: the IP:port was advertised by the Mac, so skip .service resolution
            // (on iOS 26 that resolution gets stuck in preparing forever).
            let host = NWEndpoint.Host(String(directAddress[..<separatorIndex]))
            endpoint = NWEndpoint.hostPort(host: host, port: NWEndpoint.Port(rawValue: port)!)
            Self.diag("direct connect via TXT \(directAddress)")
        } else {
            endpoint = NWEndpoint.service(
                name: serviceName,
                type: MobilePairingCrypto.bonjourServiceType,
                domain: "local.",
                interface: nil)
            Self.diag("fallback to service endpoint for \(serviceName)")
        }
        let connection: NWConnection
        if serviceName == Self.tailnetServiceName {
            // Remote tailnet path: no interface constraint — traffic is carried by Tailscale's utun interface,
            // which the .wifi constraint (used by M1 against spoofing) would block.
            connection = NWConnection(to: endpoint, using: Self.tunnelParameters())
        } else {
            // Note: do not set lanConnectStarted here — "LAN is connected" only holds once
            // TCP is actually ready (see the .ready branch). If dialing set the flag,
            // a dead .waiting(ENETDOWN) connection would also turn it true, and the later ENETDOWN
            // immediate switch to the tailnet would be blocked by the guard in fallbackToTailnet (2026-09-10
            // cellular test: the fallback log fired but "switching to the remote tailnet" never appeared).
            connection = NWConnection(to: endpoint, using: Self.wifiParameters())
        }
        Self.diag("connecting to \(serviceName)")
        // Still in preparing after 10 seconds counts as a failure — route unreachable / interface mismatch; do not leave the user with an endless spinner.
        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, case .connecting = self.phase else { return }
                Self.diag("connection timeout in preparing")
                self.stopConnection()
                self.phase = .failed(serviceName == Self.tailnetServiceName
                    ? "Remote connection timed out: make sure the Mac is on, TermiPad is running, and Tailscale is online on both devices."
                    : "Connection timed out: the Mac is unreachable. Make sure both devices are on the same Wi-Fi and pairing is enabled on the Mac.")
            }
        }
        queue.asyncAfter(deadline: .now() + 10, execute: timeoutWorkItem)
        connection.stateUpdateHandler = { [weak self, timeoutWorkItem] newState in
            Self.diag("connection state=\(newState)")
            if case .ready = newState { timeoutWorkItem.cancel() }
            guard let self else { return }
            Task { @MainActor in
                switch newState {
                case .ready:
                    self.phase = .connecting(DiscoveredMac(serviceName: serviceName))
                    self.capturedServiceName = serviceName
                    // "LAN is connected" only holds here: TCP is actually ready (a dead .waiting
                    // connection never gets this far). The tailnet pseudo service name does not count as LAN.
                    if serviceName != Self.tailnetServiceName {
                        self.lanConnectStarted = true
                    }
                    self.receiveOneMessage { data in
                        Task { @MainActor in self.handleMacHello(data) }
                    }
                case .failed(let error):
                    self.stopConnection()
                    self.phase = .failed(error.localizedDescription)
                case .waiting(let error):
                    // POSIX 50 (Network is down) = the current interface has no network (e.g. after turning Wi-Fi off, before
                    // cellular takes over / the VPN becomes active). The LAN is dead — switch to the tailnet fallback immediately
                    // instead of waiting for the 6-second timer. Clear lanConnectStarted as well: this dead
                    // connection was never ready, so it does not count as "LAN is connected" (2026-09-10 cellular test:
                    // the leftover flag blocked the guard in fallbackToTailnet).
                    if Self.isNetworkDown(error) {
                        self.lanConnectStarted = false
                    }
                    if !self.tailnetAttemptInFlight, Self.isNetworkDown(error),
                       let endpoint = self.currentCredentials?.tailnetEndpoint, !endpoint.isEmpty {
                        Self.diag("LAN interface has no network (\(error.localizedDescription)), switching to the remote tailnet immediately")
                        self.stopConnection()
                        self.fallbackToTailnet(endpoint: endpoint)
                    }
                default:
                    break
                }
            }
        }
        connection.start(queue: queue)
        self.connection = connection
    }

    private func handleMacHello(_ data: Data?) {
        guard let data else {
            phase = .failed("No handshake message received from the Mac.")
            stopConnection()
            return
        }
        do {
            let macHello = try JSONDecoder().decode(MobilePairingHandshake.MacHello.self, from: data)
            guard macHello.protocolVersion == MobilePairingHandshake.currentProtocolVersion else {
                phase = .failed("The Mac's protocol version is incompatible.")
                stopConnection()
                return
            }
            pendingMacHello = macHello
            // Whether credentials exist must be checked in the Keychain, not via phase — connect() has already set
            // phase to .connecting on ready, so checking phase would mean the resume path never triggers
            // and every attempt bounces back to the first-time pairing screen (a pitfall hit on a real device).
            if let credentials = CompanionPairingStore.loadCredentials() {
                // Already paired: take the resume path and verify the Mac public-key fingerprint == the anchor from first pairing.
                let currentFingerprint = macHello.fingerprint
                Self.diag("Credentials found; Mac fingerprint \(currentFingerprint == credentials.macFingerprint ? "matches" : "does not match")")
                if currentFingerprint == credentials.macFingerprint {
                    // Trust anchor matches — send the resume hello automatically (no fingerprint confirmation needed, since it was checked by eye last time).
                    pendingIdentity = CompanionPairingStore.loadIdentity()
                    guard let identity = pendingIdentity else {
                        CompanionPairingStore.clear()
                        phase = .noCredentials
                        return
                    }
                    let phoneNonce = MobilePairingCrypto.generateNonce()
                    pendingPhoneNonce = phoneNonce
                    let resume = MobilePairingHandshake.PhoneResumeHello(
                        protocolVersion: MobilePairingHandshake.currentProtocolVersion,
                        deviceID: credentials.deviceID,
                        phonePublicKey: (try? identity.publicKeyData()) ?? Data(),
                        phoneNonce: phoneNonce)
                    let frame = MobilePairingFrame.encode(try JSONEncoder().encode(resume))
                    phase = .awaitingAck(isResume: true)
                    connection?.send(content: frame, completion: .contentProcessed { [weak self] error in
                        Task { @MainActor in
                            guard let self else { return }
                            if error != nil {
                                self.phase = .failed("Failed to send the resume request.")
                                self.stopConnection()
                                return
                            }
                            // On the resume path the Mac sends a plaintext MacResumeHello — reset and receive one frame.
                            self.receiveOneMessage { data in
                                Task { @MainActor in self.handleMacResumeHello(data) }
                            }
                        }
                    })
                } else {
                    // Another TermiPad on the same network is pretending to be the Mac we paired with — per the security policy, go back to the pairing flow
                    // and have the user compare fingerprints by eye to confirm it is a new Mac.
                    pendingIdentity = MobilePairingIdentity.generate()
                    phase = .verifyFingerprint(
                        DiscoveredMac(serviceName: capturedServiceName ?? "TermiPad"),
                        fingerprint: currentFingerprint,
                        isResume: false)
                }
            } else {
                // First-time pairing path: the user must confirm the fingerprint by eye.
                Self.diag("No credentials — first-time pairing path")
                pendingIdentity = MobilePairingIdentity.generate()
                phase = .verifyFingerprint(
                    DiscoveredMac(serviceName: capturedServiceName ?? "TermiPad"),
                    fingerprint: macHello.fingerprint,
                    isResume: false)
            }
        } catch {
            phase = .failed("The Mac's handshake message could not be parsed.")
            stopConnection()
        }
    }

    private func handlePairingAck(_ data: Data?) {
        Self.diag("Received pairing ack: \(data?.count ?? 0) bytes")
        // Race guard: while the code is being entered, a browse callback may reopen the connection and overwrite the pending state — when the old connection's
        // ack arrives, pendingMacHello is no longer its MacHello (nonce mismatch
        // → a different derived key → decryption must fail; real-device case on 2026-09-10). A pending
        // ack belongs only to the connection that started it: new browse results received during awaitingAck
        // are simply ignored (the browse handler below intercepts them synchronously).
        guard let data,
              let macHello = pendingMacHello,
              let identity = pendingIdentity,
              let code = pendingPairingCode,
              let phoneNonce = pendingPhoneNonce else {
            phase = .failed("No pairing result received.")
            stopConnection()
            return
        }
        do {
            // Derive the session key with the same formula as the Mac; the ack is ciphertext — failing to decrypt it means the peer is not the Mac holding
            // that private key, or the pairing codes differ.
            let key = try identity.sessionKey(
                peerPublicKeyData: macHello.macPublicKey,
                pairingCode: code,
                macNonce: macHello.macNonce,
                phoneNonce: phoneNonce)
            let ack = try MobilePairingEnvelope.openAck(data, using: key)
            guard ack.accepted else {
                phase = .failed("The Mac rejected this pairing.")
                stopConnection()
                return
            }
            // Persist the credentials — the deviceID is issued by the Mac.
            let credentials = CompanionPairingCredentials(
                deviceID: ack.deviceID,
                macPublicKey: macHello.macPublicKey,
                macFingerprint: macHello.fingerprint,
                deviceName: deviceName)
            try CompanionPairingStore.save(identity: identity, credentials: credentials)
            Self.diag("Pairing complete, credentials saved (deviceID=\(ack.deviceID))")
            stopConnection()
            phase = .paired(credentials: credentials)
        } catch {
            // 2026-09-10 real-device investigation: the Mac's "pairing accepted" and the phone's decryption failure happened in the same second
            // — the two sides derived different session keys. Log a digest of the derivation inputs to compare both sides (nonce /
            // public key are public material, so this is safe). Temporarily logging pairingCode during diagnosis is the minimal way to check
            // transport consistency (in the same-network visual-comparison scenario the code is shown on screen anyway).
            func hexPrefix(_ data: Data, _ count: Int) -> String {
                data.prefix(count).map { String(format: "%02x", $0) }.joined()
            }
            let phonePubHex = ((try? identity.publicKeyData()) ?? Data()).prefix(6)
                .map { String(format: "%02x", $0) }.joined()
            Self.diag("ack verification failed: \(error.localizedDescription)")
            Self.diag("Derivation input digest: macPub=\(hexPrefix(macHello.macPublicKey, 6)) macNonce=\(hexPrefix(macHello.macNonce, 4)) phoneNonce=\(hexPrefix(phoneNonce, 4)) code=\(code) phonePub=\(phonePubHex)")
            phase = .failed("Pairing result verification failed: the Mac identity or the pairing code does not match.")
            stopConnection()
        }
    }

    private func handleMacResumeHello(_ data: Data?) {
        guard let data,
              let credentials = currentCredentials,
              let identity = pendingIdentity,
              let phoneNonce = pendingPhoneNonce else {
            // The Mac can drop the connection silently for many reasons: revocation / expiry / transient jitter / rate limiting. Do not clear the credentials
            // (2026-09-19 real device: a misjudgment under the openStream race wiped the credentials and dropped every
            // subscription). Show explicit copy so the user can retry; if it really was revoked, the next action is still rejected,
            // and the Mac's diagnostic log can be checked then.
            Self.diag("resume received no MacResumeHello — the connection was closed by the Mac (reason unknown)")
            stopConnection()
            phase = .failed("The Mac closed the connection. Please try again. If this keeps happening, check the pairing status on the Mac.")
            return
        }
        do {
            let macResume = try JSONDecoder().decode(MobilePairingHandshake.MacResumeHello.self, from: data)
            // Second check: the public key the Mac sends back must equal the one we stored (stops a MITM from swapping the peer during resume).
            guard macResume.macPublicKey == credentials.macPublicKey else {
                phase = .failed("The Mac's public key does not match the one from first pairing.")
                CompanionPairingStore.clear()
                stopConnection()
                return
            }
            let key = try identity.resumeSessionKey(
                peerPublicKeyData: credentials.macPublicKey,
                macNonce: macResume.macNonce,
                phoneNonce: phoneNonce)
            pendingSessionKey = key
            // M2a: persist the remote endpoint issued by the Mac (bootstrapped on the same network, zero steps when away).
            // Write nil back too — when the Mac turns remote access off, this clears the phone's old endpoint.
            if macResume.tailnetEndpoint != credentials.tailnetEndpoint {
                var updated = credentials
                updated.tailnetEndpoint = macResume.tailnetEndpoint
                try? CompanionPairingStore.save(identity: identity, credentials: updated)
                Self.diag("Remote endpoint updated: \(macResume.tailnetEndpoint ?? "off")")
            }
            // Send the request right away — one connection, one request, one response. Priority: requestLaunch >
            // getTaskStatus (session polling) > listTools.
            // Build the request and grab the connection first, and only then switch phase: currentDiscoveredMac only has a value in
            // .connecting/.awaitingAck, so switching to .requestingLaunch early would cause
            // the whole send block to be skipped (the frame would never go out).
            let request: MobilePairingRequest
            if let launch = pendingLaunchRequest {
                Self.diag("MacResumeHello verified, sending requestLaunch tool=\(launch.name)")
                request = MobilePairingRequest(operation: .requestLaunch, requestID: UUID(), toolID: launch.toolID)
            } else if let proposal = pendingTaskProposal {
                Self.diag("MacResumeHello verified, sending requestTaskProposal kind=\(proposal.kind)")
                request = MobilePairingRequest(
                    operation: .requestTaskProposal, requestID: UUID(), toolID: nil,
                    taskKind: proposal.kind, projectScopeID: proposal.scopeID)
            } else if let catalog = pendingCatalogOperation {
                Self.diag("MacResumeHello verified, sending \(catalog.rawValue) (catalog fetch, \(pendingCatalogRequests) round(s) left)")
                request = MobilePairingRequest(operation: catalog, requestID: UUID(), toolID: nil)
            } else if let cancel = pendingCancelTask {
                Self.diag("MacResumeHello verified, sending cancelTask task=\(cancel.taskIntentID)")
                request = MobilePairingRequest(
                    operation: .cancelTask, requestID: UUID(), toolID: nil,
                    taskIntentID: cancel.taskIntentID)
            } else if let response = pendingInteractionResponse {
                Self.diag("MacResumeHello verified, sending respondInteraction selection=\(response.selection)")
                request = MobilePairingRequest(
                    operation: .respondInteraction, requestID: UUID(), toolID: nil,
                    taskIntentID: response.taskID,
                    interactionSelection: response.selection)
            } else if pendingStreamRequest, let streamTask = streamingTaskID {
                Self.diag("MacResumeHello verified, sending openTaskStream task=\(streamTask) offset=\(streamConsumedOffset)")
                request = MobilePairingRequest(
                    operation: .openTaskStream, requestID: UUID(), toolID: nil,
                    taskIntentID: streamTask,
                    streamResumeOffset: streamConsumedOffset > 0 ? streamConsumedOffset : nil)
            } else if pendingStreamClose, let closeTask = pendingStreamCloseTaskID {
                Self.diag("MacResumeHello verified, sending closeTaskStream task=\(closeTask)")
                request = MobilePairingRequest(
                    operation: .closeTaskStream, requestID: UUID(), toolID: nil,
                    taskIntentID: closeTask)
            } else if pendingConsoleRequest {
                Self.diag("MacResumeHello verified, sending getTaskStatus (session polling)")
                request = MobilePairingRequest(operation: .getTaskStatus, requestID: UUID(), toolID: nil)
            } else {
                Self.diag("MacResumeHello verified, sending listTools")
                request = MobilePairingRequest(operation: .listTools, requestID: UUID(), toolID: nil)
            }
            guard let connection, let mac = currentDiscoveredMac else {
                Self.diag("The connection was gone at send time — request dropped")
                phase = .failed("The connection was lost. Please try again.")
                stopConnection()
                return
            }
            let frame = MobilePairingFrame.encode(try MobilePairingEnvelope.seal(request, using: key))
            if let launch = pendingLaunchRequest {
                phase = .requestingLaunch(launch.name)
            } else if pendingInteractionResponse != nil || pendingStreamRequest || pendingStreamClose {
                // Stream requests: the detail page is driven by the isStreaming/streamText data,
                // so phase stays in the list state to avoid flicker.
                phase = .listingTools(mac)
            } else if pendingConsoleRequest {
                // During session polling phase stays in the connecting/list state — the session page is
                // driven by the consoleEntries data, so polling causes no phase flicker.
                phase = .listingTools(mac)
            } else {
                phase = .listingTools(mac)
            }
            connection.send(content: frame, completion: .contentProcessed { [weak self] error in
                Task { @MainActor in
                    guard let self else { return }
                    if error != nil {
                        self.phase = .failed("Failed to send the request.")
                        self.stopConnection()
                        return
                    }
                    Self.diag("Request frame sent (\(request.operation.rawValue)), waiting for the Mac's response")
                    self.receiveOneMessage { data in
                        Task { @MainActor in self.handleResponse(data, connection: connection) }
                    }
                }
            })
        } catch {
            phase = .failed("Resume handshake failed.")
            stopConnection()
        }
    }

    private func handleResponse(_ data: Data?, connection: NWConnection) {
        guard let data, let key = pendingSessionKey else {
            phase = .failed("No response received.")
            stopConnection()
            if consolePollingActive { scheduleNextConsolePoll() }
            return
        }
        // New-task form catalog fetch (two rounds, listScopes → listFixedTasks) and the task submission receipt.
        // Round check: pendingCatalogRequests==2 means this round is scopes, ==1 means this round is tasks.
        if pendingCatalogRequests > 0 {
            do {
                switch pendingCatalogRequests {
                case 2:
                    let scopes = try MobilePairingEnvelope.openScopeSummaries(data, using: key)
                    Self.diag("Scope catalog count=\(scopes.count)")
                    consoleScopes = scopes
                    pendingCatalogRequests = 1
                    stopConnection()
                    // The second round goes through the full browse orchestration (LAN first → tailnet fallback).
                    fetchNextCatalogRound()
                case 1:
                    let tasks = try MobilePairingEnvelope.openFixedTaskSummaries(data, using: key)
                    Self.diag("Fixed task catalog count=\(tasks.count)")
                    consoleFixedTasks = tasks
                    pendingCatalogRequests = 0
                    isFetchingCatalog = false
                    stopConnection()
                default:
                    pendingCatalogRequests = 0
                    isFetchingCatalog = false
                    stopConnection()
                }
            } catch {
                Self.diag("Catalog fetch decryption failed")
                pendingCatalogRequests = 0
                isFetchingCatalog = false
                stopConnection()
            }
            return
        }
        // M4-3 interaction response: the Mac disconnects silently with no receipt frame — just wrap up.
        if let responded = pendingInteractionResponse {
            pendingInteractionResponse = nil
            Self.diag("Interaction response sent: \(responded.selection)")
            stopConnection()
            // If the long-lived stream connection was already closed by stopConnection, auto-reconnect resumes it.
            return
        }
        // M4 stream receipt: openTaskStream accepted → the current connection becomes a long-lived connection running the push receive loop;
        // rejected (including window not open) → stop and show the reason.
        if pendingStreamRequest {
            pendingStreamRequest = false
            do {
                let response = try MobilePairingEnvelope.openStreamResponse(data, using: key)
                guard response.status == .accepted, let start = response.resumeOffset else {
                    Self.diag("Stream subscription rejected: \(response.reason ?? "-")")
                    isStreaming = false
                    streamingTaskID = nil
                    stopConnection()
                    return
                }
                Self.diag("Stream subscription accepted, cursor=\(start)")
                streamConsumedOffset = start
                // The current connection is upgraded to a long-lived stream connection: the receive loop keeps running and pushed chunks are buffered frame by frame.
                streamConnection = connection
                receiveStreamFrames(on: connection)
            } catch {
                Self.diag("Failed to parse the stream receipt")
                isStreaming = false
                streamingTaskID = nil
                stopConnection()
            }
            return
        }
        if pendingStreamClose {
            pendingStreamClose = false
            pendingStreamCloseTaskID = nil
            // Unsubscribe receipt: no content needed, the connection closes naturally.
            stopConnection()
            return
        }
        // M2c task cancellation receipt: both accept and reject give immediate feedback (local status marker).
        if let cancel = pendingCancelTask {
            pendingCancelTask = nil
            do {
                let response = try MobilePairingEnvelope.openTaskProposalResponse(data, using: key)
                Self.diag("Task cancellation receipt status=\(response.status.rawValue) reason=\(response.reason ?? "-")")
                stopConnection()
                // Accepted or not, fetch a session snapshot right away — the running entry will become stopped.
                pendingConsoleRequest = true
                connect(to: Self.tailnetServiceName, directAddress: currentCredentials?.tailnetEndpoint)
            } catch {
                Self.diag("Failed to parse the task cancellation receipt")
                stopConnection()
            }
            _ = cancel
            return
        }
        if let proposal = pendingTaskProposal {
            pendingTaskProposal = nil
            _ = proposal
            do {
                let response = try MobilePairingEnvelope.openTaskProposalResponse(data, using: key)
                Self.diag("Task submission receipt status=\(response.status.rawValue) reason=\(response.reason ?? "-")")
                lastTaskProposalResult = response
                stopConnection()
                // Go to the session page right after submitting to see the status.
                openTaskConsole()
            } catch {
                Self.diag("Failed to parse the task submission receipt")
                stopConnection()
                openTaskConsole()
            }
            return
        }
        // Try the session polling response first: the Mac only returns [MobileSessionEntry] (under the request/response model
        // it is mutually exclusive with the other response types via the pending flags, so it cannot be misidentified).
        if pendingConsoleRequest {
            pendingConsoleRequest = false
            do {
                let entries = try MobilePairingEnvelope.openSessionEntries(data, using: key)
                Self.diag("Session snapshot count=\(entries.count)")
                consoleEntries = entries
                stopConnection()
                scheduleNextConsolePoll()
            } catch {
                Self.diag("Session snapshot decryption failed")
                stopConnection()
                scheduleNextConsolePoll()
            }
            return
        }
        // Try the requestLaunch response first: the Mac only returns MobileLaunchResponse.
        if let launch = pendingLaunchRequest {
            do {
                let response = try MobilePairingEnvelope.openLaunchResponse(data, using: key)
                Self.diag("Launch result status=\(response.status.rawValue)")
                pendingLaunchRequest = nil
                stopConnection()
                switch response.status {
                case .accepted:
                    phase = .launchResult(accepted: true, message: nil)
                case .rejected:
                    phase = .launchResult(accepted: false, message: response.reason)
                }
            } catch {
                pendingLaunchRequest = nil
                stopConnection()
                phase = .failed("Failed to parse the launch request result.")
            }
            _ = launch
            return
        }
        do {
            let summaries = try MobilePairingEnvelope.openToolSummaries(data, using: key)
            Self.diag("Received tool catalog count=\(summaries.count)")
            // Minimal data validation: reject anything with fields beyond the 4 allowed (guards against schema drift on the Mac).
            guard summaries.allSatisfy({ summary in
                summary.iconSymbolName == nil || !(summary.iconSymbolName?.isEmpty ?? true)
            }) else {
                phase = .failed("The tool catalog contains out-of-bounds fields.")
                stopConnection()
                return
            }
            stopConnection()
            phase = .toolSummaries(summaries)
        } catch {
            phase = .failed("Failed to decrypt the tool catalog.")
            stopConnection()
        }
    }

    // MARK: M4 long-lived stream connection receive loop

    /// Continuous receive on the stream connection: decode frames → determine the type (chunk/state/interaction) → update
    /// streamText/state. On disconnect the cursor is kept for resuming after a reconnect (isStreaming stays set;
    /// the detail page's retry button or auto-reconnect triggers a new openTaskStream round).
    private func receiveStreamFrames(on connection: NWConnection) {
        Self.diag("Stream receive loop started")
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] content, _, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if error != nil || (isComplete && content == nil) {
                    Self.diag("Stream connection lost (offset=\(self.streamConsumedOffset)) — auto-reconnecting in 3 seconds")
                    self.streamConnection = nil
                    // Auto-reconnect: resume from the cursor (streamResumeOffset).
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                        Task { @MainActor [weak self] in
                            guard let self, self.isStreaming, self.streamingTaskID != nil,
                                  self.streamConnection == nil else { return }
                            self.pendingStreamRequest = true
                            self.startBrowsingInternal()
                        }
                    }
                    return
                }
                if let content { self.streamReceiveBuffer.append(content) }
                // Decode all complete frames.
                while case .message(let message, let remainder) =
                        MobilePairingFrame.decodeOne(from: self.streamReceiveBuffer) {
                    self.streamReceiveBuffer = remainder
                    self.handleStreamFrame(message)
                }
                if self.streamConnection === connection {
                    self.receiveStreamFrames(on: connection)
                }
            }
        }
    }

    /// Dispatch a single stream frame message.
    private func handleStreamFrame(_ data: Data) {
        Self.diag("Stream frame arrived: \(data.count)B key=\(pendingSessionKey != nil ? "yes" : "no")")
        guard let key = pendingSessionKey, !data.isEmpty else { return }
        // Decrypt once, then tell the frame types apart by their fields (the same decoding the envelope helpers do,
        // without opening the same ciphertext up to three times).
        guard let plaintext = try? MobilePairingCrypto.open(data, using: key) else {
            Self.diag("Unrecognized stream frame — ignored")
            return
        }
        let decoder = JSONDecoder()
        // Try the pushed chunk first (most common); state changes next.
        if let chunk = try? decoder.decode(MobileStreamChunk.self, from: plaintext) {
            streamText += chunk.text
            streamConsumedOffset = chunk.offset + chunk.text.utf8.count
            return
        }
        if let state = try? decoder.decode(MobileStreamStateChange.self, from: plaintext) {
            streamState = state.executionState
            if state.finishedAt != nil {
                // Task finished: keep the text for reading; the connection can be unsubscribed.
                Self.diag("Stream state update: \(state.executionState) exit=\(state.exitCode.map(String.init) ?? "-")")
            }
            return
        }
        // M4-3 interaction request frame: show the choice card.
        if let interaction = try? decoder.decode(MobileStreamInteraction.self, from: plaintext) {
            Self.diag("Received interaction request: \(interaction.prompt.prefix(20))…")
            pendingInteraction = interaction
            return
        }
        Self.diag("Unrecognized stream frame — ignored")
    }

    /// Send the unsubscribe (over the original connection while the stream connection is alive; otherwise over one short-lived connection).
    private func sendStreamClose(on connection: NWConnection, taskID: UUID) {
        guard let key = pendingSessionKey else {
            connection.cancel()
            streamConnection = nil
            return
        }
        let request = MobilePairingRequest(
            operation: .closeTaskStream, requestID: UUID(), toolID: nil,
            taskIntentID: taskID)
        if let frame = try? MobilePairingFrame.encode(MobilePairingEnvelope.seal(request, using: key)) {
            connection.send(content: frame, completion: .contentProcessed { _ in })
        }
        streamConnection = nil
        // Closing the original connection is triggered by the Mac's unsubscribe receipt.
    }

    // MARK: - Diagnostics

    /// Recover the direct address from the Bonjour instance name: the Mac advertises "TermiPad-192-168-2-81",
    /// and the port is the fixed listenerPort. Returns nil when the name has no address (older Mac builds).
    nonisolated private static func directAddress(fromServiceName name: String) -> String? {
        guard let range = name.range(of: "\(MobilePairingCrypto.bonjourServiceName)-") else {
            return nil
        }
        let addressPart = String(name[range.upperBound...])
        let octets = addressPart.split(separator: "-").compactMap { UInt8($0) }
        guard octets.count == 4 else { return nil }
        let host = octets.map(String.init).joined(separator: ".")
        return "\(host):\(MobilePairingCrypto.listenerPort)"
    }

    /// Write to both NSLog and Documents/companion-diag.log — the latter can be pulled via devicectl
    /// appDataContainer without needing the console attached.
    nonisolated private static func diag(_ message: String) {
        NSLog("companion-diag: \(message)")
        let line = "[\(Date())] \(message)\n"
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        let url = dir.appendingPathComponent("companion-diag.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Frame send/receive

    /// Pin the Wi-Fi interface (symmetric with the Mac's listener): avoids resolving to unreachable addresses on VPN/tunnel interfaces.
    nonisolated private static func wifiParameters() -> NWParameters {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .wifi
        return parameters
    }

    /// Remote tailnet connection parameters: no interface constraint (traffic goes through Tailscale's utun).
    private static func tunnelParameters() -> NWParameters {
        NWParameters.tcp
    }

    private func receiveOneMessage(handler: @escaping @Sendable (Data?) -> Void) {
        guard let connection else {
            handler(nil)
            return
        }
        receiveOne(connection: connection, buffer: Data(), handler: handler)
    }

    nonisolated private func receiveOne(
        connection: NWConnection,
        buffer: Data,
        handler: @escaping @Sendable (Data?) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { content, _, isComplete, error in
            var accumulated = buffer
            if let content { accumulated.append(content) }
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
                self.receiveOne(connection: connection, buffer: accumulated, handler: handler)
            case .invalid:
                handler(nil)
            }
        }
    }

    private func stopConnection() {
        connection?.cancel()
        connection = nil
    }

    private func stopAll() {
        tailnetFallbackWorkItem?.cancel()
        tailnetFallbackWorkItem = nil
        browseTimeoutWorkItem?.cancel()
        browseTimeoutWorkItem = nil
        consolePollWorkItem?.cancel()
        consolePollWorkItem = nil
        consolePollingActive = false
        lanConnectStarted = false
        tailnetAttemptInFlight = false
        browser?.cancel()
        browser = nil
        stopConnection()
        pendingMacHello = nil
        pendingIdentity = nil
        pendingPairingCode = nil
        pendingPhoneNonce = nil
        pendingSessionKey = nil
        pendingLaunchRequest = nil
        pendingConsoleRequest = false
        pendingTaskProposal = nil
        pendingCancelTask = nil
        pendingCatalogRequests = 0
        isFetchingCatalog = false
        pendingStreamRequest = false
        pendingStreamClose = false
        pendingStreamCloseTaskID = nil
        pendingInteraction = nil
        pendingInteractionResponse = nil
        streamConnection?.cancel()
        streamConnection = nil
        streamReceiveBuffer.removeAll()
    }

    private func refreshFromKeychain() {
        if let credentials = CompanionPairingStore.loadCredentials() {
            phase = .paired(credentials: credentials)
        } else {
            phase = .noCredentials
        }
    }

    // MARK: - Derived helpers

    private var currentCredentials: CompanionPairingCredentials? {
        if case .paired(let credentials) = phase { return credentials }
        return CompanionPairingStore.loadCredentials()
    }

    /// For the UI: whether the keychain holds a remote endpoint (the browsing copy and failure copy branch on this).
    var hasTailnetEndpoint: Bool {
        !(currentCredentials?.tailnetEndpoint ?? "").isEmpty
    }

    /// For the UI: whether the tool catalog is already in hand (decides when to collapse the top progress bar).
    var hasToolSummaries: Bool {
        if case .toolSummaries = phase { return true }
        return false
    }

    /// POSIX 50 (ENETDOWN): the interface has no network. On iOS this is common in the window after Wi-Fi is turned off and before
    /// cellular/VPN takes over the traffic — a reliable signal that "the LAN is dead".
    private static func isNetworkDown(_ error: NWError) -> Bool {
        if case .posix(let code) = error, code == .ENETDOWN { return true }
        return false
    }

    private var currentDiscoveredMac: DiscoveredMac? {
        if case .connecting(let mac) = phase { return mac }
        // The resume flow has to send listTools as early as the .awaitingAck phase — it used capturedServiceName before.
        if case .awaitingAck = phase, let name = capturedServiceName {
            return DiscoveredMac(serviceName: name)
        }
        return nil
    }

    private var discoveredServiceName: String? {
        if case .connecting(let mac) = phase { return mac.serviceName }
        if case .verifyFingerprint(let mac, _, _) = phase { return mac.serviceName }
        if case .listingTools(let mac) = phase { return mac.serviceName }
        return nil
    }
}
