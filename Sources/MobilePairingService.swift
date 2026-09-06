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
            let listener = try NWListener(using: .tcp)
            listener.service = NWListener.Service(
                name: MobilePairingCrypto.bonjourServiceName,
                type: MobilePairingCrypto.bonjourServiceType)
            listener.stateUpdateHandler = { [weak self] newState in
                guard let self else { return }
                Task { @MainActor in
                    if case .failed(let error) = newState {
                        self.stopPairingInternal()
                        self.state = .failed(error.localizedDescription)
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
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
    }

    private func finishPairing(_ result: Result<PairedDeviceRecord, Error>) {
        // 失败（扫描器、版本不符、配对码错误）静默丢弃连接；诊断事件后续接入。
        if case .success = result {
            refreshPairedDevices()
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
                throw MobilePairingError.handshakeFailed
            }
            guard record.revokedAt == nil else { throw MobilePairingError.handshakeFailed }
            guard MobilePairingCrypto.fingerprint(forPublicKeyData: hello.phonePublicKey)
                == record.publicKeyHash else { throw MobilePairingError.handshakeFailed }
            let sessionKeyData = try MobilePairingHandshake.deriveResumeSessionKey(
                hello, identity: identity, macNonce: macNonce)
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
            connection.cancel()
            return
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
        default:
            // requestLaunch 等操作按设计文档节奏逐个启用；未启用即拒绝并断开。
            connection.cancel()
        }
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
