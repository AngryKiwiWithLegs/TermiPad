// iPhone 伴侣 app 入口（docs/m0-m1-mobile-entry-design.md §3.2-§3.3 + §3.3.1）。
// 两条握手路径：
//   配对（pairing）— 首次连接，输 Mac 屏上 6 位配对码 + 人工比对指纹
//   复用（resume）— 已配对手机重连，持久化身份 + 双向公钥指纹绑定，免码
import SwiftUI
import Network
import CryptoKit

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
        case noCredentials                // 首次使用——需要配对
        case paired(credentials: CompanionPairingCredentials)  // 已有凭据，可走 resume
        case browsing                     // NWBrowser 搜索中
        case connecting(DiscoveredMac)
        case verifyFingerprint(DiscoveredMac, fingerprint: String, isResume: Bool)
        case awaitingAck(isResume: Bool)
        case listingTools(DiscoveredMac)
        case toolSummaries([MobileToolSummary])
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
    private var pendingSessionKey: SymmetricKey?
    private var capturedServiceName: String?
    private let queue = DispatchQueue(label: "com.termipad.companion.network", qos: .userInitiated)

    init() {
        if let credentials = CompanionPairingStore.loadCredentials() {
            phase = .paired(credentials: credentials)
        } else {
            phase = .noCredentials
        }
    }

    // MARK: - 公开动作

    func startBrowsing() {
        stopAll()
        let browser = NWBrowser(
            for: .bonjour(type: MobilePairingCrypto.bonjourServiceType, domain: nil),
            using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            guard let first = results.first,
                  case .service(let name, _, _, _) = first.endpoint else { return }
            Task { @MainActor in self.connect(to: name) }
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
        refreshFromKeychain()
    }

    /// 已配对用户点“刷新工具目录”——走复用握手。
    func resumeAndFetchTools() {
        guard case .paired(let credentials) = phase else {
            startBrowsing()
            return
        }
        guard let identity = CompanionPairingStore.loadIdentity() else {
            // 凭据损坏：清除，回到首次配对。
            CompanionPairingStore.clear()
            phase = .noCredentials
            return
        }
        startBrowsing()
    }

    /// 首次配对用户点“开始搜索”——走配对握手。
    func confirmFingerprintAndPair() {
        guard case .verifyFingerprint(_, _, isResume: false) = phase,
              let macHello = pendingMacHello,
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
            phase = .awaitingAck(isResume: false)
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
                        Task { @MainActor in self.handlePairingAck(data) }
                    }
                }
            })
        } catch {
            phase = .failed(error.localizedDescription)
            stopConnection()
        }
    }

    /// 解除配对——清空 Keychain，回到首次配对。
    func unpair() {
        CompanionPairingStore.clear()
        stopAll()
        phase = .noCredentials
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
                    self.phase = .connecting(DiscoveredMac(serviceName: serviceName))
                    self.capturedServiceName = serviceName
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
            if case .paired(let credentials) = phase {
                // 已配对：走 resume 路径，验证 Mac 公钥指纹 == 初次配对锚点。
                let currentFingerprint = macHello.fingerprint
                if currentFingerprint == credentials.macFingerprint {
                    // 信任锚点一致——自动发 resume hello（无需用户确认指纹，因为上次人工核对过）。
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
                                self.phase = .failed("发送复用请求失败。")
                                self.stopConnection()
                                return
                            }
                            // resume 路径下 Mac 发明文 MacResumeHello——重置收一帧。
                            self.receiveOneMessage { data in
                                Task { @MainActor in self.handleMacResumeHello(data) }
                            }
                        }
                    })
                } else {
                    // 同一网内另一台 TermiPad 假装成我们配对过的 Mac——按安全策略回到配对流程，
                    // 让用户人工比对指纹确认是新 Mac。
                    pendingIdentity = MobilePairingIdentity.generate()
                    phase = .verifyFingerprint(
                        DiscoveredMac(serviceName: capturedServiceName ?? "TermiPad"),
                        fingerprint: currentFingerprint,
                        isResume: false)
                }
            } else {
                // 首次配对路径：用户必须人工确认指纹。
                pendingIdentity = MobilePairingIdentity.generate()
                phase = .verifyFingerprint(
                    DiscoveredMac(serviceName: capturedServiceName ?? "TermiPad"),
                    fingerprint: macHello.fingerprint,
                    isResume: false)
            }
        } catch {
            phase = .failed("Mac 握手消息无法解析。")
            stopConnection()
        }
    }

    private func handlePairingAck(_ data: Data?) {
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
            // 持久化凭据——deviceID 来自 Mac 下发。
            let credentials = CompanionPairingCredentials(
                deviceID: ack.deviceID,
                macPublicKey: macHello.macPublicKey,
                macFingerprint: macHello.fingerprint,
                deviceName: deviceName)
            try CompanionPairingStore.save(identity: identity, credentials: credentials)
            stopConnection()
            phase = .paired(credentials: credentials)
        } catch {
            phase = .failed("配对结果校验失败：Mac 身份或配对码不一致。")
            stopConnection()
        }
    }

    private func handleMacResumeHello(_ data: Data?) {
        guard let data,
              let credentials = currentCredentials,
              let identity = pendingIdentity,
              let phoneNonce = pendingPhoneNonce else {
            phase = .failed("复用握手异常。")
            stopConnection()
            return
        }
        do {
            let macResume = try JSONDecoder().decode(MobilePairingHandshake.MacResumeHello.self, from: data)
            // 二次校验：Mac 端发回的公钥必须 = 我们存的那个（防 MITM 在 resume 阶段换人）。
            guard macResume.macPublicKey == credentials.macPublicKey else {
                phase = .failed("Mac 公钥与初次配对不一致。")
                CompanionPairingStore.clear()
                stopConnection()
                return
            }
            let key = try identity.resumeSessionKey(
                peerPublicKeyData: credentials.macPublicKey,
                macNonce: macResume.macNonce,
                phoneNonce: phoneNonce)
            pendingSessionKey = key
            // 立刻发 listTools 请求——一连接一请求一响应。
            if let connection, let mac = currentDiscoveredMac {
                let request = MobilePairingRequest(operation: .listTools, requestID: UUID(), toolID: nil)
                let frame = MobilePairingFrame.encode(try MobilePairingEnvelope.seal(request, using: key))
                phase = .listingTools(mac)
                connection.send(content: frame, completion: .contentProcessed { [weak self] error in
                    Task { @MainActor in
                        guard let self else { return }
                        if error != nil {
                            self.phase = .failed("发送工具目录请求失败。")
                            self.stopConnection()
                            return
                        }
                        self.receiveOneMessage { data in
                            Task { @MainActor in self.handleToolSummaries(data) }
                        }
                    }
                })
            }
        } catch {
            phase = .failed("复用握手失败。")
            stopConnection()
        }
    }

    private func handleToolSummaries(_ data: Data?) {
        guard let data, let key = pendingSessionKey else {
            phase = .failed("未收到工具目录。")
            stopConnection()
            return
        }
        do {
            let summaries = try MobilePairingEnvelope.openToolSummaries(data, using: key)
            // 最小数据校验：任何 4 字段之外的字段都拒收（防 Mac 端 schema 漂移）。
            guard summaries.allSatisfy({ summary in
                summary.iconSymbolName == nil || !(summary.iconSymbolName?.isEmpty ?? true)
            }) else {
                phase = .failed("工具目录字段越界。")
                stopConnection()
                return
            }
            stopConnection()
            phase = .toolSummaries(summaries)
        } catch {
            phase = .failed("工具目录解密失败。")
            stopConnection()
        }
    }

    // MARK: - 帧收发

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
        browser?.cancel()
        browser = nil
        stopConnection()
        pendingMacHello = nil
        pendingIdentity = nil
        pendingPairingCode = nil
        pendingPhoneNonce = nil
        pendingSessionKey = nil
    }

    private func refreshFromKeychain() {
        if let credentials = CompanionPairingStore.loadCredentials() {
            phase = .paired(credentials: credentials)
        } else {
            phase = .noCredentials
        }
    }

    // MARK: - 派生 helper

    private var currentCredentials: CompanionPairingCredentials? {
        if case .paired(let credentials) = phase { return credentials }
        return CompanionPairingStore.loadCredentials()
    }

    private var currentDiscoveredMac: DiscoveredMac? {
        if case .connecting(let mac) = phase { return mac }
        return nil
    }

    private var discoveredServiceName: String? {
        if case .connecting(let mac) = phase { return mac.serviceName }
        if case .verifyFingerprint(let mac, _, _) = phase { return mac.serviceName }
        if case .listingTools(let mac) = phase { return mac.serviceName }
        return nil
    }
}
