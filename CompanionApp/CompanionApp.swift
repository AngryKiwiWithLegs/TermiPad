// iPhone 伴侣 app 入口（docs/m0-m1-mobile-entry-design.md §3.3）。
// 配对流程（与 Mac 端 MobilePairingService 镜像）：
//   1. NWBrowser 发现 _termipad-m1._tcp
//   2. 连接 → 收 MacHello 帧 → 屏显 Mac 指纹，用户与 Mac 屏幕人工比对（抗中间人）
//   3. 用户输入配对码 + 设备名 → 发 PhoneHello
//   4. 收加密 ack → 本地用对称公式推导会话密钥解开 → 配对完成
// 手机端持有会话所需全部输入（自身私钥 + MacHello 里的公钥/nonce + 用户输入的码）。
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

struct DiscoveredMac: Equatable {
    let serviceName: String
}

@MainActor
final class CompanionPairingClient: ObservableObject {
    enum Phase: Equatable {
        case idle
        case browsing
        case connecting(DiscoveredMac)
        case verifyFingerprint(DiscoveredMac, fingerprint: String)
        case awaitingAck
        case paired
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published var pairingCodeInput = ""
    @Published var deviceName = "iPhone"

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var pendingMacHello: MobilePairingHandshake.MacHello?
    private var pendingIdentity: MobilePairingIdentity?
    private var pendingPairingCode: String?
    private var pendingPhoneNonce: Data?
    private let queue = DispatchQueue(label: "com.termipad.companion.network", qos: .userInitiated)

    // MARK: - 发现

    func startBrowsing() {
        stopAll()
        let browser = NWBrowser(
            for: .bonjour(type: MobilePairingCrypto.bonjourServiceType, domain: nil),
            using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            guard let first = results.first,
                  case .service(let name, _, _, _) = first.endpoint else { return }
            Task { @MainActor in
                // 只取第一个发现的 Mac——家庭场景通常只有一台；多 Mac 选择后续提交再加。
                self.connect(to: name)
            }
        }
        browser.stateUpdateHandler = { [weak self] newState in
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
        phase = .browsing
    }

    func stopBrowsing() {
        stopAll()
        phase = .idle
    }

    // MARK: - 连接与握手

    private func connect(to serviceName: String) {
        let endpoint = NWEndpoint.service(
            name: serviceName,
            type: MobilePairingCrypto.bonjourServiceType,
            domain: "local.",
            interface: nil)
        let connection = NWConnection(to: endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            Task { @MainActor in
                switch newState {
                case .ready:
                    if case .connecting(let mac) = self.phase {
                        self.phase = .connecting(mac)
                    }
                    // Mac 在 ready 后立刻发 MacHello——等第一帧。
                    self.receiveOneMessage { data in
                        Task { @MainActor in self.handleMacHello(data) }
                    }
                case .failed(let error):
                    self.stopConnection()
                    self.phase = .failed(error.localizedDescription)
                default:
                    break
                }
            }
        }
        connection.start(queue: queue)
        self.connection = connection
        phase = .connecting(DiscoveredMac(serviceName: serviceName))
    }

    private func handleMacHello(_ data: Data?) {
        guard let data else {
            phase = .failed("未收到 Mac 握手消息。")
            stopConnection()
            return
        }
        do {
            let macHello = try JSONDecoder().decode(MobilePairingHandshake.MacHello.self, from: data)
            guard macHello.protocolVersion == MobilePairingHandshake.currentProtocolVersion else {
                phase = .failed("Mac 端协议版本不兼容。")
                stopConnection()
                return
            }
            pendingMacHello = macHello
            pendingIdentity = MobilePairingIdentity.generate()
            guard let mac = discoveredServiceName else { return }
            phase = .verifyFingerprint(DiscoveredMac(serviceName: mac), fingerprint: macHello.fingerprint)
        } catch {
            phase = .failed("Mac 握手消息无法解析。")
            stopConnection()
        }
    }

    private var discoveredServiceName: String? {
        if case .connecting(let mac) = phase { return mac.serviceName }
        if case .verifyFingerprint(let mac, _) = phase { return mac.serviceName }
        return nil
    }

    /// 用户确认"Mac 屏显指纹与手机一致"后调用。
    func confirmFingerprintAndPair() {
        guard case .verifyFingerprint = phase,
              pendingMacHello != nil,
              let identity = pendingIdentity else { return }
        let code = pairingCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.utf8.count == MobilePairingCrypto.pairingCodeDigitCount,
              code.allSatisfy(\.isNumber) else {
            phase = .failed("配对码必须是 6 位数字。")
            return
        }
        let name = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            phase = .failed("设备名不能为空。")
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
            phase = .awaitingAck
            guard let connection else {
                phase = .failed("连接已断开。")
                return
            }
            connection.send(content: frame, completion: .contentProcessed { [weak self] error in
                Task { @MainActor in
                    guard let self else { return }
                    if error != nil {
                        self.phase = .failed("发送配对请求失败。")
                        self.stopConnection()
                        return
                    }
                    self.receiveOneMessage { data in
                        Task { @MainActor in self.handleAck(data) }
                    }
                }
            })
        } catch {
            phase = .failed(error.localizedDescription)
            stopConnection()
        }
    }

    private func handleAck(_ data: Data?) {
        guard let data,
              let macHello = pendingMacHello,
              let identity = pendingIdentity,
              let code = pendingPairingCode,
              let phoneNonce = pendingPhoneNonce else {
            phase = .failed("未收到配对结果。")
            stopConnection()
            return
        }
        do {
            // 与 Mac 同一公式推导会话密钥；ack 是密文——解不开即说明对端不是持有
            // 该私钥的 Mac 或配对码不一致。
            let key = try identity.sessionKey(
                peerPublicKeyData: macHello.macPublicKey,
                pairingCode: code,
                macNonce: macHello.macNonce,
                phoneNonce: phoneNonce)
            let ack = try MobilePairingEnvelope.openAck(data, using: key)
            guard ack.accepted else {
                phase = .failed("Mac 拒绝了本次配对。")
                stopConnection()
                return
            }
            stopConnection()
            phase = .paired
        } catch {
            phase = .failed("配对结果校验失败：Mac 身份或配对码不一致。")
            stopConnection()
        }
    }

    // MARK: - 帧收发（与 Mac 端同一帧格式）

    private func receiveOneMessage(handler: @escaping @Sendable (Data?) -> Void) {
        guard let connection else {
            handler(nil)
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { content, _, isComplete, error in
            var accumulated = Data()
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
                // 继续收：递归携带累计缓冲。
                self.receiveContinuation(connection: connection, buffer: accumulated, handler: handler)
            case .invalid:
                handler(nil)
            }
        }
    }

    nonisolated private func receiveContinuation(
        connection: NWConnection,
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
                self.receiveContinuation(connection: connection, buffer: accumulated, handler: handler)
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
        browser?.cancel()
        browser = nil
        stopConnection()
        pendingMacHello = nil
        pendingIdentity = nil
        pendingPairingCode = nil
        pendingPhoneNonce = nil
    }
}
