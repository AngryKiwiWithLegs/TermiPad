// iPhone 伴侣 app 入口（docs/m0-m1-mobile-entry-design.md §3.2-§3.3 + §3.3.1）。
// 两条握手路径：
//   配对（pairing）— 首次连接，输 Mac 屏上 6 位配对码 + 人工比对指纹
//   复用（resume）— 已配对手机重连，持久化身份 + 双向公钥指纹绑定，免码
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
                // M2b 防线 1（设计 §4）：切回前台过 Face ID/设备密码。
                // 锁定时盖住全部界面——偷手机的人过不了生物识别。
                .fullScreenCover(isPresented: $appLock.isLocked) {
                    CompanionLockView(appLock: appLock)
                }
        }
    }
}

/// M2b 防线 1：app 前台锁。默认开启（用户可在锁屏页暂时跳过一次会话内
/// 不再锁——设备级安全由 iOS 系统锁兜底；配对凭据本身已
/// WhenUnlockedThisDeviceOnly）。
@MainActor
final class CompanionAppLock: ObservableObject {
    @Published var isLocked = true

    func requestUnlock() {
        let context = LAContext()
        var error: NSError?
        // 设备密码兜底：无 Face ID/Touch ID 的设备回落 passcode。
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // 无任何生物/密码保护的设备（理论罕见）——不锁死用户。
            isLocked = false
            return
        }
        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "解锁 TermiPad 伴侣以查看任务会话"
        ) { [weak self] success, _ in
            Task { @MainActor in
                self?.isLocked = !success
            }
        }
    }
}

/// 锁屏盖层：全屏遮罩 + 解锁按钮（点击触发 Face ID）。
struct CompanionLockView: View {
    @ObservedObject var appLock: CompanionAppLock

    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("TermiPad 伴侣已锁定")
                    .font(.headline)
                Button("使用面容 ID 解锁") {
                    appLock.requestUnlock()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("companion-applock-unlock")
                Text("为防止他人使用你的手机控制 Mac，每次打开需要验证。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .onAppear { appLock.requestUnlock() }
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
    /// M2b-1 任务会话页数据（docs/m2b-remote-task-console-design.md §6）：
    /// 非空即渲染会话页——数据驱动而非 phase 驱动，避免轮询期间
    /// browsing/connecting 状态导致视图闪动。仅内存，不落盘（防线 1）。
    @Published private(set) var consoleEntries: [MobileSessionEntry] = []

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
    /// M2b-1：非 nil 时 resume 后发 getTaskStatus（会话轮询请求）。
    private var pendingConsoleRequest = false
    // M2b-1 会话轮询状态（设计 §6：3 秒间隔、串行——上一轮响应（或超时）
    // 之后才排下一轮，请求永不重叠；仅 app 前台时活跃）。
    private var consolePollWorkItem: DispatchWorkItem?
    private var consolePollingActive = false
    /// 手动"返回"或页面隐藏后置位；进入会话页重新拉起。
    private var consoleDismissed = false
    // M2a 连接编排状态（LAN 优先 / tailnet 兜底 / 明确超时文案）。
    private var tailnetFallbackWorkItem: DispatchWorkItem?
    private var browseTimeoutWorkItem: DispatchWorkItem?
    private var lanConnectStarted = false
    private var tailnetAttemptInFlight = false
    /// 隧道路径的伪服务名——connect() 据此选无接口约束的参数（tailnet 流量走
    /// Tailscale 的 utun 接口，M1 的 .wifi 约束会把它挡死）。ContentView 亦用它
    /// 区分连接中的文案。
    static let tailnetServiceName = "TermiPad-tailnet"
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
        startBrowsingInternal()
    }

    // MARK: - M2b-1 任务会话（docs/m2b-remote-task-console-design.md §6）

    /// 进入会话页：立即拉一轮，成功后按 3 秒节奏轮询。数据到达即
    /// consoleEntries 非空——会话页据此自渲染。
    func openTaskConsole() {
        consoleDismissed = false
        guard !consolePollingActive else { return }
        startConsolePollCycle()
    }

    /// 离开会话页：停轮询（连接由"一连接一请求"模型自然关闭）。
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
            // 没有端点且不在近场——走既有浏览流程兜底。
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
        // 连接编排复用既有路径：resume 握手 → getTaskStatus 一问一答。
        // 会话轮询请求在 resume 完成后发出（pendingConsoleRequest）。
        pendingConsoleRequest = true
        connect(to: serviceName, directAddress: directAddress)
        Self.diag("会话轮询：连接 Mac（\(directAddress ?? "LAN")）")
    }

    /// 上一轮响应/失败后调用：排 3 秒后的下一轮（串行，永不重叠）。
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
            // 竞态守卫（2026-09-10）：指纹确认与等待 ack 阶段忽略新 browse
            // 结果——重连会覆盖 pendingMacHello/pendingIdentity/pendingNonce，
            // 用户随后提交的配对将混用两轮连接的密钥材料（真机实测：Mac 端
            // 「配对接受」与手机端解密失败同秒出现，即此竞态）。phase 是
            // MainActor 隔离属性——闭包在 queue 上跑，经主线程读。
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
        // M2a：LAN 优先、tailnet 兜底、超时给明确文案——不无限转圈。
        lanConnectStarted = false
        tailnetAttemptInFlight = false
        scheduleTailnetFallbackIfNeeded()
        scheduleBrowseTimeout()
    }

    /// browse 结果的主线程处理（2026-09-10 从闭包抽出——闭包在 queue 上跑，
    /// phase 检查必须回 MainActor）。iOS 26 的 browse 结果不带 TXT（metadata
    /// 恒为 .none）；.service 端点解析会卡 preparing。Mac 端把 LAN 地址编码进
    /// 实例名（TermiPad-192-168-2-81），这里直接从名字还原 IP 直连。
    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        guard let first = results.first,
              case .service(let name, _, _, _) = first.endpoint else { return }
        guard let directAddress = Self.directAddress(fromServiceName: name) else {
            Self.diag("实例名无 LAN 地址（\(name)）——等待 Mac 端重新开启配对广播")
            return
        }
        Self.diag("从实例名还原直连地址 \(directAddress)")
        connect(to: name, directAddress: directAddress)
    }

    /// M2a 连接编排（docs/m2-secure-remote-session-design.md §3）：
    /// 浏览 6 秒仍一无所获且凭据里有异地端点 → 放弃 LAN 浏览改走 tailnet 直连。
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
        // 唯一前置条件：LAN 尚未连上（lanConnectStarted 仅在 LAN TCP ready
        // 时置真）且 tailnet 不在途。不按 phase 判——.waiting 触发的立即转
        // 路径此刻 phase 已是 .connecting，按 browsing 判会永远挡掉拨号
        // （2026-09-09 实测：日志触发两次但一次都没拨出去）。
        guard !lanConnectStarted, !tailnetAttemptInFlight else { return }
        Self.diag("LAN 不可用，改走异地 tailnet \(endpoint)")
        tailnetFallbackWorkItem?.cancel()
        tailnetFallbackWorkItem = nil
        browseTimeoutWorkItem?.cancel()
        browseTimeoutWorkItem = nil
        browser?.cancel()
        browser = nil
        tailnetAttemptInFlight = true
        connect(to: Self.tailnetServiceName, directAddress: endpoint)
    }

    /// 浏览 10 秒仍停在 .browsing（且 tailnet 兜底未在途）→ 明确失败文案。
    private func scheduleBrowseTimeout() {
        browseTimeoutWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, case .browsing = self.phase, !self.tailnetAttemptInFlight else { return }
                let hasTailnet = !(self.currentCredentials?.tailnetEndpoint ?? "").isEmpty
                self.stopAll()
                self.phase = .failed(hasTailnet
                    ? "同一 Wi-Fi 内未发现 Mac，异地 tailnet 通道也未连通。确认 Mac 已开机、TermiPad 正在运行、两端 Tailscale 在线。"
                    : "同一 Wi-Fi 内未发现 Mac，且异地通道未开启。确认两端在同一 Wi-Fi、Mac 端配对已开启；在外网使用需在 Mac 端『设置 → 手机伴侣 → 异地访问』打开开关（需要 Tailscale）。")
            }
        }
        browseTimeoutWorkItem = work
        queue.asyncAfter(deadline: .now() + 10, execute: work)
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
    /// 注意顺序：startBrowsing 内部的 stopAll 会清 pendingLaunchRequest，
    /// 所以标志必须在 stopAll 之后（返回的闭包里）重新写入。
    func requestLaunch(_ summary: MobileToolSummary) {
        let launch = (toolID: summary.id, name: summary.displayName)
        stopAll()
        pendingLaunchRequest = launch
        startBrowsingInternal()
    }

    // MARK: - M2b-3 新任务提交（docs/m2b-remote-task-console-design.md §6）

    /// 目录数据（listScopes / listFixedTasks 结果）——仅内存。
    @Published private(set) var consoleScopes: [MobileScopeSummary] = []
    @Published private(set) var consoleFixedTasks: [MobileFixedTaskSummary] = []
    /// 非 nil 时 resume 后发 requestTaskProposal（kind + scopeID）。
    private var pendingTaskProposal: (kind: String, scopeID: UUID, title: String)?

    /// 打开"新任务"页：拉 scopes + fixedTasks 两轮目录。
    func openNewTaskForm() {
        pendingCatalogRequests = 2
        connectAndRequest(operation: .listScopes)
    }

    /// 目录轮次：listScopes 回来后接着拉 listFixedTasks（一连接一请求）。
    private var pendingCatalogRequests = 0

    /// 发起任务提交（新任务页的提交按钮）。
    func submitTaskProposal(kind: String, scopeID: UUID, title: String) {
        stopAll()
        pendingTaskProposal = (kind, scopeID, title)
        startBrowsingInternal()
    }

    /// 任务提交回执 → 会话页直接看状态（轮询里能看到该任务）。
    @Published private(set) var lastTaskProposalResult: MobileTaskProposalResponse?

    /// 通用"连接→resume→发指定操作"入口（新任务表单的目录拉取用）。
    private func connectAndRequest(operation: PairedDeviceOperation) {
        guard let credentials = currentCredentials else {
            phase = .noCredentials
            return
        }
        nextCatalogOperation = operation
        connect(to: Self.tailnetServiceName, directAddress: credentials.tailnetEndpoint)
    }

    private var nextCatalogOperation: PairedDeviceOperation?

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
        let connection: NWConnection
        if serviceName == Self.tailnetServiceName {
            // 异地 tailnet 路径：无接口约束——流量由 Tailscale 的 utun 接口承载，
            // .wifi 约束（M1 防仿冒用）会挡掉它。
            connection = NWConnection(to: endpoint, using: Self.tunnelParameters())
        } else {
            lanConnectStarted = true
            connection = NWConnection(to: endpoint, using: Self.wifiParameters())
        }
        Self.diag("connecting to \(serviceName)")
        // 10 秒仍停在 preparing 即视为失败——路由不可达/接口不匹配，不让用户无限转圈。
        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, case .connecting = self.phase else { return }
                Self.diag("connection timeout in preparing")
                self.stopConnection()
                self.phase = .failed(serviceName == Self.tailnetServiceName
                    ? "异地连接超时：确认 Mac 已开机、TermiPad 正在运行、两端 Tailscale 在线。"
                    : "连接超时：Mac 不可达。确认两端在同一 Wi-Fi，且 Mac 端配对已开启。")
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
                case .waiting(let error):
                    // POSIX 50（Network is down）= 当前接口无网（如关 Wi-Fi 后
                    // 蜂窝未接管/VPN 未活跃）。LAN 已死——立即转 tailnet 兜底，
                    // 不再等 6 秒定时器（此前 browse 缓存会伪装出结果，
                    // lanConnectStarted 挡掉兜底守卫）。
                    if !self.tailnetAttemptInFlight, Self.isNetworkDown(error),
                       let endpoint = self.currentCredentials?.tailnetEndpoint, !endpoint.isEmpty {
                        Self.diag("LAN 接口无网（\(error.localizedDescription)），立即转异地 tailnet")
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
        Self.diag("收到配对 ack：\(data?.count ?? 0) 字节")
        // 竞态守卫：输码期间浏览回调可能重开连接覆盖 pending 状态——旧连接
        // 的 ack 到达时 pendingMacHello 已不是它的 MacHello（nonce 不匹配
        // → 派生密钥不同 → 解密必然失败，2026-09-10 真机实例）。待确认的
        // ack 只属于发起它的那次连接：awaitingAck 阶段收到新 browse 结果
        // 直接忽略（下面 browse handler 同步拦截）。
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
            // 2026-09-10 真机排查：Mac 端「配对接受」与手机端解密失败同秒发生
            // ——两端派生了不同会话密钥。打出派生输入摘要与两端比对（nonce/
            // 公钥均为公开材料，安全）。诊断期间临时打 pairingCode 是核对传输
            // 一致性的最小手段（同网人工比对场景下码本就屏显）。
            func hexPrefix(_ data: Data, _ count: Int) -> String {
                data.prefix(count).map { String(format: "%02x", $0) }.joined()
            }
            let phonePubHex = ((try? identity.publicKeyData()) ?? Data()).prefix(6)
                .map { String(format: "%02x", $0) }.joined()
            Self.diag("ack 校验失败：\(error.localizedDescription)")
            Self.diag("派生输入摘要：macPub=\(hexPrefix(macHello.macPublicKey, 6)) macNonce=\(hexPrefix(macHello.macNonce, 4)) phoneNonce=\(hexPrefix(phoneNonce, 4)) code=\(code) phonePub=\(phonePubHex)")
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
            // M2a：持久化 Mac 下发的异地端点（同网引导异地，出门零操作）。
            // nil 也写回——Mac 端关闭异地访问时清掉手机侧的旧端点。
            if macResume.tailnetEndpoint != credentials.tailnetEndpoint {
                var updated = credentials
                updated.tailnetEndpoint = macResume.tailnetEndpoint
                try? CompanionPairingStore.save(identity: identity, credentials: updated)
                Self.diag("异地端点已更新：\(macResume.tailnetEndpoint ?? "off")")
            }
            // 立刻发请求——一连接一请求一响应。优先级：requestLaunch >
            // getTaskStatus（会话轮询）> listTools。
            // 先构造请求、取连接，最后才切 phase：currentDiscoveredMac 只在
            // .connecting/.awaitingAck 有值，提前切 .requestingLaunch 会让
            // 发送块被整体跳过（帧发不出去）。
            let request: MobilePairingRequest
            if let launch = pendingLaunchRequest {
                Self.diag("MacResumeHello 校验通过，发 requestLaunch tool=\(launch.name)")
                request = MobilePairingRequest(operation: .requestLaunch, requestID: UUID(), toolID: launch.toolID)
            } else if let proposal = pendingTaskProposal {
                Self.diag("MacResumeHello 校验通过，发 requestTaskProposal kind=\(proposal.kind)")
                request = MobilePairingRequest(
                    operation: .requestTaskProposal, requestID: UUID(), toolID: nil,
                    taskKind: proposal.kind, projectScopeID: proposal.scopeID)
            } else if let catalog = nextCatalogOperation {
                Self.diag("MacResumeHello 校验通过，发 \(catalog.rawValue)（目录拉取）")
                request = MobilePairingRequest(operation: catalog, requestID: UUID(), toolID: nil)
            } else if pendingConsoleRequest {
                Self.diag("MacResumeHello 校验通过，发 getTaskStatus（会话轮询）")
                request = MobilePairingRequest(operation: .getTaskStatus, requestID: UUID(), toolID: nil)
            } else {
                Self.diag("MacResumeHello 校验通过，发 listTools")
                request = MobilePairingRequest(operation: .listTools, requestID: UUID(), toolID: nil)
            }
            guard let connection, let mac = currentDiscoveredMac else {
                Self.diag("发送时连接已不在——请求被丢弃")
                phase = .failed("连接已断开，请重试。")
                stopConnection()
                return
            }
            let frame = MobilePairingFrame.encode(try MobilePairingEnvelope.seal(request, using: key))
            if let launch = pendingLaunchRequest {
                phase = .requestingLaunch(launch.name)
            } else if pendingConsoleRequest {
                // 会话轮询期间 phase 保持在连接/列表态——会话页由
                // consoleEntries 数据驱动，轮询不产生 phase 闪动。
                phase = .listingTools(mac)
            } else {
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
                    Self.diag("请求帧已发出（\(request.operation.rawValue)），等待 Mac 响应")
                    self.receiveOneMessage { data in
                        Task { @MainActor in self.handleResponse(data) }
                    }
                }
            })
        } catch {
            phase = .failed("复用握手失败。")
            stopConnection()
        }
    }

    private func handleResponse(_ data: Data?) {
        guard let data, let key = pendingSessionKey else {
            phase = .failed("未收到响应。")
            stopConnection()
            if consolePollingActive { scheduleNextConsolePoll() }
            return
        }
        // 新任务表单目录拉取（listScopes → listFixedTasks 两轮）与任务提交回执。
        if let catalog = nextCatalogOperation {
            nextCatalogOperation = nil
            do {
                switch catalog {
                case .listScopes:
                    let scopes = try MobilePairingEnvelope.openScopeSummaries(data, using: key)
                    Self.diag("范围目录 count=\(scopes.count)")
                    consoleScopes = scopes
                case .listFixedTasks:
                    let tasks = try MobilePairingEnvelope.openFixedTaskSummaries(data, using: key)
                    Self.diag("固定任务目录 count=\(tasks.count)")
                    consoleFixedTasks = tasks
                default:
                    break
                }
                stopConnection()
                // 下一轮目录：scopes 到了就拉 fixedTasks。
                if pendingCatalogRequests > 1 {
                    pendingCatalogRequests -= 1
                    connectAndRequest(operation: .listFixedTasks)
                }
            } catch {
                Self.diag("目录拉取解密失败")
                stopConnection()
            }
            return
        }
        if let proposal = pendingTaskProposal {
            pendingTaskProposal = nil
            _ = proposal
            do {
                let response = try MobilePairingEnvelope.openTaskProposalResponse(data, using: key)
                Self.diag("任务提交回执 status=\(response.status.rawValue) reason=\(response.reason ?? "-")")
                lastTaskProposalResult = response
                stopConnection()
                // 提交后立即进会话页看状态。
                openTaskConsole()
            } catch {
                Self.diag("任务提交回执解析失败")
                stopConnection()
                openTaskConsole()
            }
            return
        }
        // 会话轮询响应先试：Mac 只回 [MobileSessionEntry]（一问一答模型下
        // 与其他响应类型按 pending 标志互斥，不会误判）。
        if pendingConsoleRequest {
            pendingConsoleRequest = false
            do {
                let entries = try MobilePairingEnvelope.openSessionEntries(data, using: key)
                Self.diag("会话快照 count=\(entries.count)")
                consoleEntries = entries
                stopConnection()
                scheduleNextConsolePoll()
            } catch {
                Self.diag("会话快照解密失败")
                stopConnection()
                scheduleNextConsolePoll()
            }
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

    /// 异地 tailnet 连接参数：无接口约束（流量走 Tailscale utun）。
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
        nextCatalogOperation = nil
        pendingCatalogRequests = 0
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

    /// UI 用：钥匙串里是否存有异地端点（browsing 文案与失败文案据此分流）。
    var hasTailnetEndpoint: Bool {
        !(currentCredentials?.tailnetEndpoint ?? "").isEmpty
    }

    /// POSIX 50（ENETDOWN）：接口无网。iOS 上常见于关 Wi-Fi 后蜂窝/VPN
    /// 未接管流量的窗口期——是"LAN 已死"的可靠信号。
    private static func isNetworkDown(_ error: NWError) -> Bool {
        if case .posix(let code) = error, code == .ENETDOWN { return true }
        return false
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
