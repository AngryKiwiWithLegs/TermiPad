// Cryptographic core of M1 local network pairing (docs/m0-m1-mobile-entry-design.md §3.2-§3.3).
// This file must stay pure computation: zero I/O, zero network, zero processes — enforced by the
// mobile_pairing_core_code guard in verify-macos.sh. Network listening may only appear in the future
// MobilePairingService.swift, fenced in by a dedicated guard.
import CryptoKit
import Foundation
import Security

enum MobilePairingCrypto {
    static let protocolVersion = "termipad-m1-pairing-v1"
    static let pairingCodeDigitCount = 6
    static let nonceByteCount = 16

    /// 6-digit numeric pairing code. It must use SecRandomCopyBytes rather than SystemRandomNumberGenerator:
    /// the pairing code takes part in key derivation, so being predictable would mean the pairing channel can be derived offline.
    static func generatePairingCode() -> String {
        var bytes = [UInt8](repeating: 0, count: pairingCodeDigitCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, pairingCodeDigitCount, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
        return bytes.map { String($0 % 10) }.joined()
    }

    static func generateNonce() -> Data {
        var bytes = [UInt8](repeating: 0, count: nonceByteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, nonceByteCount, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
        return Data(bytes)
    }
}

/// The Mac's long-term pairing identity (X25519). The struct holds only the raw private-key bytes (Data is naturally Sendable)
/// and materializes the CryptoKit private-key object only when needed, to avoid holding a non-Sendable handle across concurrency domains.
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

    /// X25519 + HKDF-SHA256 session key derivation (§3.3.1 session resume).
    /// Uses a different info domain from the pairing derivation (sessionKey) — the same key material is never reused across protocols.
    /// salt = macNonce ‖ phoneNonce (role order, fixed lengths, unambiguous concatenation).
    func resumeSessionKey(
        peerPublicKeyData: Data,
        macNonce: Data,
        phoneNonce: Data
    ) throws -> SymmetricKey {
        guard macNonce.count == MobilePairingCrypto.nonceByteCount,
              phoneNonce.count == MobilePairingCrypto.nonceByteCount else {
            throw MobilePairingError.invalidNonce
        }
        let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKeyData)
        let peerPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicKeyData)
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: peerPublicKey)
        var salt = macNonce
        salt.append(phoneNonce)
        return sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: Data(MobilePairingHandshake.resumeProtocolInfo.utf8),
            outputByteCount: 32)
    }

    /// X25519 + HKDF-SHA256 derivation of the pairing channel's symmetric key.
    /// salt = pairing code (6B) ‖ Mac nonce (16B) ‖ phone nonce (16B): all three lengths are fixed,
    /// the concatenation is unambiguous, and both sides get the same key only by computing in the same role order — not local/peer
    /// order (each side computing its own way would produce a different salt). info = protocol version, so a new version means a new key.
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
    /// AES-GCM; returns combined (nonce ‖ ciphertext ‖ tag), so the decrypting side does not need the nonce sent separately.
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

    /// SHA-256 public-key fingerprint: uppercase hex, grouped every 2 bytes (4 characters), separated by ":".
    /// The user compares it by eye on the iPhone during pairing — this is the key credential against man-in-the-middle attacks.
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
