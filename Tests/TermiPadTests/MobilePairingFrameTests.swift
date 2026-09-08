import XCTest
@testable import TermiPad

/// M1 帧层契约测试：4 字节大端长度前缀、64KB 上限、incomplete/invalid 分支。
/// 这是把"分包/粘包在 listenerQueue 里解"的网络层前置单测。
final class MobilePairingFrameTests: XCTestCase {
    func testEncodeThenDecodeRoundTrips() {
        let payload = Data(repeating: 0xAB, count: 100)
        let encoded = MobilePairingFrame.encode(payload)
        XCTAssertEqual(encoded.count, 4 + payload.count)
        XCTAssertEqual(Array(encoded.prefix(4)), [0x00, 0x00, 0x00, 0x64])
        XCTAssertEqual(MobilePairingFrame.decodeOne(from: encoded), .message(payload, remainder: Data()))
    }

    func testDecodeKeepsRemainderForStreaming() {
        let first = Data(repeating: 0x01, count: 10)
        let second = Data(repeating: 0x02, count: 20)
        let stream = MobilePairingFrame.encode(first) + MobilePairingFrame.encode(second)
        let outcome = MobilePairingFrame.decodeOne(from: stream)
        XCTAssertEqual(outcome, .message(first, remainder: MobilePairingFrame.encode(second)))
    }

    func testDecodeReturnsIncompleteForTruncatedFrames() {
        let encoded = MobilePairingFrame.encode(Data(count: 100))
        let truncated = encoded.prefix(10)
        XCTAssertEqual(MobilePairingFrame.decodeOne(from: Data(truncated)), .incomplete)
    }

    func testDecodeRejectsOversizedDeclaredLength() {
        var fake = Data([0x00, 0x10, 0x00, 0x00]) // 1 MB，远超 64 KB 上限
        fake.append(Data(count: 1))
        XCTAssertEqual(MobilePairingFrame.decodeOne(from: fake), .invalid)
    }

    func testEncodeEmptyPayloadIsFourHeaderBytes() {
        XCTAssertEqual(MobilePairingFrame.encode(Data()), Data([0, 0, 0, 0]))
        XCTAssertEqual(
            MobilePairingFrame.decodeOne(from: Data([0, 0, 0, 0])),
            .message(Data(), remainder: Data()))
    }

    func testEnvelopedAckRoundTripAcrossFrameBoundary() throws {
        let mac = MobilePairingIdentity.generate()
        let phone = MobilePairingIdentity.generate()
        let key = try mac.sessionKey(
            peerPublicKeyData: try phone.publicKeyData(),
            pairingCode: "042913",
            macNonce: MobilePairingCrypto.generateNonce(),
            phoneNonce: MobilePairingCrypto.generateNonce())
        let ack = MobilePairingAck(accepted: true, deviceID: UUID())
        let frame = MobilePairingFrame.encode(try MobilePairingEnvelope.seal(ack, using: key))
        let outcome = MobilePairingFrame.decodeOne(from: frame)
        let payload = try XCTUnwrap({
            if case .message(let data, _) = outcome { return data } else { return nil }
        }())
        XCTAssertEqual(try MobilePairingEnvelope.openAck(payload, using: key), ack)
    }
}
