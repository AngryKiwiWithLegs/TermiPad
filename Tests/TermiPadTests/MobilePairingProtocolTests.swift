import XCTest
import CryptoKit
@testable import TermiPad

/// M1 pairing protocol layer contract tests: data minimization (encoded key set), AEAD envelope,
/// operation allowlist, handshake state machine. All pure logic, zero real network.
final class MobilePairingProtocolTests: XCTestCase {
    private static func keyData(_ key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }

    /// Build a pair of negotiated session keys (from the Mac's perspective).
    private func makeSessionKey() throws -> SymmetricKey {
        try MobilePairingIdentity.generate().sessionKey(
            peerPublicKeyData: MobilePairingIdentity.generate().publicKeyData(),
            pairingCode: "042913",
            macNonce: MobilePairingCrypto.generateNonce(),
            phoneNonce: MobilePairingCrypto.generateNonce())
    }

    // MARK: - Data minimization contract

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
        // M2b: beyond the three task reference keys (taskKind/projectScopeID/taskIntentID),
        // any added field (command/path/param/env) would enlarge this set and fail.
        // nil Optional keys do not enter the encoded output (JSONEncoder's default behavior) — the set
        // is "every key this request actually sends".
        XCTAssertEqual(Set(object.keys), Set([
            "operation", "requestID",
            "taskKind", "projectScopeID"]))
    }

    /// Old payloads (the three M1/M2a fields) still decode — decodeIfPresent semantics (restore compatibility red line).
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

    /// taskKind is an allowlisted enum reference — not a free-form command channel. Lock down the legal character set.
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
        // Every FixedTaskCatalog kind is a plain camelCase identifier of lowercase-initial letters (no spaces / metacharacters /
        // shell syntax) — locked down by regex so taskKind cannot become a hidden command channel.
        XCTAssertTrue(kind.range(of: "^[a-zA-Z][a-zA-Z0-9]{0,63}$", options: .regularExpression) != nil,
                      "taskKind must have the shape of an allowlisted identifier, actual: \(kind)")
    }

    func testToolSummaryEncodesOnlyWhitelistedKeys() throws {
        let summary = MobileToolSummary(
            id: UUID(),
            displayName: "Run Tests",
            displayDescription: "Run swift test",
            iconSymbolName: "hammer")
        let json = try JSONEncoder().encode([summary])
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: json) as? [[String: Any]])
        let summaryObject = try XCTUnwrap(object.first)
        // Any added field (command/path/argument) would enlarge this set and fail.
        XCTAssertEqual(Set(summaryObject.keys), Set(["id", "displayName", "displayDescription", "iconSymbolName"]))
    }

    // MARK: - Operation allowlist

    func testOperationWhitelistMatchesDesignDoc() {
        // The 8 base cases of §3.4 + the two M4 stream operations are fixed — a new operation must first change the design doc and this test.
        XCTAssertEqual(
            Set(PairedDeviceOperation.allCases.map(\.rawValue)),
            Set(["listTools", "requestLaunch", "listScopes", "listFixedTasks",
                 "requestTaskProposal", "getTaskStatus", "cancelTask", "heartbeat",
                 "openTaskStream", "closeTaskStream", "respondInteraction"]))
    }

    // MARK: - AEAD envelope

    func testEnvelopeRoundTripBothDirections() throws {
        let key = try makeSessionKey()
        let request = MobilePairingRequest(operation: .listTools, requestID: UUID(), toolID: nil)
        let sealed = try MobilePairingEnvelope.seal(request, using: key)
        XCTAssertEqual(try MobilePairingEnvelope.openRequest(sealed, using: key), request)

        let summaries = [
            MobileToolSummary(id: UUID(), displayName: "Build", displayDescription: "", iconSymbolName: nil)
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

    // MARK: - Bonjour contract

    func testBonjourServiceTypeIsPinned() {
        // The service type is fixed and not configurable at runtime — changing it here must change the guard as well.
        XCTAssertEqual(MobilePairingCrypto.bonjourServiceType, "_termipad-m1._tcp")
        XCTAssertEqual(MobilePairingCrypto.bonjourServiceName, "TermiPad")
    }

    func testBonjourTXTOnlyCarriesVersionAndFingerprintPrefix() {
        let txt = MobilePairingCrypto.bonjourTXTRecord(fingerprint: String(repeating: "AB", count: 40))
        XCTAssertEqual(Set(txt.keys), Set(["v", "fp"]))
        XCTAssertEqual(txt["v"], MobilePairingCrypto.protocolVersion)
        XCTAssertEqual(txt["fp"]?.count, 16)
    }

    // MARK: - Handshake state machine

    func testHandshakeRoundTripDerivesSameKeyOnBothSides() throws {
        let mac = MobilePairingIdentity.generate()
        let phone = MobilePairingIdentity.generate()
        let macNonce = MobilePairingCrypto.generateNonce()
        let phoneNonce = MobilePairingCrypto.generateNonce()
        let pairingCode = MobilePairingCrypto.generatePairingCode()

        let macHello = try MobilePairingHandshake.makeMacHello(identity: mac, macNonce: macNonce)
        XCTAssertEqual(macHello.fingerprint.count, 79, "16 groups of 4 hex + 15 separators")

        let phoneHello = MobilePairingHandshake.PhoneHello(
            protocolVersion: MobilePairingHandshake.currentProtocolVersion,
            phonePublicKey: try phone.publicKeyData(),
            phoneNonce: phoneNonce,
            pairingCode: pairingCode,
            deviceName: "iPhone 16 Pro")
        let accepted = try MobilePairingHandshake.acceptPhoneHello(phoneHello, identity: mac, macNonce: macNonce)

        // The phone derives it independently with the same formula; the keys must match.
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

    // MARK: - Session resume (§3.3.1)

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
        // Different info domains: the same key material is never reused across protocols.
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
            return XCTFail("the pairing hello should be dispatched to .pairing")
        }
        XCTAssertEqual(decodedPairing, pairing)
        guard case .resume(let decodedResume) = MobilePairingHandshake.decodeIncomingHello(
            from: try JSONEncoder().encode(resume)) else {
            return XCTFail("the resume hello should be dispatched to .resume")
        }
        XCTAssertEqual(decodedResume, resume)
        XCTAssertNil(MobilePairingHandshake.decodeIncomingHello(from: Data("{}".utf8)))
    }

    func testAcceptResumeValidation() throws {
        // Verify the pure computation part of deriveResumeSessionKey. Rejecting revoked devices / changed public keys is what the Mac's
        // MobilePairingService.handleResumeHello does before calling this method — this test only covers
        // the "pure computation" branch: success + rejection on version mismatch.
        let mac = MobilePairingIdentity.generate()
        let phone = MobilePairingIdentity.generate()
        let phonePub = try phone.publicKeyData()
        let hello = MobilePairingHandshake.PhoneResumeHello(
            protocolVersion: MobilePairingHandshake.currentProtocolVersion,
            deviceID: UUID(),
            phonePublicKey: phonePub,
            phoneNonce: MobilePairingCrypto.generateNonce())

        // Normal path: returns a 32-byte session key.
        let keyData = try MobilePairingHandshake.deriveResumeSessionKey(
            hello, identity: mac, macNonce: MobilePairingCrypto.generateNonce())
        XCTAssertEqual(keyData.count, 32)

        // Version mismatch → rejected.
        XCTAssertThrowsError(try MobilePairingHandshake.deriveResumeSessionKey(
            MobilePairingHandshake.PhoneResumeHello(
                protocolVersion: "termipad-m1-resume-v9",
                deviceID: hello.deviceID,
                phonePublicKey: phonePub,
                phoneNonce: MobilePairingCrypto.generateNonce()),
            identity: mac, macNonce: MobilePairingCrypto.generateNonce()))
    }

    // MARK: - M2b task session return contract (docs/m2b-remote-task-console-design.md §3.2)

    /// Envelope round-trip: after AEAD encryption the five new return structures decode back unchanged on the phone side.
    func testTaskConsoleEnvelopeRoundTrip() throws {
        let key = try makeSessionKey()

        let scopes = [MobileScopeSummary(id: UUID(), displayName: "TermiPad")]
        XCTAssertEqual(try MobilePairingEnvelope.openScopeSummaries(
            try MobilePairingEnvelope.seal(scopes, using: key), using: key), scopes)

        let tasks = [MobileFixedTaskSummary(
            kind: "swiftPackageTests",
            purpose: "Run the project's Swift Package unit tests.",
            commandPreview: "swift test")]
        XCTAssertEqual(try MobilePairingEnvelope.openFixedTaskSummaries(
            try MobilePairingEnvelope.seal(tasks, using: key), using: key), tasks)

        let entries = [
            MobileSessionEntry(
                id: UUID(), title: "swift test", kind: .fixedTask,
                executionState: TaskExecutionState.running.rawValue,
                exitCode: nil, startedAt: Date(), finishedAt: nil, outputSnippet: nil),
            MobileSessionEntry(
                id: UUID(), title: "Build", kind: .toolLaunch,
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
            status: .rejected, reason: "Remote tasks are rejected while locked", taskIntentID: nil)
        XCTAssertEqual(try MobilePairingEnvelope.openTaskProposalResponse(
            try MobilePairingEnvelope.seal(rejected, using: key), using: key), rejected)
    }

    /// Lock on the encoded key set of session entries: no content-bearing field other than outputSnippet may be added.
    func testSessionEntryEncodesOnlyWhitelistedKeys() throws {
        let entry = MobileSessionEntry(
            id: UUID(), title: "swift test", kind: .fixedTask,
            executionState: TaskExecutionState.succeeded.rawValue,
            exitCode: 0, startedAt: Date(), finishedAt: Date(),
            outputSnippet: "All passed")
        let json = try JSONEncoder().encode(entry)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set([
            "id", "title", "kind", "executionState", "exitCode",
            "startedAt", "finishedAt", "outputSnippet"]))
    }

    /// Tool launch entries have no outputSnippet key — the terminal handoff path never returns output (at compile level
    /// an Optional defaulting to nil does not enter the encoded output, the same discipline as tailnetEndpoint).
    func testToolLaunchEntryOmitsOutputSnippet() throws {
        let entry = MobileSessionEntry(
            id: UUID(), title: "Build", kind: .toolLaunch,
            executionState: "launched",
            exitCode: nil, startedAt: Date(), finishedAt: nil)
        let json = try JSONEncoder().encode(entry)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        XCTAssertNil(object["outputSnippet"])
    }

    /// The encoded output of the old return structures does not contain the three task reference keys — frames received by M1/M2a phones are unaffected.
    func testLegacyRequestKeySetUnchanged() throws {
        let request = MobilePairingRequest(
            operation: .listTools, requestID: UUID(), toolID: UUID())
        let json = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        // Exactly 3 keys when toolID is non-nil; the three task reference keys are all nil and do not enter the encoded output.
        XCTAssertEqual(Set(object.keys), Set(["operation", "requestID", "toolID"]))
    }
}
