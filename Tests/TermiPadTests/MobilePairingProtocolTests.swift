import XCTest
import CryptoKit
@testable import TermiPad

/// M1 配对协议层契约测试：数据最小化（编码 key 集合）、AEAD 信封、
/// 操作白名单、握手状态机。全部纯逻辑，零真实网络。
final class MobilePairingProtocolTests: XCTestCase {
    private static func keyData(_ key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }

    /// 构造一对已协商的会话密钥（Mac 侧视角）。
    private func makeSessionKey() throws -> SymmetricKey {
        try MobilePairingIdentity.generate().sessionKey(
            peerPublicKeyData: MobilePairingIdentity.generate().publicKeyData(),
            pairingCode: "042913",
            macNonce: MobilePairingCrypto.generateNonce(),
            phoneNonce: MobilePairingCrypto.generateNonce())
    }

    // MARK: - 数据最小化契约

    func testRequestEncodesOnlyWhitelistedKeys() throws {
        let request = MobilePairingRequest(
            operation: .requestLaunch,
            requestID: UUID(),
            toolID: UUID())
        let json = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        // 任何新增字段（command/path/param/env）都会让这个集合扩大而失败。
        XCTAssertEqual(Set(object.keys), Set(["operation", "requestID", "toolID"]))
    }

    func testToolSummaryEncodesOnlyWhitelistedKeys() throws {
        let summary = MobileToolSummary(
            id: UUID(),
            displayName: "跑测试",
            displayDescription: "运行 swift test",
            iconSymbolName: "hammer")
        let json = try JSONEncoder().encode([summary])
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: json) as? [[String: Any]])
        let summaryObject = try XCTUnwrap(object.first)
        // 任何新增字段（命令/路径/参数）都会让这个集合扩大而失败。
        XCTAssertEqual(Set(summaryObject.keys), Set(["id", "displayName", "displayDescription", "iconSymbolName"]))
    }

    // MARK: - 操作白名单

    func testOperationWhitelistMatchesDesignDoc() {
        // §3.4 的 8 个 case 固定——新增操作必须先改设计文档与本测试。
        XCTAssertEqual(
            Set(PairedDeviceOperation.allCases.map(\.rawValue)),
            Set(["listTools", "requestLaunch", "listScopes", "listFixedTasks",
                 "requestTaskProposal", "getTaskStatus", "cancelTask", "heartbeat"]))
    }

    // MARK: - AEAD 信封

    func testEnvelopeRoundTripBothDirections() throws {
        let key = try makeSessionKey()
        let request = MobilePairingRequest(operation: .listTools, requestID: UUID(), toolID: nil)
        let sealed = try MobilePairingEnvelope.seal(request, using: key)
        XCTAssertEqual(try MobilePairingEnvelope.openRequest(sealed, using: key), request)

        let summaries = [
            MobileToolSummary(id: UUID(), displayName: "构建", displayDescription: "", iconSymbolName: nil)
        ]
        let sealedSummaries = try MobilePairingEnvelope.seal(summaries, using: key)
        XCTAssertEqual(try MobilePairingEnvelope.openToolSummaries(sealedSummaries, using: key), summaries)
    }

    func testEnvelopeTamperAndWrongKeyRejected() throws {
        let key = try makeSessionKey()
        let sealed = try MobilePairingEnvelope.seal(
            MobilePairingRequest(operation: .heartbeat, requestID: UUID(), toolID: nil),
            using: key)
        var tampered = sealed
        tampered[tampered.count - 1] = tampered[tampered.count - 1] ^ 0xFF
        XCTAssertThrowsError(try MobilePairingEnvelope.openRequest(tampered, using: key))
        XCTAssertThrowsError(try MobilePairingEnvelope.openRequest(sealed, using: try makeSessionKey()))
    }

    // MARK: - Bonjour 契约

    func testBonjourServiceTypeIsPinned() {
        // 服务类型固定，不允许运行时配置——改这里必须连同守卫一起改。
        XCTAssertEqual(MobilePairingCrypto.bonjourServiceType, "_termipad-m1._tcp")
        XCTAssertEqual(MobilePairingCrypto.bonjourServiceName, "TermiPad")
    }

    func testBonjourTXTOnlyCarriesVersionAndFingerprintPrefix() {
        let txt = MobilePairingCrypto.bonjourTXTRecord(fingerprint: String(repeating: "AB", count: 40))
        XCTAssertEqual(Set(txt.keys), Set(["v", "fp"]))
        XCTAssertEqual(txt["v"], MobilePairingCrypto.protocolVersion)
        XCTAssertEqual(txt["fp"]?.count, 16)
    }

    // MARK: - 握手状态机

    func testHandshakeRoundTripDerivesSameKeyOnBothSides() throws {
        let mac = MobilePairingIdentity.generate()
        let phone = MobilePairingIdentity.generate()
        let macNonce = MobilePairingCrypto.generateNonce()
        let phoneNonce = MobilePairingCrypto.generateNonce()
        let pairingCode = MobilePairingCrypto.generatePairingCode()

        let macHello = try MobilePairingHandshake.makeMacHello(identity: mac, macNonce: macNonce)
        XCTAssertEqual(macHello.fingerprint.count, 79, "16 组 4 hex + 15 个分隔符")

        let phoneHello = MobilePairingHandshake.PhoneHello(
            protocolVersion: MobilePairingHandshake.currentProtocolVersion,
            phonePublicKey: try phone.publicKeyData(),
            phoneNonce: phoneNonce,
            pairingCode: pairingCode,
            deviceName: "iPhone 16 Pro")
        let accepted = try MobilePairingHandshake.acceptPhoneHello(phoneHello, identity: mac, macNonce: macNonce)

        // 手机侧用同一公式独立推导，密钥必须一致。
        let phoneSideKey = try phone.sessionKey(
            peerPublicKeyData: try mac.publicKeyData(),
            pairingCode: pairingCode,
            macNonce: macNonce,
            phoneNonce: phoneNonce)
        XCTAssertEqual(accepted.sessionKeyData, Self.keyData(phoneSideKey))
        XCTAssertEqual(accepted.phonePublicKeyHash, MobilePairingCrypto.fingerprint(forPublicKeyData: try phone.publicKeyData()))
        XCTAssertEqual(accepted.deviceName, "iPhone 16 Pro")
    }

    func testHandshakeRejectsWrongVersionCodeAndName() throws {
        let mac = MobilePairingIdentity.generate()
        let phone = MobilePairingIdentity.generate()
        let macNonce = MobilePairingCrypto.generateNonce()
        let phoneNonce = MobilePairingCrypto.generateNonce()

        func hello(protocolVersion: String, pairingCode: String, deviceName: String) -> MobilePairingHandshake.PhoneHello {
            MobilePairingHandshake.PhoneHello(
                protocolVersion: protocolVersion,
                phonePublicKey: (try? phone.publicKeyData()) ?? Data(),
                phoneNonce: phoneNonce,
                pairingCode: pairingCode,
                deviceName: deviceName)
        }

        XCTAssertThrowsError(try MobilePairingHandshake.acceptPhoneHello(
            hello(protocolVersion: "termipad-m1-pairing-v9", pairingCode: "042913", deviceName: "iPhone"),
            identity: mac, macNonce: macNonce)) { error in
            XCTAssertEqual(error as? MobilePairingError, .unsupportedProtocolVersion)
        }
        XCTAssertThrowsError(try MobilePairingHandshake.acceptPhoneHello(
            hello(protocolVersion: MobilePairingHandshake.currentProtocolVersion, pairingCode: "04291", deviceName: "iPhone"),
            identity: mac, macNonce: macNonce)) { error in
            XCTAssertEqual(error as? MobilePairingError, .invalidPairingCode)
        }
        XCTAssertThrowsError(try MobilePairingHandshake.acceptPhoneHello(
            hello(protocolVersion: MobilePairingHandshake.currentProtocolVersion, pairingCode: "042913", deviceName: "   "),
            identity: mac, macNonce: macNonce)) { error in
            XCTAssertEqual(error as? MobilePairingError, .invalidDeviceName)
        }
    }
}
