import XCTest
import CryptoKit
@testable import TermiPad

/// M1 pairing core contract tests (feature/m1-local-network-pairing).
/// Everything uses the in-memory dual implementation of storage and never hits the real SecItem (same discipline as KeychainStoreTests).
final class MobilePairingTests: XCTestCase {
    /// In-memory backend: test domain only. Satisfies the same protocol contract as the production KeychainMobileSecureStore.
    private final class InMemorySecureStore: MobileSecureKeyValueStore, @unchecked Sendable {
        private var values: [String: String] = [:]
        private let lock = NSLock()

        func string(for account: String) throws -> String? {
            lock.lock()
            defer { lock.unlock() }
            return values[account]
        }

        func save(_ value: String, for account: String) throws {
            lock.lock()
            defer { lock.unlock() }
            values[account] = value
        }

        func remove(account: String) throws {
            lock.lock()
            defer { lock.unlock() }
            values.removeValue(forKey: account)
        }
    }

    private static func keyData(_ key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }

    // MARK: - Pairing code and nonce

    func testPairingCodeIsSixNumericDigits() {
        let allowedDigits = Set("0123456789")
        for _ in 0..<50 {
            let code = MobilePairingCrypto.generatePairingCode()
            XCTAssertEqual(code.count, MobilePairingCrypto.pairingCodeDigitCount)
            XCTAssertTrue(code.allSatisfy { allowedDigits.contains($0) }, "The pairing code must be digits only: \(code)")
        }
    }

    func testNonceIsSixteenBytesAndUnique() {
        let first = MobilePairingCrypto.generateNonce()
        let second = MobilePairingCrypto.generateNonce()
        XCTAssertEqual(first.count, MobilePairingCrypto.nonceByteCount)
        XCTAssertEqual(second.count, MobilePairingCrypto.nonceByteCount)
        XCTAssertNotEqual(first, second)
    }

    // MARK: - Key agreement and derivation

    func testBothSidesDeriveIdenticalSessionKey() throws {
        let mac = MobilePairingIdentity.generate()
        let phone = MobilePairingIdentity.generate()
        let pairingCode = MobilePairingCrypto.generatePairingCode()
        let macNonce = MobilePairingCrypto.generateNonce()
        let phoneNonce = MobilePairingCrypto.generateNonce()

        let macKey = try mac.sessionKey(
            peerPublicKeyData: phone.publicKeyData(),
            pairingCode: pairingCode,
            macNonce: macNonce,
            phoneNonce: phoneNonce)
        let phoneKey = try phone.sessionKey(
            peerPublicKeyData: mac.publicKeyData(),
            pairingCode: pairingCode,
            macNonce: macNonce,
            phoneNonce: phoneNonce)

        XCTAssertEqual(Self.keyData(macKey), Self.keyData(phoneKey))
    }

    func testSessionKeyBindsToPairingCodeAndNonces() throws {
        let mac = MobilePairingIdentity.generate()
        let phone = MobilePairingIdentity.generate()
        let macNonce = MobilePairingCrypto.generateNonce()
        let phoneNonce = MobilePairingCrypto.generateNonce()

        let baseline = try mac.sessionKey(
            peerPublicKeyData: phone.publicKeyData(),
            pairingCode: "042913",
            macNonce: macNonce,
            phoneNonce: phoneNonce)
        let otherCode = try mac.sessionKey(
            peerPublicKeyData: phone.publicKeyData(),
            pairingCode: "042914",
            macNonce: macNonce,
            phoneNonce: phoneNonce)
        let otherNonce = try mac.sessionKey(
            peerPublicKeyData: phone.publicKeyData(),
            pairingCode: "042913",
            macNonce: MobilePairingCrypto.generateNonce(),
            phoneNonce: phoneNonce)

        XCTAssertNotEqual(Self.keyData(baseline), Self.keyData(otherCode))
        XCTAssertNotEqual(Self.keyData(baseline), Self.keyData(otherNonce))
    }

    func testSessionKeyRejectsMalformedInputs() throws {
        let mac = MobilePairingIdentity.generate()
        let phone = MobilePairingIdentity.generate()
        let nonce = MobilePairingCrypto.generateNonce()

        XCTAssertThrowsError(try mac.sessionKey(
            peerPublicKeyData: phone.publicKeyData(),
            pairingCode: "04291",
            macNonce: nonce,
            phoneNonce: nonce)) { error in
            XCTAssertEqual(error as? MobilePairingError, .invalidPairingCode)
        }
        XCTAssertThrowsError(try mac.sessionKey(
            peerPublicKeyData: phone.publicKeyData(),
            pairingCode: "042913",
            macNonce: Data(repeating: 0, count: 15),
            phoneNonce: nonce)) { error in
            XCTAssertEqual(error as? MobilePairingError, .invalidNonce)
        }
    }

    // MARK: - AEAD

    func testAEADRoundTripAndTamperDetection() throws {
        let key = try MobilePairingIdentity.generate()
            .sessionKey(
                peerPublicKeyData: MobilePairingIdentity.generate().publicKeyData(),
                pairingCode: "042913",
                macNonce: MobilePairingCrypto.generateNonce(),
                phoneNonce: MobilePairingCrypto.generateNonce())
        let plaintext = Data("minimal-result".utf8)

        let sealed = try MobilePairingCrypto.seal(plaintext, using: key)
        XCTAssertEqual(try MobilePairingCrypto.open(sealed, using: key), plaintext)

        var tampered = sealed
        tampered[tampered.count - 1] = tampered[tampered.count - 1] ^ 0xFF
        XCTAssertThrowsError(try MobilePairingCrypto.open(tampered, using: key))
    }

    // MARK: - Fingerprint

    func testFingerprintIsStableHexGroups() {
        let fingerprint = MobilePairingCrypto.fingerprint(forPublicKeyData: Data(repeating: 0x7A, count: 32))
        // SHA-256 = 32 bytes → 64 hex characters → 16 groups of 4 characters.
        XCTAssertEqual(fingerprint.split(separator: ":").count, 16)
        XCTAssertTrue(fingerprint.allSatisfy { $0.isHexDigit || $0 == ":" }, "The fingerprint may only contain hex and separators: \(fingerprint)")
        XCTAssertEqual(fingerprint, fingerprint.uppercased())
        XCTAssertEqual(
            fingerprint,
            MobilePairingCrypto.fingerprint(forPublicKeyData: Data(repeating: 0x7A, count: 32)),
            "the same public key must yield the same fingerprint")
        XCTAssertNotEqual(
            fingerprint,
            MobilePairingCrypto.fingerprint(forPublicKeyData: Data(repeating: 0x7B, count: 32)),
            "different public keys must not collide in fingerprint")
    }

    // MARK: - Device record storage

    func testDeviceStoreRoundTripRevokeAndFilter() throws {
        let store = InMemorySecureStore()
        let deviceA = try PairedDeviceStore.add(
            displayName: "iPhone 16 Pro",
            publicKeyData: Data(repeating: 1, count: 32),
            store: store)
        let deviceB = try PairedDeviceStore.add(
            displayName: "iPhone SE",
            publicKeyData: Data(repeating: 2, count: 32),
            store: store)

        XCTAssertEqual(Set(PairedDeviceStore.list(store: store).map(\.id)), Set([deviceA.id, deviceB.id]))
        XCTAssertEqual(PairedDeviceStore.activeDevices(store: store).count, 2)

        try PairedDeviceStore.revoke(id: deviceA.id, store: store)
        XCTAssertEqual(PairedDeviceStore.activeDevices(store: store).map(\.id), [deviceB.id])
        XCTAssertNotNil(PairedDeviceStore.find(id: deviceA.id, store: store)?.revokedAt)

        XCTAssertEqual(
            PairedDeviceStore.findActive(byPublicKeyHash: deviceB.publicKeyHash, store: store)?.id,
            deviceB.id)
        XCTAssertNil(PairedDeviceStore.findActive(byPublicKeyHash: deviceA.publicKeyHash, store: store))

        let connectedAt = Date(timeIntervalSince1970: 1_800_000_000)
        try PairedDeviceStore.markConnected(id: deviceB.id, at: connectedAt, store: store)
        XCTAssertEqual(PairedDeviceStore.find(id: deviceB.id, store: store)?.lastConnectedAt, connectedAt)

        try PairedDeviceStore.removeAll(store: store)
        XCTAssertTrue(PairedDeviceStore.list(store: store).isEmpty)
    }

    func testIdentityStoreLoadOrCreateIsStable() throws {
        let store = InMemorySecureStore()
        let first = try PairedDeviceStore.MobilePairingIdentityStore.loadOrCreate(store: store)
        let second = try PairedDeviceStore.MobilePairingIdentityStore.loadOrCreate(store: store)
        XCTAssertEqual(try first.publicKeyData(), try second.publicKeyData())
    }
}
