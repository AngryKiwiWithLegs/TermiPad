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
}

/// iPhone → Mac 请求的最小载荷。字段集合是产品红线（最小数据回传）：
/// 任何 commit 不得新增 command/path/parameter/environment 字段——
/// MobilePairingProtocolTests 锁死编码后的 key 集合。
struct MobilePairingRequest: Codable, Sendable, Equatable {
    let operation: PairedDeviceOperation
    let requestID: UUID
    /// 仅 listTools / heartbeat 等无目标操作为 nil。
    let toolID: UUID?
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
    struct MacResumeHello: Codable, Sendable, Equatable {
        let protocolVersion: String
        let macPublicKey: Data
        let macNonce: Data
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
