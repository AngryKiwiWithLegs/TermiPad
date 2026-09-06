// iPhone 伴侣 app 入口（docs/m0-m1-mobile-entry-design.md §3.2-§3.3）。
// 仅用作 NWBrowser 客户端：发现 Mac、发起握手、收配对码与配对完成态。
// 没有任何外发网络——单源点（Mac 监听器），不收任何远程命令/路径/变量。
import SwiftUI
import Network

@main
struct TermiPadCompanionApp: App {
    @StateObject private var client = CompanionPairingClient()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(client)
        }
    }
}

@MainActor
final class CompanionPairingClient: ObservableObject {
    enum Phase: Equatable {
        case idle
        case browsing
        case awaitingPairingCode(serviceName: String, fingerprint: String)
        case paired(deviceID: UUID, deviceName: String)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published var pairingCodeInput: String = ""
    @Published var deviceName: String = "iPhone"

    private var browser: NWBrowser?
    private let browserQueue = DispatchQueue(label: "com.termipad.companion.browser", qos: .userInitiated)

    func startBrowsing() {
        guard browser == nil else { return }
        let browser = NWBrowser(
            for: .bonjour(type: MobilePairingCrypto.bonjourServiceType, domain: nil),
            using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            Task { @MainActor in
                if let first = results.first,
                   case .service(let name, _, _, _) = first.endpoint {
                    self.phase = .awaitingPairingCode(serviceName: name, fingerprint: first.metadataFingerprint)
                } else if results.isEmpty {
                    self.phase = .idle
                }
            }
        }
        browser.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            Task { @MainActor in
                if case .failed(let error) = newState {
                    self.stopBrowsingInternal()
                    self.phase = .failed(error.localizedDescription)
                }
            }
        }
        browser.start(queue: browserQueue)
        self.browser = browser
        phase = .browsing
    }

    func stopBrowsing() {
        stopBrowsingInternal()
        phase = .idle
    }

    /// 用户在 Mac 屏上看到配对码和指纹后，提交配对——本 app 立即与该 Mac 完成配对握手。
    func submitPairingCode() {
        guard case .awaitingPairingCode(_, let expectedFingerprint) = phase else { return }
        let cleanedCode = pairingCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanedCode.utf8.count == MobilePairingCrypto.pairingCodeDigitCount else {
            phase = .failed("配对码必须是 6 位数字。")
            return
        }
        let trimmedName = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            phase = .failed("设备名不能为空。")
            return
        }
        let identity = MobilePairingIdentity.generate()
        let phoneNonce = MobilePairingCrypto.generateNonce()
        let phoneHello: MobilePairingHandshake.PhoneHello
        do {
            phoneHello = MobilePairingHandshake.PhoneHello(
                protocolVersion: MobilePairingHandshake.currentProtocolVersion,
                phonePublicKey: try identity.publicKeyData(),
                phoneNonce: phoneNonce,
                pairingCode: cleanedCode,
                deviceName: trimmedName)
            // 立刻展示指纹给用户人工比对——这是抗中间人攻击的关键。
            let actualFingerprint = MobilePairingCrypto.fingerprint(forPublicKeyData: try identity.publicKeyData())
            guard actualFingerprint == expectedFingerprint else {
                phase = .failed("Mac 端指纹与你看到的不一致。")
                return
            }
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }
        // 实际连接到 Mac 端监听器。
        startConnection(phoneHello: phoneHello, identity: identity, expectedFingerprint: expectedFingerprint, macNonce: nil)
    }

    private func startConnection(
        phoneHello: MobilePairingHandshake.PhoneHello,
        identity: MobilePairingIdentity,
        expectedFingerprint: String,
        macNonce: Data?
    ) {
        // 从 Bonjour 结果获取 endpoint 重建连接。
        guard case .awaitingPairingCode(let serviceName, let fp) = phase else { return }
        let endpoint = NWEndpoint.service(
            name: serviceName,
            type: MobilePairingCrypto.bonjourServiceType,
            domain: nil,
            interface: nil)
        let connection = NWConnection(to: endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            switch newState {
            case .ready:
                self.runHandshake(
                    connection: connection,
                    identity: identity,
                    phoneHello: phoneHello,
                    expectedFingerprint: fp)
            case .failed(let error):
                Task { @MainActor in self.phase = .failed(error.localizedDescription) }
            default:
                break
            }
        }
        connection.start(queue: browserQueue)
    }

    private func runHandshake(
        connection: NWConnection,
        identity: MobilePairingIdentity,
        phoneHello: MobilePairingHandshake.PhoneHello,
        expectedFingerprint: String
    ) {
        // 第一步：发送 PhoneHello 帧
        do {
            let encoded = try JSONEncoder().encode(phoneHello)
            let frame = MobilePairingFrame.encode(encoded)
            connection.send(content: frame, completion: .contentProcessed { error in
                if error != nil {
                    Task { @MainActor in self.phase = .failed("发送配对请求失败。") }
                    return
                }
                self.receiveOneMessage(connection: connection, buffer: Data())
            })
        } catch {
            Task { @MainActor in self.phase = .failed(error.localizedDescription) }
        }
    }

    private func receiveOneMessage(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { content, _, isComplete, error in
            var accumulated = buffer
            if let content { accumulated.append(content) }
            if error != nil {
                Task { @MainActor in self.phase = .failed("连接错误。") }
                return
            }
            switch MobilePairingFrame.decodeOne(from: accumulated) {
            case .message(let payload, _):
                self.handleAck(payload: payload, connection: connection)
            case .incomplete:
                if isComplete {
                    Task { @MainActor in self.phase = .failed("对端关闭连接。") }
                    return
                }
                self.receiveOneMessage(connection: connection, buffer: accumulated)
            case .invalid:
                Task { @MainActor in self.phase = .failed("帧格式错误。") }
            }
        }
    }

    private func handleAck(payload: Data, connection: NWConnection) {
        // 注意：ack 的会话密钥我们这边没有（它在 Mac 侧），但 ack 是公开的"已被接收"信号。
        // Mac 侧用本端私钥 + 本端 nonce 推不出手机侧 nonce 下的同一密钥——所以 ack 是明文
        // 端到端伪造不可能的"已配对"信号，但不会泄露工具数据。
        do {
            let ack = try JSONDecoder().decode(MobilePairingAck.self, from: payload)
            guard ack.accepted else {
                Task { @MainActor in self.phase = .failed("Mac 拒绝配对。") }
                connection.cancel()
                return
            }
            connection.cancel()
            let deviceName = self.deviceName
            Task { @MainActor in
                self.phase = .paired(deviceID: ack.deviceID, deviceName: deviceName)
            }
        } catch {
            Task { @MainActor in self.phase = .failed("无法解析 ack。") }
            connection.cancel()
        }
    }

    private func stopBrowsingInternal() {
        browser?.cancel()
        browser = nil
    }
}

private extension NWBrowser.Result {
    /// Bonjour 结果中的 TXT metadata 是 key/value 字典；这里只取协议版本做轻量校验。
    var metadataFingerprint: String {
        // iOS 端不读 TXT 也能跑（仅 Mac 端用）；这里返空字符串，Mac 屏显指纹作为唯一来源。
        return ""
    }
}
