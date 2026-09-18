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
            operation: .requestTaskProposal,
            requestID: UUID(),
            toolID: nil,
            taskKind: "swiftPackageTests",
            projectScopeID: UUID(),
            taskIntentID: nil)
        let json = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        // M2b：任务引用三键（taskKind/projectScopeID/taskIntentID）之外，
        // 任何新增字段（command/path/param/env）都会让这个集合扩大而失败。
        // nil 的 Optional 键不进编码产物（JSONEncoder 默认行为）——集合
        // 即"本请求实际下发的全部键"。
        XCTAssertEqual(Set(object.keys), Set([
            "operation", "requestID",
            "taskKind", "projectScopeID"]))
    }

    /// 旧载荷（M1/M2a 三字段）仍可解码——decodeIfPresent 语义（恢复兼容红线）。
    func testRequestDecodesLegacyThreeFieldPayload() throws {
        let legacyJSON = """
        {"operation":"listTools","requestID":"\(UUID().uuidString)","toolID":null}
        """
        let decoded = try JSONDecoder().decode(MobilePairingRequest.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(decoded.operation, .listTools)
        XCTAssertNil(decoded.taskKind)
        XCTAssertNil(decoded.projectScopeID)
        XCTAssertNil(decoded.taskIntentID)
    }

    /// taskKind 是白名单枚举引用——不是自由命令通道。锁住合法字符集。
    func testRequestTaskKindIsWhitelistedReference() throws {
        let request = MobilePairingRequest(
            operation: .requestTaskProposal,
            requestID: UUID(),
            toolID: nil,
            taskKind: "swiftPackageTests",
            projectScopeID: UUID(),
            taskIntentID: nil)
        let json = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        let kind = try XCTUnwrap(object["taskKind"] as? String)
        // FixedTaskCatalog 全部 kind 均为纯小写字母驼峰标识符（无空格/元字符/
        // shell 语法）——正则锁死，防 taskKind 变成隐藏命令通道。
        XCTAssertTrue(kind.range(of: "^[a-zA-Z][a-zA-Z0-9]{0,63}$", options: .regularExpression) != nil,
                      "taskKind 必须是白名单标识符形态，实际：\(kind)")
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
        // §3.4 的 8 个基础 case + M4 两个流操作固定——新增操作必须先改设计文档与本测试。
        XCTAssertEqual(
            Set(PairedDeviceOperation.allCases.map(\.rawValue)),
            Set(["listTools", "requestLaunch", "listScopes", "listFixedTasks",
                 "requestTaskProposal", "getTaskStatus", "cancelTask", "heartbeat",
                 "openTaskStream", "closeTaskStream"]))
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

    // MARK: - 会话复用（§3.3.1）

    func testResumeKeyDerivesSameKeyOnBothSides() throws {
        let mac = MobilePairingIdentity.generate()
        let phone = MobilePairingIdentity.generate()
        let macNonce = MobilePairingCrypto.generateNonce()
        let phoneNonce = MobilePairingCrypto.generateNonce()

        let macSide = try mac.resumeSessionKey(
            peerPublicKeyData: phone.publicKeyData(), macNonce: macNonce, phoneNonce: phoneNonce)
        let phoneSide = try phone.resumeSessionKey(
            peerPublicKeyData: mac.publicKeyData(), macNonce: macNonce, phoneNonce: phoneNonce)

        XCTAssertEqual(Self.keyData(macSide), Self.keyData(phoneSide))
    }

    func testResumeKeyDiffersFromPairingKey() throws {
        // info 域不同：同一密钥材料永不跨协议复用。
        let mac = MobilePairingIdentity.generate()
        let phone = MobilePairingIdentity.generate()
        let macNonce = MobilePairingCrypto.generateNonce()
        let phoneNonce = MobilePairingCrypto.generateNonce()
        let resume = try mac.resumeSessionKey(
            peerPublicKeyData: phone.publicKeyData(), macNonce: macNonce, phoneNonce: phoneNonce)
        let pairing = try mac.sessionKey(
            peerPublicKeyData: phone.publicKeyData(),
            pairingCode: "042913",
            macNonce: macNonce,
            phoneNonce: phoneNonce)
        XCTAssertNotEqual(Self.keyData(resume), Self.keyData(pairing))
    }

    func testIncomingHelloDispatchPairingVsResume() throws {
        let phoneKey = try MobilePairingIdentity.generate().publicKeyData()
        let pairing = MobilePairingHandshake.PhoneHello(
            protocolVersion: MobilePairingHandshake.currentProtocolVersion,
            phonePublicKey: phoneKey,
            phoneNonce: MobilePairingCrypto.generateNonce(),
            pairingCode: "042913",
            deviceName: "iPhone")
        let resume = MobilePairingHandshake.PhoneResumeHello(
            protocolVersion: MobilePairingHandshake.currentProtocolVersion,
            deviceID: UUID(),
            phonePublicKey: phoneKey,
            phoneNonce: MobilePairingCrypto.generateNonce())

        guard case .pairing(let decodedPairing) = MobilePairingHandshake.decodeIncomingHello(
            from: try JSONEncoder().encode(pairing)) else {
            return XCTFail("pairing hello 应被分发到 .pairing")
        }
        XCTAssertEqual(decodedPairing, pairing)
        guard case .resume(let decodedResume) = MobilePairingHandshake.decodeIncomingHello(
            from: try JSONEncoder().encode(resume)) else {
            return XCTFail("resume hello 应被分发到 .resume")
        }
        XCTAssertEqual(decodedResume, resume)
        XCTAssertNil(MobilePairingHandshake.decodeIncomingHello(from: Data("{}".utf8)))
    }

    func testAcceptResumeValidation() throws {
        // 验证 deriveResumeSessionKey 的纯计算部分。撤销/换公钥的拒绝是 Mac 端
        // MobilePairingService.handleResumeHello 在调用此方法前做的——本测试只负责
        // "纯计算"分支：成功 + 版本不符拒绝。
        let mac = MobilePairingIdentity.generate()
        let phone = MobilePairingIdentity.generate()
        let phonePub = try phone.publicKeyData()
        let hello = MobilePairingHandshake.PhoneResumeHello(
            protocolVersion: MobilePairingHandshake.currentProtocolVersion,
            deviceID: UUID(),
            phonePublicKey: phonePub,
            phoneNonce: MobilePairingCrypto.generateNonce())

        // 正常路径：返回 32 字节会话密钥。
        let keyData = try MobilePairingHandshake.deriveResumeSessionKey(
            hello, identity: mac, macNonce: MobilePairingCrypto.generateNonce())
        XCTAssertEqual(keyData.count, 32)

        // 版本不符 → 拒绝。
        XCTAssertThrowsError(try MobilePairingHandshake.deriveResumeSessionKey(
            MobilePairingHandshake.PhoneResumeHello(
                protocolVersion: "termipad-m1-resume-v9",
                deviceID: hello.deviceID,
                phonePublicKey: phonePub,
                phoneNonce: MobilePairingCrypto.generateNonce()),
            identity: mac, macNonce: MobilePairingCrypto.generateNonce()))
    }

    // MARK: - M2b 任务会话回传契约（docs/m2b-remote-task-console-design.md §3.2）

    /// 信封回环：五个新回传结构经 AEAD 加密后手机侧可原样解回。
    func testTaskConsoleEnvelopeRoundTrip() throws {
        let key = try makeSessionKey()

        let scopes = [MobileScopeSummary(id: UUID(), displayName: "TermiPad")]
        XCTAssertEqual(try MobilePairingEnvelope.openScopeSummaries(
            try MobilePairingEnvelope.seal(scopes, using: key), using: key), scopes)

        let tasks = [MobileFixedTaskSummary(
            kind: "swiftPackageTests",
            purpose: "运行项目的 Swift Package 单元测试。",
            commandPreview: "swift test")]
        XCTAssertEqual(try MobilePairingEnvelope.openFixedTaskSummaries(
            try MobilePairingEnvelope.seal(tasks, using: key), using: key), tasks)

        let entries = [
            MobileSessionEntry(
                id: UUID(), title: "swift test", kind: .fixedTask,
                executionState: TaskExecutionState.running.rawValue,
                exitCode: nil, startedAt: Date(), finishedAt: nil, outputSnippet: nil),
            MobileSessionEntry(
                id: UUID(), title: "构建", kind: .toolLaunch,
                executionState: "launched",
                exitCode: nil, startedAt: Date(), finishedAt: nil)
        ]
        XCTAssertEqual(try MobilePairingEnvelope.openSessionEntries(
            try MobilePairingEnvelope.seal(entries, using: key), using: key), entries)

        let accepted = MobileTaskProposalResponse(
            status: .accepted, reason: nil, taskIntentID: UUID())
        XCTAssertEqual(try MobilePairingEnvelope.openTaskProposalResponse(
            try MobilePairingEnvelope.seal(accepted, using: key), using: key), accepted)

        let rejected = MobileTaskProposalResponse(
            status: .rejected, reason: "锁屏期间拒绝远程任务", taskIntentID: nil)
        XCTAssertEqual(try MobilePairingEnvelope.openTaskProposalResponse(
            try MobilePairingEnvelope.seal(rejected, using: key), using: key), rejected)
    }

    /// 会话条目编码 key 集合锁：outputSnippet 之外不得新增内容性字段。
    func testSessionEntryEncodesOnlyWhitelistedKeys() throws {
        let entry = MobileSessionEntry(
            id: UUID(), title: "swift test", kind: .fixedTask,
            executionState: TaskExecutionState.succeeded.rawValue,
            exitCode: 0, startedAt: Date(), finishedAt: Date(),
            outputSnippet: "全部通过")
        let json = try JSONEncoder().encode(entry)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set([
            "id", "title", "kind", "executionState", "exitCode",
            "startedAt", "finishedAt", "outputSnippet"]))
    }

    /// 工具启动条目无 outputSnippet 键——终端交接路径永无输出回传（编译层
    /// Optional 默认 nil 不进编码产物，与 tailnetEndpoint 同款纪律）。
    func testToolLaunchEntryOmitsOutputSnippet() throws {
        let entry = MobileSessionEntry(
            id: UUID(), title: "构建", kind: .toolLaunch,
            executionState: "launched",
            exitCode: nil, startedAt: Date(), finishedAt: nil)
        let json = try JSONEncoder().encode(entry)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        XCTAssertNil(object["outputSnippet"])
    }

    /// 旧回传结构的编码产物不含任务引用三键——M1/M2a 手机收到的帧不受影响。
    func testLegacyRequestKeySetUnchanged() throws {
        let request = MobilePairingRequest(
            operation: .listTools, requestID: UUID(), toolID: UUID())
        let json = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        // toolID 非 nil 时恰 3 键；任务引用三键均 nil 不进编码产物。
        XCTAssertEqual(Set(object.keys), Set(["operation", "requestID", "toolID"]))
    }
}
