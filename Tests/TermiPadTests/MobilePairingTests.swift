import XCTest
import CryptoKit
@testable import TermiPad

/// M1 配对核心契约测试（feature/m1-local-network-pairing）。
/// 全部走内存存储双实现，不打真实 SecItem（与 KeychainStoreTests 纪律一致）。
final class MobilePairingTests: XCTestCase {
    /// 内存后端：仅测试域。与生产 KeychainMobileSecureStore 满足同一协议契约。
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

    // MARK: - 配对码与 nonce

    func testPairingCodeIsSixNumericDigits() {
        let allowedDigits = Set("0123456789")
        for _ in 0..<50 {
            let code = MobilePairingCrypto.generatePairingCode()
            XCTAssertEqual(code.count, MobilePairingCrypto.pairingCodeDigitCount)
            XCTAssertTrue(code.allSatisfy { allowedDigits.contains($0) }, "配对码必须是纯数字：\(code)")
        }
    }

    func testNonceIsSixteenBytesAndUnique() {
        let first = MobilePairingCrypto.generateNonce()
        let second = MobilePairingCrypto.generateNonce()
        XCTAssertEqual(first.count, MobilePairingCrypto.nonceByteCount)
        XCTAssertEqual(second.count, MobilePairingCrypto.nonceByteCount)
        XCTAssertNotEqual(first, second)
    }

    // MARK: - 密钥协商与派生

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

    // MARK: - 指纹

    func testFingerprintIsStableHexGroups() {
        let fingerprint = MobilePairingCrypto.fingerprint(forPublicKeyData: Data(repeating: 0x7A, count: 32))
        // SHA-256 = 32 字节 → 64 hex 字符 → 16 个 4 字符分组。
        XCTAssertEqual(fingerprint.split(separator: ":").count, 16)
        XCTAssertTrue(fingerprint.allSatisfy { $0.isHexDigit || $0 == ":" }, "指纹只允许 hex 与分隔符：\(fingerprint)")
        XCTAssertEqual(fingerprint, fingerprint.uppercased())
        XCTAssertEqual(
            fingerprint,
            MobilePairingCrypto.fingerprint(forPublicKeyData: Data(repeating: 0x7A, count: 32)),
            "同一公钥必须得到同一指纹")
        XCTAssertNotEqual(
            fingerprint,
            MobilePairingCrypto.fingerprint(forPublicKeyData: Data(repeating: 0x7B, count: 32)),
            "不同公钥不得碰撞指纹")
    }

    // MARK: - 设备记录存储

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
