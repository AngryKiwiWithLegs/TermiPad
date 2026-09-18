// M1 同网配对协议层（docs/m0-m1-mobile-entry-design.md §3.3-§3.4）。
// 本文件只做协议数据与握手状态机——数据最小化由结构体字段硬编码保证：
// 手机发不出命令、路径、参数或环境变量，也收不到它们。
// 真实网络监听（NWListener）由未来的 Sources/MobilePairingService.swift 接入；
// 本文件保持零 I/O，verify-macos.sh 的 mobile_pairing_protocol_code 守卫强制。
import CryptoKit
import Foundation
import Network

/// M1 操作白名单（§3.4）：任何 iPhone 请求必须 match 之一，否则拒绝。
/// 与 TaskMCPBridge 的受限 case 设计同一纪律——白名单即攻击面。
enum PairedDeviceOperation: String, Codable, CaseIterable, Sendable {
    case listTools
    case requestLaunch
    case listScopes
    case listFixedTasks
    case requestTaskProposal
    case getTaskStatus
    case cancelTask
    case heartbeat
    // M4 交互会话（docs/m4-interactive-session-design.md §2.1）：
    // 订阅式长连接——openTaskStream 后连接保持，Mac 主动推流；
    // closeTaskStream 退订。前置条件：每日远程窗口开启。
    case openTaskStream
    case closeTaskStream
}

/// iPhone → Mac 请求的最小载荷。字段集合是产品红线（最小数据回传）：
/// 任何 commit 不得新增 command/path/parameter/environment 字段——
/// MobilePairingProtocolTests 锁死编码后的 key 集合。
/// M2b 增量（docs/m2b-remote-task-console-design.md §3.1）：三个任务引用
/// 字段全部是 UUID / 白名单枚举字符串，且仅对任务操作有义——
/// requestTaskProposal 用 taskKind+projectScopeID（引用 FixedTaskCatalog
/// 与已登记 scope，不下发路径），getTaskStatus/cancelTask 用 taskIntentID。
/// Optional + 合成 Codable（decodeIfPresent 语义）——旧手机/Mac 双向兼容。
struct MobilePairingRequest: Codable, Sendable, Equatable {
    let operation: PairedDeviceOperation
    let requestID: UUID
    /// 仅 listTools / heartbeat 等无目标操作为 nil。
    let toolID: UUID?
    var taskKind: String? = nil
    var projectScopeID: UUID? = nil
    var taskIntentID: UUID? = nil
    /// M4：openTaskStream 的续传偏移（断线重连场景）——从该 UTF-8 字节
    /// 偏移之后继续推送；nil = 全新订阅。旧端忽略（兼容红线）。
    var streamResumeOffset: Int? = nil
}

/// Mac → iPhone 工具目录条目：手机端只允许看到这 4 个字段。
struct MobileToolSummary: Codable, Sendable, Equatable {
    let id: UUID
    let displayName: String
    let displayDescription: String
    let iconSymbolName: String?
}

/// AEAD 信封：JSON 载荷经会话密钥加密后上传输。
enum MobilePairingEnvelope {
    static func seal(_ value: some Encodable, using key: SymmetricKey) throws -> Data {
        let data = try JSONEncoder().encode(value)
        return try MobilePairingCrypto.seal(data, using: key)
    }

    static func openRequest(_ data: Data, using key: SymmetricKey) throws -> MobilePairingRequest {
        let plaintext = try MobilePairingCrypto.open(data, using: key)
        return try JSONDecoder().decode(MobilePairingRequest.self, from: plaintext)
    }

    static func openToolSummaries(_ data: Data, using key: SymmetricKey) throws -> [MobileToolSummary] {
        let plaintext = try MobilePairingCrypto.open(data, using: key)
        return try JSONDecoder().decode([MobileToolSummary].self, from: plaintext)
    }

    static func openAck(_ data: Data, using key: SymmetricKey) throws -> MobilePairingAck {
        let plaintext = try MobilePairingCrypto.open(data, using: key)
        return try JSONDecoder().decode(MobilePairingAck.self, from: plaintext)
    }

    static func openLaunchResponse(_ data: Data, using key: SymmetricKey) throws -> MobileLaunchResponse {
        let plaintext = try MobilePairingCrypto.open(data, using: key)
        return try JSONDecoder().decode(MobileLaunchResponse.self, from: plaintext)
    }

    // MARK: M2b 任务会话信封解码（与既有 open* 同模式）

    static func openScopeSummaries(_ data: Data, using key: SymmetricKey) throws -> [MobileScopeSummary] {
        let plaintext = try MobilePairingCrypto.open(data, using: key)
        return try JSONDecoder().decode([MobileScopeSummary].self, from: plaintext)
    }

    static func openFixedTaskSummaries(_ data: Data, using key: SymmetricKey) throws -> [MobileFixedTaskSummary] {
        let plaintext = try MobilePairingCrypto.open(data, using: key)
        return try JSONDecoder().decode([MobileFixedTaskSummary].self, from: plaintext)
    }

    static func openSessionEntries(_ data: Data, using key: SymmetricKey) throws -> [MobileSessionEntry] {
        let plaintext = try MobilePairingCrypto.open(data, using: key)
        return try JSONDecoder().decode([MobileSessionEntry].self, from: plaintext)
    }

    static func openTaskProposalResponse(_ data: Data, using key: SymmetricKey) throws -> MobileTaskProposalResponse {
        let plaintext = try MobilePairingCrypto.open(data, using: key)
        return try JSONDecoder().decode(MobileTaskProposalResponse.self, from: plaintext)
    }

    // MARK: M4 交互会话信封解码

    static func openStreamResponse(_ data: Data, using key: SymmetricKey) throws -> MobileStreamResponse {
        let plaintext = try MobilePairingCrypto.open(data, using: key)
        return try JSONDecoder().decode(MobileStreamResponse.self, from: plaintext)
    }

    static func openStreamChunk(_ data: Data, using key: SymmetricKey) throws -> MobileStreamChunk {
        let plaintext = try MobilePairingCrypto.open(data, using: key)
        return try JSONDecoder().decode(MobileStreamChunk.self, from: plaintext)
    }

    static func openStreamStateChange(_ data: Data, using key: SymmetricKey) throws -> MobileStreamStateChange {
        let plaintext = try MobilePairingCrypto.open(data, using: key)
        return try JSONDecoder().decode(MobileStreamStateChange.self, from: plaintext)
    }
}

/// Mac → iPhone 配对确认（经会话密钥 AEAD 加密后发送）。
struct MobilePairingAck: Codable, Sendable, Equatable {
    let accepted: Bool
    let deviceID: UUID
}

/// Mac → iPhone 启动请求结果（§3.3.2）。手机端只收到结果枚举与可选的
/// 一句提示，永不收到命令正文/路径/变量/终端输出。
struct MobileLaunchResponse: Codable, Sendable, Equatable {
    enum Status: String, Codable, Sendable {
        case accepted
        case rejected
    }

    let status: Status
    /// 拒绝时的一句人话原因（固定枚举文案，不含工具数据）。
    let reason: String?
}

// MARK: - M2b 任务会话回传（docs/m2b-remote-task-console-design.md §3.2）
// 数据最小化纪律与 M1 目录一致：手机只见引用、显示名与固定枚举，
// 永不见 rootPath / 命令 / 参数 / 变量 / 工具启动的终端输出。

/// 项目范围条目：id + 显示名（rootPath 永不下发——范围路径是本机数据）。
struct MobileScopeSummary: Codable, Sendable, Equatable {
    let id: UUID
    let displayName: String
}

/// 固定任务目录条目：kind + 双语用途 + 固定命令预览（全部是
/// FixedTaskCatalog 字面量，非用户数据；任务提交只回传 kind 引用）。
struct MobileFixedTaskSummary: Codable, Sendable, Equatable {
    let kind: String
    let purpose: String
    let commandPreview: String
    /// M2c：任务对项目目录的固定要求（FixedTaskCatalog 字面量，非用户
    /// 数据）——手机端显示"需要：Package.swift"等，让用户能自行对上
    /// 范围与任务（2026-09-15 实测：缺文件拒绝文案精确了，但选范围时
    /// 仍无从知道哪个范围满足哪个任务）。Optional + 合成解码——旧 Mac
    /// 不发此键，旧手机忽略（兼容红线）。
    var requiredRelativePaths: [String]? = nil
}

/// 会话条目：工具启动与固定任务统一形态（§3.3——状态字符串全部来自
/// T1 TaskExecutionState 原样枚举，工具启动仅 launched/launchFailed）。
struct MobileSessionEntry: Codable, Sendable, Equatable, Identifiable {
    enum SessionKind: String, Codable, Sendable {
        case toolLaunch
        case fixedTask
    }

    let id: UUID
    let title: String
    let kind: SessionKind
    let executionState: String
    let exitCode: Int?
    let startedAt: Date?
    let finishedAt: Date?
    /// 仅输出档位 ≥ restricted 且条目为 T1 固定任务时非 nil（§5.4）；
    /// 工具启动（终端交接路径）永无输出。
    var outputSnippet: String? = nil
}

/// requestTaskProposal 的回执：接受/拒绝 + 任务引用（拒绝文案固定枚举）。
struct MobileTaskProposalResponse: Codable, Sendable, Equatable {
    enum Status: String, Codable, Sendable {
        case accepted
        case rejected
    }

    let status: Status
    /// 拒绝时的一句人话原因（固定枚举文案，无路径无命令）。
    let reason: String?
    /// 接受时手机后续 getTaskStatus / cancelTask 的任务引用。
    let taskIntentID: UUID?
}

// MARK: - M4 交互会话推送（docs/m4-interactive-session-design.md §2.1）
// Mac → 手机主动推送帧（订阅式长连接内）。全部经既有 AEAD 信封；
// 输出先经 OutputRedactor 脱敏；工具启动（终端交接）永无流。

/// 流订阅回执：接受（带游标——断线续传起点）或拒绝。
struct MobileStreamResponse: Codable, Sendable, Equatable {
    enum Status: String, Codable, Sendable {
        case accepted
        case rejected
    }

    let status: Status
    let reason: String?
    /// 续传游标：从此偏移（字节）之后的输出开始推送；新订阅为 0。
    let resumeOffset: Int?
}

/// 输出块推送（Mac → 手机，流生命周期内多次）。
struct MobileStreamChunk: Codable, Sendable, Equatable {
    let streamID: UUID
    /// 本块覆盖的字节区间起点（续传游标依据）。
    let offset: Int
    /// 脱敏后的输出文本（行级合帧，≤8KB/块）。
    let text: String
}

/// 状态变化推送。
struct MobileStreamStateChange: Codable, Sendable, Equatable {
    let streamID: UUID
    let executionState: String
    let exitCode: Int?
    let finishedAt: Date?
}

/// 交互点推送（M4-3）：任务需要决策。选项全部来自任务定义字面量。
struct MobileStreamInteraction: Codable, Sendable, Equatable {
    let streamID: UUID
    let prompt: String
    /// 固定选项（任务定义声明，非运行时生成）。
    let options: [String]
}

/// 手机端持久化凭据（原 CompanionApp 私有类型，M2a 迁入共享协议层——
/// Mac 测试可锁其编解码兼容性，两端单一事实源；iOS 端 Keychain 存储不变）。
/// `tailnetEndpoint`（M2a）：同网 resume 时由 MacResumeHello 下发并持久化，
/// 供异地直连 "100.x.x.x:57147"。可 Optional + 合成 Codable 对 Optional 用
/// decodeIfPresent——旧凭据 JSON 无此键也能解码（恢复兼容红线，测试锁）。
struct CompanionPairingCredentials: Codable, Sendable, Equatable {
    let deviceID: UUID
    let macPublicKey: Data
    let macFingerprint: String
    let deviceName: String
    var tailnetEndpoint: String? = nil
}

/// 4 字节大端长度前缀帧编解码。纯逻辑——分包/粘包由测试覆盖；
/// 网络层只做"收字节进缓冲、解出一帧、发一帧"。
enum MobilePairingFrame {
    static let headerByteCount = 4
    /// 单帧上限 64 KB：配对与工具目录消息远小于此；声明超过即协议违规，直接断连。
    static let maxPayloadByteCount = 65_536

    enum DecodeOutcome: Equatable {
        case message(Data, remainder: Data)
        case incomplete
        case invalid
    }

    static func encode(_ payload: Data) -> Data {
        var frame = Data(capacity: headerByteCount + payload.count)
        let length = UInt32(payload.count)
        frame.append(UInt8((length >> 24) & 0xFF))
        frame.append(UInt8((length >> 16) & 0xFF))
        frame.append(UInt8((length >> 8) & 0xFF))
        frame.append(UInt8(length & 0xFF))
        frame.append(payload)
        return frame
    }

    static func decodeOne(from buffer: Data) -> DecodeOutcome {
        guard buffer.count >= headerByteCount else { return .incomplete }
        let header = [UInt8](buffer.prefix(headerByteCount))
        let declaredLength = (UInt32(header[0]) << 24)
            | (UInt32(header[1]) << 16)
            | (UInt32(header[2]) << 8)
            | UInt32(header[3])
        guard declaredLength <= maxPayloadByteCount else { return .invalid }
        let total = headerByteCount + Int(declaredLength)
        guard buffer.count >= total else { return .incomplete }
        let message = Data(buffer.dropFirst(headerByteCount).prefix(Int(declaredLength)))
        let remainder = Data(buffer.dropFirst(total))
        return .message(message, remainder: remainder)
    }
}

/// Bonjour 广播契约：服务类型固定，不允许运行时配置——防仿冒服务重定向。
/// TXT 只广播协议版本 + 指纹前缀 + LAN 直连地址（a/p，供手机绕开 iOS 26
/// 对 .service 端点的解析卡死）；不广播主机名/用户名/工具信息。
extension MobilePairingCrypto {
    static let bonjourServiceType = "_termipad-m1._tcp"
    static let bonjourServiceName = "TermiPad"
    /// M1 监听固定端口（Mac 端监听用它；手机端从实例名还原直连地址时拼端口）。
    /// 跨端共享故放协议层。
    static let listenerPort: UInt16 = 57146
    /// M2a 异地隧道监听固定端口（Mac 回环监听 + tailscale serve TCP 转发；
    /// 与 M1 的 57146 独立——两条路径互不干扰、可独立开关、故障域隔离）。
    static let tunnelListenerPort: UInt16 = 57147

    static func bonjourTXTRecord(fingerprint: String) -> [String: String] {
        [
            "v": protocolVersion,
            "fp": String(fingerprint.prefix(16))
        ]
    }

    /// TXT 是否携带直连地址（"a"=IPv4, "p"=端口）——手机端用它决定
    /// 走 hostPort 直连还是回退到 .service 端点解析。
    static func bonjourDirectAddress(fromTXT txt: NWTXTRecord) -> (host: String, port: UInt16)? {
        guard let host = txt["a"], let portString = txt["p"],
              let port = UInt16(portString), !host.isEmpty else {
            return nil
        }
        return (host, port)
    }
}

/// 配对握手（§3.3 步骤 3-6）的 Mac 侧状态机。纯逻辑：真实收发由网络层调用，
/// 测试用双端进程内模拟完成全握手。
enum MobilePairingHandshake {
    static let currentProtocolVersion = MobilePairingCrypto.protocolVersion
    static let resumeProtocolInfo = "termipad-m1-resume-v1"

    /// Mac → iPhone 第一步：公布协议版本、公钥、nonce 与指纹（iPhone 屏上人工比对）。
    struct MacHello: Codable, Sendable, Equatable {
        let protocolVersion: String
        let macPublicKey: Data
        let macNonce: Data
        let fingerprint: String
    }

    /// iPhone → Mac 第二步：手机公钥 + nonce + 用户抄写的配对码 + 设备名。
    struct PhoneHello: Codable, Sendable, Equatable {
        let protocolVersion: String
        let phonePublicKey: Data
        let phoneNonce: Data
        let pairingCode: String
        let deviceName: String
    }

    /// Mac 接受配对后的产物：会话密钥 + 待写入 PairedDeviceStore 的最小记录。
    struct AcceptedPairing: Sendable, Equatable {
        let sessionKeyData: Data
        let phonePublicKeyHash: String
        let deviceName: String
    }

    static func makeMacHello(identity: MobilePairingIdentity, macNonce: Data) throws -> MacHello {
        guard macNonce.count == MobilePairingCrypto.nonceByteCount else {
            throw MobilePairingError.invalidNonce
        }
        let publicKey = try identity.publicKeyData()
        return MacHello(
            protocolVersion: currentProtocolVersion,
            macPublicKey: publicKey,
            macNonce: macNonce,
            fingerprint: MobilePairingCrypto.fingerprint(forPublicKeyData: publicKey))
    }

    static func acceptPhoneHello(
        _ hello: PhoneHello,
        identity: MobilePairingIdentity,
        macNonce: Data
    ) throws -> AcceptedPairing {
        // 协议版本精确钉死（与 MCP initialize 版本协商同一纪律）——不接受"更高版本"。
        guard hello.protocolVersion == currentProtocolVersion else {
            throw MobilePairingError.unsupportedProtocolVersion
        }
        guard hello.pairingCode.utf8.count == MobilePairingCrypto.pairingCodeDigitCount else {
            throw MobilePairingError.invalidPairingCode
        }
        guard hello.phoneNonce.count == MobilePairingCrypto.nonceByteCount,
              macNonce.count == MobilePairingCrypto.nonceByteCount else {
            throw MobilePairingError.invalidNonce
        }
        guard !hello.deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MobilePairingError.invalidDeviceName
        }
        let key = try identity.sessionKey(
            peerPublicKeyData: hello.phonePublicKey,
            pairingCode: hello.pairingCode,
            macNonce: macNonce,
            phoneNonce: hello.phoneNonce)
        return AcceptedPairing(
            sessionKeyData: key.withUnsafeBytes { Data($0) },
            phonePublicKeyHash: MobilePairingCrypto.fingerprint(forPublicKeyData: hello.phonePublicKey),
            deviceName: hello.deviceName)
    }

    // MARK: - 会话复用（§3.3.1，2026-09-06 增补）

    /// 已配对手机重连时的第一个帧。无 pairingCode 字段——与 PhoneHello 靠字段区分。
    struct PhoneResumeHello: Codable, Sendable, Equatable {
        let protocolVersion: String
        let deviceID: UUID
        let phonePublicKey: Data
        let phoneNonce: Data
    }

    /// Mac 回给已配对手机的明文 hello（公钥与 nonce 非机密；后续全部帧走 AEAD）。
    /// M2a 增补：`tailnetEndpoint` 仅当 Mac 端开启"异地访问"时非 nil
    /// （"100.x.x.x:57147"）。明文可接受——tailnet IP 的机密性由 tailnet
    /// 成员资格天然保障，非成员路由不到 100.64/10；连接仍需应用层配对双通过。
    /// 旧 Mac 不发此字段（解码得 nil）；旧手机忽略未知键——双向兼容。
    struct MacResumeHello: Codable, Sendable, Equatable {
        let protocolVersion: String
        let macPublicKey: Data
        let macNonce: Data
        var tailnetEndpoint: String? = nil
    }

    /// Mac 收到的第一个 hello 的分流结果。
    enum IncomingHello {
        case pairing(PhoneHello)
        case resume(PhoneResumeHello)
    }

    /// 按 JSON 字段存在性区分两种 hello：含 pairingCode → 配对；含 deviceID → 复用。
    static func decodeIncomingHello(from data: Data) -> IncomingHello? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if object["pairingCode"] != nil {
            return (try? JSONDecoder().decode(PhoneHello.self, from: data)).map { .pairing($0) }
        }
        if object["deviceID"] != nil {
            return (try? JSONDecoder().decode(PhoneResumeHello.self, from: data)).map { .resume($0) }
        }
        return nil
    }

    /// Mac 侧复用校验 + 会话密钥派生。拆为两步以让 iOS 端也能复用纯计算部分：
    /// 1. `validateResumeRecord`：版本/记录/指纹三重绑定（Mac 专用，依赖 PairedDeviceRecord）
    /// 2. `resumeSessionKey`：纯计算，签名双方一致即同密钥
    ///
    /// 整体等价于原 `acceptResume` + `expectedRecord.revokedAt == nil` + 公钥指纹校验。
    /// 拆出的目的是让 iOS 复用握手代码无须引入 Mac 专用 PairedDeviceRecord 类型。

    /// 纯计算侧：版本钉死 + 派生会话密钥。iOS 端在双向公钥指纹绑定后调用此方法。
    /// Mac 端先调 `validateResumeRecord` 再调本方法——两步等价原 `acceptResume`。
    static func deriveResumeSessionKey(
        _ hello: PhoneResumeHello,
        identity: MobilePairingIdentity,
        macNonce: Data
    ) throws -> Data {
        guard hello.protocolVersion == currentProtocolVersion else {
            throw MobilePairingError.unsupportedProtocolVersion
        }
        guard hello.phoneNonce.count == MobilePairingCrypto.nonceByteCount,
              macNonce.count == MobilePairingCrypto.nonceByteCount else {
            throw MobilePairingError.invalidNonce
        }
        let key = try identity.resumeSessionKey(
            peerPublicKeyData: hello.phonePublicKey,
            macNonce: macNonce,
            phoneNonce: hello.phoneNonce)
        return key.withUnsafeBytes { Data($0) }
    }
}
