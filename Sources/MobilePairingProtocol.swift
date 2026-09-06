// M1 同网配对协议层（docs/m0-m1-mobile-entry-design.md §3.3-§3.4）。
// 本文件只做协议数据与握手状态机——数据最小化由结构体字段硬编码保证：
// 手机发不出命令、路径、参数或环境变量，也收不到它们。
// 真实网络监听（NWListener）由未来的 Sources/MobilePairingService.swift 接入；
// 本文件保持零 I/O，verify-macos.sh 的 mobile_pairing_protocol_code 守卫强制。
import CryptoKit
import Foundation

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
}

/// Bonjour 广播契约：服务类型固定，不允许运行时配置——防仿冒服务重定向。
/// TXT 只广播协议版本 + 指纹前缀，足以让手机预筛，不广播主机名/用户名/工具信息。
extension MobilePairingCrypto {
    static let bonjourServiceType = "_termipad-m1._tcp"
    static let bonjourServiceName = "TermiPad"

    static func bonjourTXTRecord(fingerprint: String) -> [String: String] {
        [
            "v": protocolVersion,
            "fp": String(fingerprint.prefix(16))
        ]
    }
}

/// 配对握手（§3.3 步骤 3-6）的 Mac 侧状态机。纯逻辑：真实收发由网络层调用，
/// 测试用双端进程内模拟完成全握手。
enum MobilePairingHandshake {
    static let currentProtocolVersion = MobilePairingCrypto.protocolVersion

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
}
