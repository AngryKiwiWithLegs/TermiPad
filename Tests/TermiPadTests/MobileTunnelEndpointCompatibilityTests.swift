import XCTest
@testable import TermiPad

/// M2a protocol increment compatibility tests (docs/m2-secure-remote-session-design.md §4.1).
/// Restore compatibility red line: new fields must be Optional + old data must decode — this locks down the decoding
/// behavior of two old-version payloads, so no commit can break credential reads on phones already in the field.
final class MobileTunnelEndpointCompatibilityTests: XCTestCase {
    /// An old MacResumeHello JSON (M1, no tailnetEndpoint key) must decode successfully with a nil endpoint.
    func testMacResumeHelloWithoutEndpointDecodesFromLegacyJSON() throws {
        let legacy = """
        {"protocolVersion":"1","macPublicKey":"AAEC","macNonce":"AAEC"}
        """
        let hello = try JSONDecoder().decode(
            MobilePairingHandshake.MacResumeHello.self, from: Data(legacy.utf8))
        XCTAssertNil(hello.tailnetEndpoint)
        XCTAssertEqual(hello.protocolVersion, "1")
    }

    /// The new field reads back after encoding; when nil the key is not produced (no effect on old phones' JSONDecoder, backward compatible).
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
                       "a nil optional field should not appear in the encoded output (synthesized Encodable uses encodeIfPresent)")
    }

    /// An old credential JSON (the M1 pairing output, 4 keys) must decode successfully with a nil tailnetEndpoint —
    /// this guarantees that Keychain data stays readable after an installed phone upgrades the app.
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

    /// The new credential field round-trips through encode/decode; the Keychain payload is exactly this JSON.
    func testCompanionCredentialsEndpointRoundTrip() throws {
        var credentials = CompanionPairingCredentials(
            deviceID: UUID(), macPublicKey: Data([0x01]),
            macFingerprint: "abcd", deviceName: "iPhone")
        credentials.tailnetEndpoint = "100.114.69.20:57147"
        let data = try JSONEncoder().encode(credentials)
        let decoded = try JSONDecoder().decode(CompanionPairingCredentials.self, from: data)
        XCTAssertEqual(decoded.tailnetEndpoint, "100.114.69.20:57147")
    }

    /// The tunnel port constant sits next to the local-network port with a different value — both sides agree through the single declaration in the protocol layer.
    func testTunnelPortConstantIsDistinctFromLANPort() {
        XCTAssertEqual(MobilePairingCrypto.tunnelListenerPort, 57147)
        XCTAssertEqual(MobilePairingCrypto.listenerPort, 57146)
        XCTAssertNotEqual(MobilePairingCrypto.tunnelListenerPort, MobilePairingCrypto.listenerPort)
    }
}
