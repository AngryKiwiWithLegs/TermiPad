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
        case requestingLaunch(String)
        case launchResult(accepted: Bool, message: String?)
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
    /// 非 nil 时 resume 后发 requestLaunch（而非 listTools）。
    private var pendingLaunchRequest: (toolID: UUID, name: String)?
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
            Self.diag("browse results=\(results.count) metadata=\(results.first?.metadata)")
            guard let self else { return }
            guard let first = results.first,
                  case .service(let name, _, _, _) = first.endpoint else { return }
            // iOS 26 的 browse 结果不带 TXT（metadata 恒为 .none）；.service 端点
            // 解析会卡 preparing。Mac 端把 LAN 地址编码进实例名
            // （TermiPad-192-168-2-81），这里直接从名字还原 IP 直连。
            guard let directAddress = Self.directAddress(fromServiceName: name) else {
                Self.diag("实例名无 LAN 地址（\(name)）——等待 Mac 端重新开启配对广播")
                return
            }
            Self.diag("从实例名还原直连地址 \(directAddress)")
            let finalAddress = directAddress
            Task { @MainActor in self.connect(to: name, directAddress: finalAddress) }
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

    /// 手机点工具卡发起启动请求（§3.3.2）——走 resume 通道。
    func requestLaunch(_ summary: MobileToolSummary) {
        pendingLaunchRequest = (toolID: summary.id, name: summary.displayName)
        startBrowsing()
    }

    /// 解除配对——清空 Keychain，回到首次配对。
    func unpair() {
        CompanionPairingStore.clear()
        stopAll()
        phase = .noCredentials
    }

    // MARK: - 连接与握手

    private func connect(to serviceName: String, directAddress: String?) {
        let endpoint: NWEndpoint
        if let directAddress,
           let separatorIndex = directAddress.lastIndex(of: ":"),
           let port = UInt16(directAddress[directAddress.index(after: separatorIndex)...]) {
            // TXT 直连路径：IP:port 已由 Mac 通告，跳过 .service 解析
            // （iOS 26 下该解析会无限卡 preparing）。
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
        let connection = NWConnection(to: endpoint, using: Self.wifiParameters())
        Self.diag("connecting to \(serviceName)")
        // 10 秒仍停在 preparing 即视为失败——路由不可达/接口不匹配，不让用户无限转圈。
        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, case .connecting = self.phase else { return }
                Self.diag("connection timeout in preparing")
                self.stopConnection()
                self.phase = .failed("连接超时：Mac 不可达。确认两端在同一 Wi-Fi，且 Mac 端配对已开启。")
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
            // 凭据判断必须查 Keychain 而非 phase——connect() 在 ready 时已把
            // phase 改成 .connecting，查 phase 会让 resume 路径永远不触发，
            // 每次都跳回首次配对界面（真机实测踩过的坑）。
            if let credentials = CompanionPairingStore.loadCredentials() {
                // 已配对：走 resume 路径，验证 Mac 公钥指纹 == 初次配对锚点。
                let currentFingerprint = macHello.fingerprint
                Self.diag("有凭据；Mac指纹\(currentFingerprint == credentials.macFingerprint ? "匹配" : "不匹配")")
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
                Self.diag("无凭据——首次配对路径")
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
            Self.diag("配对完成，凭据已存（deviceID=\(ack.deviceID)）")
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
            // Mac 对被撤销/未知设备的 resume 静默断连（不回错误细节防探测）。
            // 凭据已失效——清除并回到配对界面，而不是留一句含糊的报错。
            Self.diag("resume 未收到 MacResumeHello——凭据很可能已被 Mac 撤销")
            CompanionPairingStore.clear()
            stopAll()
            phase = .failed("Mac 已撤销本设备的配对。请重新走一次配对流程。")
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
            // 立刻发请求——一连接一请求一响应。有 pendingLaunchRequest 发
            // requestLaunch，否则发 listTools。
            let request: MobilePairingRequest
            if let launch = pendingLaunchRequest {
                Self.diag("MacResumeHello 校验通过，发 requestLaunch tool=\(launch.name)")
                request = MobilePairingRequest(operation: .requestLaunch, requestID: UUID(), toolID: launch.toolID)
                phase = .requestingLaunch(launch.name)
            } else {
                Self.diag("MacResumeHello 校验通过，发 listTools")
                request = MobilePairingRequest(operation: .listTools, requestID: UUID(), toolID: nil)
            }
            if let connection, let mac = currentDiscoveredMac {
                let frame = MobilePairingFrame.encode(try MobilePairingEnvelope.seal(request, using: key))
                if pendingLaunchRequest == nil {
                    phase = .listingTools(mac)
                }
                connection.send(content: frame, completion: .contentProcessed { [weak self] error in
                    Task { @MainActor in
                        guard let self else { return }
                        if error != nil {
                            self.phase = .failed("发送请求失败。")
                            self.stopConnection()
                            return
                        }
                        self.receiveOneMessage { data in
                            Task { @MainActor in self.handleResponse(data) }
                        }
                    }
                })
            }
        } catch {
            phase = .failed("复用握手失败。")
            stopConnection()
        }
    }

    private func handleResponse(_ data: Data?) {
        guard let data, let key = pendingSessionKey else {
            phase = .failed("未收到响应。")
            stopConnection()
            return
        }
        // requestLaunch 的响应先试：Mac 只回 MobileLaunchResponse。
        if let launch = pendingLaunchRequest {
            do {
                let response = try MobilePairingEnvelope.openLaunchResponse(data, using: key)
                Self.diag("启动结果 status=\(response.status.rawValue)")
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
                phase = .failed("启动请求结果解析失败。")
            }
            _ = launch
            return
        }
        do {
            let summaries = try MobilePairingEnvelope.openToolSummaries(data, using: key)
            Self.diag("收到工具目录 count=\(summaries.count)")
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

    // MARK: - 诊断

    /// 从 Bonjour 实例名还原直连地址：Mac 端通告 "TermiPad-192-168-2-81"，
    /// 端口固定 listenerPort。名字里没地址（老版 Mac）返回 nil。
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

    /// 同时写 NSLog 与 Documents/companion-diag.log——后者可经 devicectl
    /// appDataContainer 拉取，不依赖控制台挂载。
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

    // MARK: - 帧收发

    /// 锁 Wi-Fi 接口（与 Mac 端监听器对称）：避免解析到 VPN/隧道接口的不可达地址。
    nonisolated private static func wifiParameters() -> NWParameters {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .wifi
        return parameters
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
        browser?.cancel()
        browser = nil
        stopConnection()
        pendingMacHello = nil
        pendingIdentity = nil
        pendingPairingCode = nil
        pendingPhoneNonce = nil
        pendingSessionKey = nil
        pendingLaunchRequest = nil
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
        // resume 流程在 .awaitingAck 阶段就要发 listTools——此前用 capturedServiceName。
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
