// M1 同网监听服务（docs/m0-m1-mobile-entry-design.md §3.2-§3.3）。
// 全仓库唯一允许使用 NWListener/NWConnection 的文件（verify-macos.sh 全局白名单）。
// 红线实现：默认关闭（state 初始 .off）；只有用户在设置页开启后才创建监听器；
// Bonjour 服务类型固定、不可配置；配对码必须与 Mac 屏显一致才接受——否则
// 任何同网主机都能在配对窗口内静默成为"已配对设备"。
// 连接级 I/O 全部在 listenerQueue 上完成；只有 Sendable 的配对结果跳回主线程。
import CryptoKit
import Foundation
import Network
import SwiftData

@MainActor
final class MobilePairingService: ObservableObject {
    /// M1 监听固定端口。固定端口让 TXT 在 listener 启动前就能带上完整地址，
    /// 手机可绕开 Bonjour 服务解析（iOS 26 对 .service 端点解析会卡 preparing）直连。
    nonisolated static let listenerPort: UInt16 = MobilePairingCrypto.listenerPort

    /// 枚举 en* 接口上的第一个私有 IPv4（192.168/10./172.16-31）。
    /// 不用 Process、不依赖 shell——getifaddrs 是 libc 级系统调用。
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

    init(store: MobileSecureKeyValueStore = KeychainMobileSecureStore()) {
        self.store = store
        refreshPairedDevices()
    }

    /// 注入 SwiftData 上下文（MainActor 域）——listTools 响应的只读数据源。
    /// 静态处理函数拿不到实例状态，经类级静态成员共享。
    func configure(modelContext: ModelContext) {
        Self.sharedModelContext = modelContext
    }

    @MainActor private static var sharedModelContext: ModelContext?

    func refreshPairedDevices() {
        pairedDevices = PairedDeviceStore.list(store: store)
    }

    /// 用户开启配对：加载/生成本机身份，屏显配对码与指纹，启动 Bonjour 广播。
    func startPairing() {
        guard listener == nil else { return }
        do {
            let identity = try PairedDeviceStore.MobilePairingIdentityStore.loadOrCreate(store: store)
            let fingerprint = MobilePairingCrypto.fingerprint(forPublicKeyData: try identity.publicKeyData())
            let pairingCode = MobilePairingCrypto.generatePairingCode()
            // 锁 Wi-Fi + 固定端口 + TXT 携带 LAN 地址：手机浏览时直接拿到 IP:port
            // 用 hostPort 直连，绕开 iOS 26 对 .service 端点解析卡 preparing 的问题。
            let parameters = NWParameters.tcp
            parameters.requiredInterfaceType = .wifi
            // 停止→快速重启配对时旧 socket 尚在 TIME_WAIT/异步关闭中，固定端口
            // 会报"地址已被占用"（UI 显示一串红色错误）。允许本地端点复用，
            // 这是 M1 固定端口设计的必然配套。
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: MobilePairingService.listenerPort)!)
            var txtDictionary = MobilePairingCrypto.bonjourTXTRecord(fingerprint: fingerprint)
            if let lanAddress = MobilePairingService.lanIPv4Address() {
                txtDictionary["a"] = lanAddress
                txtDictionary["p"] = String(MobilePairingService.listenerPort)
                Self.diagMac("TXT 带 LAN 地址 \(lanAddress):\(MobilePairingService.listenerPort)")
            } else {
                Self.diagMac("未找到 LAN IPv4——TXT 无地址，手机走服务端点回退路径")
            }
            // 实例名携带 LAN 地址（TermiPad-192-168-2-81）：iOS 26 的手机端浏览
            // browse 结果不带 TXT（metadata 恒为 .none），.service 解析又卡
            // preparing。地址编码进实例名是手机端唯一能自取的通道；端口固定
            // listenerPort。实例名只影响"怎么连上"，身份仍由 MacHello 指纹决定。
            let serviceName: String
            if let lanAddress = MobilePairingService.lanIPv4Address() {
                serviceName = "\(MobilePairingCrypto.bonjourServiceName)-\(lanAddress.replacingOccurrences(of: ".", with: "-"))"
                Self.diagMac("实例名带 LAN 地址: \(serviceName)")
            } else {
                serviceName = MobilePairingCrypto.bonjourServiceName
                Self.diagMac("未找到 LAN IPv4——退回无地址实例名")
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
                        self.stopPairingInternal()
                        self.state = .failed(error.localizedDescription)
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
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stopPairing() {
        stopPairingInternal()
        state = .off
    }

    /// 红线"每个权限可撤销"：撤销立即写入 Keychain 并刷新列表。
    /// 撤销不影响已建立的旧连接——本提交配对完成后即断开，无长连接可残留。
    func revoke(id: UUID) {
        try? PairedDeviceStore.revoke(id: id, store: store)
        refreshPairedDevices()
    }

    private func stopPairingInternal() {
        listener?.cancel()
        listener = nil
        // 关闭监听即清会话白名单——免确认缓存的生命周期绝不超出监听开启期。
        MobileLaunchSession.shared.invalidateAll()
    }

    private func finishPairing(_ result: Result<PairedDeviceRecord, Error>) {
        // 失败（扫描器、版本不符、配对码错误）静默丢弃连接；诊断事件后续接入。
        if case .success = result {
            refreshPairedDevices()
        }
    }

    // MARK: - 诊断

    /// Mac 端诊断：NSLog + ~/Library/Logs/termipad-pairing.log（统一日志在
    /// 本机 ad hoc 签名下不稳定，文件日志保证可查）。
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

    // MARK: - 连接级握手（listenerQueue 上下文，不触碰 MainActor 状态）

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

    /// 配对路径：与屏显配对码比对 → 接受 → 落库 → 发加密 ack → 断开。
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
            // Mac 侧必须核对配对码与屏显一致——这是防"同网主机静默配对"的关键。
            guard hello.pairingCode == expectedPairingCode else {
                complete(.failure(MobilePairingError.invalidPairingCode))
                return
            }
            let accepted = try MobilePairingHandshake.acceptPhoneHello(
                hello, identity: identity, macNonce: macNonce)
            // 同一指纹的活跃设备复用记录，避免重复配对产生重复条目。
            let record: PairedDeviceRecord
            if let existing = PairedDeviceStore.findActive(
                byPublicKeyHash: accepted.phonePublicKeyHash, store: store) {
                try PairedDeviceStore.markConnected(id: existing.id, store: store)
                record = existing
            } else {
                record = try PairedDeviceStore.add(
                    displayName: accepted.deviceName,
                    publicKeyData: hello.phonePublicKey,
                    store: store)
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

    /// 复用路径（§3.3.1）：验记录活跃 + 公钥指纹绑定 → 发明文 MacResumeHello →
    /// 等加密请求 → 一请求一响应 → 断开。失败静默断连（对端无法区分拒绝原因，
    /// 避免给扫描器提供探测信息）。
    nonisolated private static func handleResumeHello(
        _ hello: MobilePairingHandshake.PhoneResumeHello,
        connection: NWConnection,
        identity: MobilePairingIdentity,
        macNonce: Data,
        store: MobileSecureKeyValueStore
    ) {
        do {
            guard let record = PairedDeviceStore.find(id: hello.deviceID, store: store) else {
                diagMac("resume 拒绝：找不到设备记录 \(hello.deviceID)")
                throw MobilePairingError.handshakeFailed
            }
            guard record.revokedAt == nil else {
                diagMac("resume 拒绝：设备已撤销 \(record.displayName)")
                throw MobilePairingError.handshakeFailed
            }
            guard MobilePairingCrypto.fingerprint(forPublicKeyData: hello.phonePublicKey)
                == record.publicKeyHash else {
                diagMac("resume 拒绝：公钥指纹不匹配")
                throw MobilePairingError.handshakeFailed
            }
            let sessionKeyData = try MobilePairingHandshake.deriveResumeSessionKey(
                hello, identity: identity, macNonce: macNonce)
            diagMac("resume 接受：\(record.displayName)，发 MacResumeHello")
            let macResume = MobilePairingHandshake.MacResumeHello(
                protocolVersion: MobilePairingHandshake.currentProtocolVersion,
                macPublicKey: try identity.publicKeyData(),
                macNonce: macNonce)
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

    /// 解密请求 → 操作白名单分发。解不开（非配对对端/篡改）与白名单外操作
    /// 一律直接断连，不回错误细节。
    nonisolated private static func handleSealedRequest(
        _ data: Data,
        connection: NWConnection,
        sessionKeyData: Data
    ) {
        let key = SymmetricKey(data: sessionKeyData)
        guard let request = try? MobilePairingEnvelope.openRequest(data, using: key) else {
            diagMac("加密请求解密失败——\(data.count) 字节")
            connection.cancel()
            return
        }
        diagMac("收到请求 op=\(request.operation.rawValue) toolID=\(request.toolID?.uuidString ?? "nil")")
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
                        MobileLaunchResponse(status: .rejected, reason: "请求缺少目标工具。"),
                        on: connection, using: key)
                    return
                }
                await Self.handleLaunchRequest(
                    toolID: toolID, connection: connection, sessionKey: key)
            }
        default:
            // 其余操作按设计文档节奏逐个启用；未启用即拒绝并断开。
            connection.cancel()
        }
    }

    /// §3.3.2 启动请求执行链（顺序不可交换）：
    /// 资格预检 → 本机确认（60s 超时=拒绝）→ 经 TerminalLauncher 交接 → 回结果。
    @MainActor
    private static func handleLaunchRequest(
        toolID: UUID,
        connection: NWConnection,
        sessionKey: SymmetricKey
    ) async {
        // 1. 资格预检
        guard let tool = fetchTool(id: toolID),
              tool.showInMobileEntry,
              tool.allowMobileLaunchRequest,
              tool.revokeMobilePermissionAt == nil,
              CommandTemplate.variables(in: tool.commandTemplate).isEmpty else {
            sendLaunchResponse(
                MobileLaunchResponse(status: .rejected, reason: "该工具未允许手机启动，或需要填写参数。"),
                on: connection, using: sessionKey)
            return
        }
        // 2. 本机确认（§3.3.2 增补 2026-09-08）：perSession/lowRisk 会话白名单
        //    命中即免确认直启（记审计事件）；everyTime / 未命中 / lowRisk 元字符
        //    第二道防线拦下的一律弹 60s 确认框。
        let launchSession = MobileLaunchSession.shared
        if launchSession.canSkipConfirmation(
            policy: tool.mobileLocalConfirmPolicy,
            toolID: tool.id,
            commandTemplate: tool.commandTemplate) {
            DiagnosticsStore.shared.record(.mobileLaunchAutoConfirmed)
            diagMac("会话白名单命中，免确认直启 policy=\(tool.mobileLocalConfirmPolicy.rawValue)")
        } else {
            let accepted = await MobileLaunchPromptCenter.shared.requestConfirmation(
                toolName: tool.mobileDisplayName ?? tool.name,
                deviceName: "已配对设备")
            guard accepted else {
                sendLaunchResponse(
                    MobileLaunchResponse(status: .rejected, reason: "Mac 上拒绝了本次启动。"),
                    on: connection, using: sessionKey)
                return
            }
            // 确认通过刷新会话时间戳——perSession/lowRisk 从这次确认起算 5 分钟。
            launchSession.recordConfirmation(toolID: tool.id)
        }
        // 3. 经既有终端启动路径——不新增执行入口，命令来自 Mac 已保存模板
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
            default:
                DiagnosticsStore.shared.record(.launchFailed, terminalTarget: target)
            }
        } catch {
            DiagnosticsStore.shared.record(.launchFailed, terminalTarget: target)
        }
        // 4. 结果（启动交接完成即 accepted；是否真的弹出终端由终端侧决定，
        // 与 Mac 上手动启动同一语义）
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

    /// 只读目录：仅 showInMobileEntry == true 的工具，4 字段白名单
    /// （id / displayName / displayDescription / iconSymbolName）。
    /// 命令、路径、变量值永不进入该响应——MobileToolSummary 字段集合由测试锁死。
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

    /// 递归收字节进缓冲，解出第一帧后回调；错误/对端关闭回调 nil。
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
