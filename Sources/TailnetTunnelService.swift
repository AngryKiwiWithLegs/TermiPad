// M2a remote tunnel service (docs/m2-secure-remote-session-design.md §5).
// Integration model: relies on the Tailscale the user installed themselves (a pattern proven by OpenClaw); TermiPad only orchestrates —
// no embedded tailscaled, no home-made WireGuard, Funnel permanently disabled (public exposure red line).
// The Mac opens only one loopback listener bound to 127.0.0.1 (57147), and `tailscale serve --tcp`
// forwards tailnet traffic into it — the port is invisible to the public internet, the LAN, and other virtual interfaces.
// CLI call discipline: fixed absolute path + fixed arguments + no user input concatenated, never through a shell (same as
// EnvironmentReport); this is the only file in the repository allowed to call the tailscale CLI (guarded by verify-macos.sh).
import Foundation
import Network

/// Tunnel endpoint box shared across isolation domains: written by TailnetTunnelService (MainActor),
/// read by MobilePairingService's nonisolated static handshake chain when building MacResumeHello.
/// Protected by an NSLock — the handshake runs on listenerQueue and must not touch MainActor state.
final class TailnetEndpointHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    func set(_ newValue: String?) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

@MainActor
final class TailnetTunnelService: ObservableObject {
    enum TunnelState: Equatable {
        case off
        case detecting
        case ready(endpoint: String)
        case failed(String)
    }

    static let shared = TailnetTunnelService()
    static let tunnelListenerPort: UInt16 = MobilePairingCrypto.tunnelListenerPort
    /// Loopback backend port (internal to the Mac). While tailscaled's serve frontend holds 57147 on the tailnet
    /// side, the kernel refuses a loopback bind to the same port number (EADDRINUSE, reproduced in testing) —
    /// same fix as OpenClaw: the frontend and backend use different ports, and serve forwards tailnet:57147
    /// to 127.0.0.1:57148. The phone only ever sees 57147; the backend port never leaves the Mac.
    static let loopbackBackendPort: UInt16 = 57148
    /// Persistence key for the user preference: once on, the tunnel is restored automatically at every app launch (remote capability is always-on
    /// infrastructure and, unlike pairing mode, needs no on-screen pairing code).
    static let enabledDefaultsKey = "TermiPad.mobileTailnetTunnelEnabled"
    /// Fixed absolute-path allowlist: only the Homebrew and /usr/local install locations are recognized;
    /// PATH is not searched and user-configured paths are not accepted.
    nonisolated static let cliCandidatePaths = [
        "/opt/homebrew/bin/tailscale",
        "/usr/local/bin/tailscale"
    ]

    /// Shared endpoint box read by the handshake chain (static, lives as long as the process).
    nonisolated static let endpointHolder = TailnetEndpointHolder()

    @Published private(set) var state: TunnelState = .off

    private var loopbackListener: NWListener?
    private let listenerQueue = DispatchQueue(label: "com.termipad.tailnet-tunnel", qos: .userInitiated)

    private init() {}

    /// Called at app launch: restores automatically if the user had it on last time.
    func restoreIfNeeded() {
        guard UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey), state == .off else {
            return
        }
        enable()
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.enabledDefaultsKey)
        if enabled {
            enable()
        } else {
            disable()
        }
    }

    /// Enable: detect the CLI → configure serve forwarding → read the tailnet IP → start the loopback listener.
    func enable() {
        guard loopbackListener == nil, state != .detecting else { return }
        state = .detecting
        Task.detached(priority: .userInitiated) { [port = Self.tunnelListenerPort, backend = Self.loopbackBackendPort] in
            let result = Self.configureServe(port: port, backendPort: backend)
            await MainActor.run { self.finishEnable(result: result, port: port) }
        }
    }

    func disable() {
        let hadListener = loopbackListener != nil
        stopLoopbackListener()
        Self.endpointHolder.set(nil)
        state = .off
        if hadListener {
            DiagnosticsStore.shared.record(.remoteTunnelClosed)
        }
        // Revoke the serve forwarding in the background — a failure is only logged to diagnostics; the UI state is already off.
        Task.detached(priority: .utility) { [port = Self.tunnelListenerPort] in
            _ = Self.runFixedCLI(arguments: ["serve", "--tcp=\(port)", "off"])
        }
        // Turning the tunnel off clears the session allowlist — the confirmation-free cache never outlives the channel that authorized it.
        MobileLaunchSession.shared.invalidateAll()
    }

    // MARK: - Enable flow

    private func finishEnable(result: ServeConfigResult, port: UInt16) {
        switch result {
        case .binaryNotFound:
            MobilePairingService.diagMac("Tunnel failed: tailscale CLI not found (fixed-path allowlist)")
            state = .failed("Tailscale was not found. Install it, sign in, and try again (brew install tailscale or the App Store version).")
        case .cliError(let message):
            MobilePairingService.diagMac("Tunnel failed: \(message)")
            state = .failed("Tailscale configuration failed: \(message)")
        case .configured(let endpoint):
            startLoopbackListener(port: Self.loopbackBackendPort, endpoint: endpoint)
        }
    }

    private func startLoopbackListener(port: UInt16, endpoint: String) {
        let parameters = NWParameters.tcp
        // Bind the loopback interface only: the port is invisible to the LAN / public internet / other virtual interfaces, and only tailscaled's
        // serve forwarding can reach it — the strongest form of the "no public ports" red line.
        // Note: requiredLocalEndpoint only applies to outbound connections and has **no effect** on an NWListener's listening
        // bind (it once caused "state is ready but the port was never bound"); the listening bind must use
        // requiredInterfaceType = .loopback (tested 2026-09-08: self-connection succeeded).
        parameters.requiredInterfaceType = .loopback
        // On a quick off→on the old socket is still in TIME_WAIT (same pitfall as M1): without reuse it reports
        // "address already in use", which shows up as the switch always failing the second time it is turned on.
        parameters.allowLocalEndpointReuse = true
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            MobilePairingService.diagMac("Tunnel failed: could not create the loopback listener: \(error.localizedDescription)")
            state = .failed("Failed to start the local listener: \(error.localizedDescription)")
            return
        }
        listener.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            Task { @MainActor in
                if case .failed(let error) = newState {
                    MobilePairingService.diagMac("Tunnel listener failed: \(error.localizedDescription)")
                    self.stopLoopbackListener()
                    Self.endpointHolder.set(nil)
                    self.state = .failed("Tunnel listener error: \(error.localizedDescription)")
                }
            }
        }
        listener.newConnectionHandler = { connection in
            // Shares the same handshake chain as the M1 local network listener — the tunnel accepts only resume requests from already-paired devices;
            // first-time pairing must stay on the same network (the design premise of comparing fingerprints by eye).
            MobilePairingService.beginResumeOnlyHandshake(
                on: connection,
                queue: self.listenerQueue)
        }
        listener.start(queue: listenerQueue)
        loopbackListener = listener
        Self.endpointHolder.set(endpoint)
        state = .ready(endpoint: endpoint)
        DiagnosticsStore.shared.record(.remoteTunnelOpened)
        MobilePairingService.diagMac("Remote tunnel ready: \(endpoint) (loopback listener + tailscale serve forwarding)")
    }

    private func stopLoopbackListener() {
        loopbackListener?.cancel()
        loopbackListener = nil
    }

    // MARK: - CLI orchestration (fixed path + fixed arguments, run on a background queue)

    private enum ServeConfigResult {
        case configured(endpoint: String)
        case binaryNotFound
        case cliError(String)
    }

    nonisolated private static func resolveCLIBinary() -> String? {
        cliCandidatePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Order: serve configures the forwarding → tailscale ip -4 gets the endpoint. Any failed step aborts
    /// (the UI reports the error explicitly, no silent degradation).
    nonisolated private static func configureServe(port: UInt16, backendPort: UInt16) -> ServeConfigResult {
        guard let binary = resolveCLIBinary() else {
            return .binaryNotFound
        }
        guard runFixedCLI(
            arguments: ["serve", "--bg", "--tcp=\(port)", "tcp://127.0.0.1:\(backendPort)"]) != nil else {
            return .cliError("serve forwarding was not configured successfully (make sure Tailscale is signed in)")
        }
        // A successful serve prints the endpoint line; then take this Mac's tailnet IPv4 to build "IP:port".
        guard let ipOutput = runFixedCLI(arguments: ["ip", "-4"]),
              let tailnetIP = ipOutput
                  .split(whereSeparator: \.isNewline)
                  .first?
                  .trimmingCharacters(in: .whitespaces),
              !tailnetIP.isEmpty else {
            return .cliError("Could not read the tailnet IP (make sure Tailscale is connected)")
        }
        return .configured(endpoint: "\(tailnetIP):\(port)")
    }

    /// Run one tailscale subcommand with fixed arguments. Execs the absolute path directly — no PATH search,
    /// no shell, and every argument comes from literals in this file. Returns stdout (with stderr appended);
    /// returns nil on a non-zero exit code.
    nonisolated private static func runFixedCLI(arguments: [String]) -> String? {
        guard let binary = resolveCLIBinary() else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe
        do {
            try process.run()
        } catch {
            return nil
        }
        let stdoutData = pipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return nil
        }
        var output = String(data: stdoutData, encoding: .utf8) ?? ""
        if let stderr = String(data: stderrData, encoding: .utf8), !stderr.isEmpty {
            output += stderr
        }
        return output
    }
}
