// M1 同网配对的密码学核心（docs/m0-m1-mobile-entry-design.md §3.2-§3.3）。
// 本文件必须保持纯计算：零 I/O、零网络、零进程——由 verify-macos.sh 的
// mobile_pairing_core_code 守卫强制。网络监听只允许出现在未来的
// MobilePairingService.swift 并由专门守卫圈定。
import CryptoKit
import Foundation
import Security

enum MobilePairingCrypto {
    static let protocolVersion = "termipad-m1-pairing-v1"
    static let pairingCodeDigitCount = 6
    static let nonceByteCount = 16

    /// 6 位数字配对码。必须用 SecRandomCopyBytes 而非 SystemRandomNumberGenerator：
    /// 配对码参与密钥派生，可预测即等于配对通道可被离线推算。
    static func generatePairingCode() -> String {
        var bytes = [UInt8](repeating: 0, count: pairingCodeDigitCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, pairingCodeDigitCount, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes 失败：\(status)")
        return bytes.map { String($0 % 10) }.joined()
    }

    static func generateNonce() -> Data {
        var bytes = [UInt8](repeating: 0, count: nonceByteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, nonceByteCount, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes 失败：\(status)")
        return Data(bytes)
    }
}

/// Mac 端长期配对身份（X25519）。结构体只持有私钥原始字节（Data 天然 Sendable），
/// 需要时再物化 CryptoKit 私钥对象，避免跨并发域持有非 Sendable 句柄。
struct MobilePairingIdentity: Sendable, Equatable {
    let privateKeyData: Data

    init(privateKeyData: Data) {
        self.privateKeyData = privateKeyData
    }

    static func generate() -> MobilePairingIdentity {
        MobilePairingIdentity(privateKeyData: Curve25519.KeyAgreement.PrivateKey().rawRepresentation)
    }

    func publicKeyData() throws -> Data {
        let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKeyData)
        return privateKey.publicKey.rawRepresentation
    }

    /// X25519 + HKDF-SHA256 派生配对通道对称密钥。
    /// salt = 配对码(6B) ‖ Mac nonce(16B) ‖ 手机 nonce(16B)：三段长度全部固定，
    /// 拼接无歧义，双方按同一角色顺序计算才能得到同一密钥——不用 local/peer
    /// 顺序（两侧各算各的会拼出不同 salt）。info = 协议版本，换版本即换密钥。
    func sessionKey(
        peerPublicKeyData: Data,
        pairingCode: String,
        macNonce: Data,
        phoneNonce: Data
    ) throws -> SymmetricKey {
        guard pairingCode.utf8.count == MobilePairingCrypto.pairingCodeDigitCount else {
            throw MobilePairingError.invalidPairingCode
        }
        guard macNonce.count == MobilePairingCrypto.nonceByteCount,
              phoneNonce.count == MobilePairingCrypto.nonceByteCount else {
            throw MobilePairingError.invalidNonce
        }
        let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKeyData)
        let peerPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicKeyData)
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: peerPublicKey)
        var salt = Data(pairingCode.utf8)
        salt.append(macNonce)
        salt.append(phoneNonce)
        return sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: Data(MobilePairingCrypto.protocolVersion.utf8),
            outputByteCount: 32)
    }
}

enum MobilePairingError: Error, Equatable {
    case invalidPairingCode
    case invalidNonce
    case sealFailed
    case unsupportedProtocolVersion
    case invalidDeviceName
    case handshakeFailed
}

extension MobilePairingCrypto {
    /// AES-GCM；返回 combined（nonce ‖ ciphertext ‖ tag），解密端无需单独传 nonce。
    static func seal(_ plaintext: Data, using key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key)
        guard let combined = box.combined else {
            throw MobilePairingError.sealFailed
        }
        return combined
    }

    static func open(_ combined: Data, using key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(box, using: key)
    }

    /// SHA-256 公钥指纹：大写 hex、每 2 字节（4 字符）一组、":" 分隔。
    /// 配对时用户在 iPhone 上人工比对——这是抗中间人攻击的关键凭据。
    static func fingerprint(forPublicKeyData publicKeyData: Data) -> String {
        let hex = SHA256.hash(data: publicKeyData)
            .map { byte -> String in
                let s = String(byte, radix: 16)
                return s.count == 1 ? "0" + s : s
            }
            .joined()
            .uppercased()
        var groups: [String] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let end = hex.index(index, offsetBy: 4, limitedBy: hex.endIndex) ?? hex.endIndex
            groups.append(String(hex[index..<end]))
            index = end
        }
        return groups.joined(separator: ":")
    }
}
