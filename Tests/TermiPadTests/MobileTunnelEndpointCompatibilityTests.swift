import XCTest
@testable import TermiPad

/// M2a 协议增量兼容性测试（docs/m2-secure-remote-session-design.md §4.1）。
/// 恢复兼容红线：新增字段必须 Optional + 旧数据可解码——这里锁死两个
/// 旧版本载荷的解码行为，防止任何 commit 破坏已装机手机的凭据读取。
final class MobileTunnelEndpointCompatibilityTests: XCTestCase {
    /// 旧版 MacResumeHello JSON（M1，无 tailnetEndpoint 键）必须解码成功且端点为 nil。
    func testMacResumeHelloWithoutEndpointDecodesFromLegacyJSON() throws {
        let legacy = """
        {"protocolVersion":"1","macPublicKey":"AAEC","macNonce":"AAEC"}
        """
        let hello = try JSONDecoder().decode(
            MobilePairingHandshake.MacResumeHello.self, from: Data(legacy.utf8))
        XCTAssertNil(hello.tailnetEndpoint)
        XCTAssertEqual(hello.protocolVersion, "1")
    }

    /// 新字段编码后可回读；nil 时不产生该键（向后兼容旧手机的 JSONDecoder 无影响）。
    func testMacResumeHelloEndpointRoundTrip() throws {
        var hello = MobilePairingHandshake.MacResumeHello(
            protocolVersion: "1", macPublicKey: Data([0x01]), macNonce: Data([0x02]))
        hello.tailnetEndpoint = "100.114.69.20:57147"
        let data = try JSONEncoder().encode(hello)
        let decoded = try JSONDecoder().decode(
            MobilePairingHandshake.MacResumeHello.self, from: data)
        XCTAssertEqual(decoded.tailnetEndpoint, "100.114.69.20:57147")

        hello.tailnetEndpoint = nil
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(hello)) as! [String: Any]
        XCTAssertFalse(object.keys.contains("tailnetEndpoint"),
                       "nil 可选字段不应出现在编码产物里（synthesize Encodable 用 encodeIfPresent）")
    }

    /// 旧版凭据 JSON（M1 配对产物，4 个键）必须解码成功且 tailnetEndpoint 为 nil——
    /// 这是已装机手机升级 app 后 Keychain 数据继续可读的保证。
    func testCompanionCredentialsLegacyJSONDecodesWithNilEndpoint() throws {
        let legacy = """
        {"deviceID":"11111111-2222-3333-4444-555555555555",
         "macPublicKey":"AAEC",
         "macFingerprint":"abcd",
         "deviceName":"iPhone"}
        """
        let credentials = try JSONDecoder().decode(
            CompanionPairingCredentials.self, from: Data(legacy.utf8))
        XCTAssertNil(credentials.tailnetEndpoint)
        XCTAssertEqual(credentials.deviceName, "iPhone")
    }

    /// 新凭据字段编解码回读；Keychain 载荷即此 JSON。
    func testCompanionCredentialsEndpointRoundTrip() throws {
        var credentials = CompanionPairingCredentials(
            deviceID: UUID(), macPublicKey: Data([0x01]),
            macFingerprint: "abcd", deviceName: "iPhone")
        credentials.tailnetEndpoint = "100.114.69.20:57147"
        let data = try JSONEncoder().encode(credentials)
        let decoded = try JSONDecoder().decode(CompanionPairingCredentials.self, from: data)
        XCTAssertEqual(decoded.tailnetEndpoint, "100.114.69.20:57147")
    }

    /// 隧道端口常量与同网端口并列且不同值——两端一致靠协议层单一声明。
    func testTunnelPortConstantIsDistinctFromLANPort() {
        XCTAssertEqual(MobilePairingCrypto.tunnelListenerPort, 57147)
        XCTAssertEqual(MobilePairingCrypto.listenerPort, 57146)
        XCTAssertNotEqual(MobilePairingCrypto.tunnelListenerPort, MobilePairingCrypto.listenerPort)
    }
}
