// M1 同网监听服务（docs/m0-m1-mobile-entry-design.md §3.2-§3.3）。
// 全仓库唯一允许使用 NWListener/NWConnection 的文件（verify-macos.sh 全局白名单）。
// 红线实现：默认关闭（state 初始 .off）；只有用户在设置页开启后才创建监听器；
// Bonjour 服务类型固定、不可配置；配对码必须与 Mac 屏显一致才接受——否则
// 任何同网主机都能在配对窗口内静默成为"已配对设备"。
// 连接级 I/O 全部在 listenerQueue 上完成；只有 Sendable 的配对结果跳回主线程。
import CryptoKit
import Foundation
import Network

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
                do {
                    let hello = try JSONDecoder().decode(MobilePairingHandshake.PhoneHello.self, from: data)
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
        } catch {
            complete(.failure(error))
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
