import XCTest
@testable import TermiPad

/// Regression tests for defects found in the 2026-10 code review. Each test fails on the code as it was before the fix.

// MARK: - Task output stream

@MainActor
final class TaskOutputStreamRegressionTests: XCTestCase {
    private func makeLine(_ index: Int) -> String {
        "output line \(index) of the task\n"
    }

    /// Feeds output in pieces of roughly 4 KB (below the 8 KB chunk limit, so each piece is pushed unchanged)
    /// until at least `byteCount` bytes were sent. Returns everything that was sent.
    private func feedOutput(to service: TaskOutputStreamService, taskID: UUID, atLeast byteCount: Int) -> String {
        var sent = ""
        var lineIndex = 0
        while sent.utf8.count < byteCount {
            var piece = ""
            while piece.utf8.count < 4_000 {
                piece += makeLine(lineIndex)
                lineIndex += 1
            }
            service.dispatchOutput(taskID: taskID, rawText: piece)
            sent += piece
        }
        return sent
    }

    /// Once a task had produced more than the 64 KB buffer limit, subscribers stopped receiving anything.
    func testOutputKeepsFlowingPastTheBufferLimit() throws {
        let service = TaskOutputStreamService()
        let taskID = UUID()
        let connectionID = UUID()
        var pushed: [MobileStreamChunk] = []
        service.registerSink(connectionID) { pushed.append($0) }
        _ = service.subscribe(connectionID: connectionID, taskID: taskID, resumeOffset: nil) { pushed.append($0) }

        var sent = feedOutput(
            to: service, taskID: taskID, atLeast: TaskOutputStreamService.bufferByteLimit + 40_000)
        service.dispatchOutput(taskID: taskID, rawText: "FINAL MARKER\n")
        sent += "FINAL MARKER\n"

        XCTAssertTrue(pushed.contains { $0.text.contains("FINAL MARKER") },
                      "Output after the first 64 KB must still reach a subscriber")
        XCTAssertEqual(pushed.map(\.text).joined(), sent,
                       "A subscriber that keeps up must receive every byte exactly once")
        let last = try XCTUnwrap(pushed.last)
        XCTAssertEqual(last.offset + last.text.utf8.count, sent.utf8.count,
                       "Offsets count from the start of the task's output, also after the buffer dropped its head")
    }

    func testResumeCursorStaysValidAfterTheBufferDroppedItsHead() {
        let service = TaskOutputStreamService()
        let taskID = UUID()
        var sent = feedOutput(
            to: service, taskID: taskID, atLeast: TaskOutputStreamService.bufferByteLimit + 20_000)
        let tail = "tail after reconnect\n"
        service.dispatchOutput(taskID: taskID, rawText: tail)
        sent += tail

        // A phone that reconnects having consumed everything except the tail gets exactly the tail.
        let connectionID = UUID()
        var pushed: [MobileStreamChunk] = []
        service.registerSink(connectionID) { pushed.append($0) }
        let cursor = service.subscribe(
            connectionID: connectionID, taskID: taskID,
            resumeOffset: sent.utf8.count - tail.utf8.count) { pushed.append($0) }

        XCTAssertEqual(cursor, sent.utf8.count)
        XCTAssertEqual(pushed.map(\.text).joined(), tail)
        XCTAssertEqual(pushed.first?.offset, sent.utf8.count - tail.utf8.count)
    }

    /// A cursor older than what the buffer still holds restarts at the oldest retained output instead of failing.
    func testResumeCursorOlderThanTheBufferStartsAtTheOldestRetainedOutput() throws {
        let service = TaskOutputStreamService()
        let taskID = UUID()
        let sent = feedOutput(
            to: service, taskID: taskID, atLeast: TaskOutputStreamService.bufferByteLimit * 2)
        let lastLine = try XCTUnwrap(sent.split(separator: "\n").last)
        let connectionID = UUID()
        var pushed: [MobileStreamChunk] = []
        service.registerSink(connectionID) { pushed.append($0) }
        let cursor = service.subscribe(
            connectionID: connectionID, taskID: taskID, resumeOffset: 10) { pushed.append($0) }

        XCTAssertEqual(cursor, sent.utf8.count)
        let firstChunk = try XCTUnwrap(pushed.first)
        XCTAssertEqual(firstChunk.offset, sent.utf8.count - TaskOutputStreamService.bufferByteLimit,
                       "The replay starts at the oldest output the buffer still holds")
        XCTAssertTrue(pushed.map(\.text).joined().contains(lastLine))
    }

    /// The original implementation, kept as the reference: walk the characters until `offset` bytes are consumed.
    private func referenceSubstring(fromUTF8Offset offset: Int, of text: String) -> String {
        guard offset > 0 else { return text }
        var byteIndex = text.startIndex
        var consumed = 0
        while consumed < offset, byteIndex < text.endIndex {
            let next = text.index(after: byteIndex)
            consumed += text[byteIndex..<next].utf8.count
            byteIndex = next
        }
        return String(text[byteIndex...])
    }

    func testSubstringFromByteOffsetMatchesTheCharacterWalkAtEveryOffset() {
        let samples = [
            "",
            "plain ascii output\nsecond line\n",
            "windows line endings\r\nsecond\r\n\r\n",
            "中文输出：构建完成。\n第二行\n",
            "accents: cafe\u{301} na\u{EF}ve \u{1F1E8}\u{1F1E6}\u{1F1EF}\u{1F1F5}\n",
            "emoji 👩‍👩‍👧‍👦 family, 👍🏽 skin tone, 🏳️‍🌈 flag\n",
            "mixed ascii 和 中文 with tabs\tand a trailing accent e\u{301}",
            String(repeating: "é", count: 40) + "\n" + String(repeating: "x", count: 40)
        ]
        for sample in samples {
            for offset in -1...(sample.utf8.count + 2) {
                XCTAssertEqual(
                    TaskOutputStreamService.substring(fromUTF8Offset: offset, of: sample),
                    referenceSubstring(fromUTF8Offset: offset, of: sample),
                    "offset \(offset) in \(sample.debugDescription)")
            }
        }
    }

    /// An interaction request goes only to the outlet of a connection subscribed to that task, and a removed
    /// connection receives nothing further.
    func testInteractionOutletIsScopedToItsConnectionAndReleasedWithIt() {
        let service = TaskOutputStreamService()
        let taskID = UUID()
        let otherTaskID = UUID()
        let subscribed = UUID()
        let subscribedElsewhere = UUID()
        var received: [UUID: [MobileStreamInteraction]] = [:]
        for (connectionID, task) in [(subscribed, taskID), (subscribedElsewhere, otherTaskID)] {
            service.registerSink(connectionID) { _ in }
            service.registerInteractionSink(connectionID) { received[connectionID, default: []].append($0) }
            _ = service.subscribe(connectionID: connectionID, taskID: task, resumeOffset: nil) { _ in }
        }

        service.dispatchInteraction(taskID: taskID, prompt: "Continue?", options: ["yes", "no"])
        XCTAssertEqual(received[subscribed]?.map(\.prompt), ["Continue?"])
        XCTAssertNil(received[subscribedElsewhere])

        service.removeSink(subscribed)
        service.dispatchInteraction(taskID: taskID, prompt: "Again?", options: ["yes", "no"])
        XCTAssertEqual(received[subscribed]?.count, 1, "A connection that ended must not receive further requests")
        XCTAssertFalse(service.hasActiveSubscribers(taskID: taskID))
    }
}

// MARK: - Task output capture

final class TaskOutputCaptureDecodingTests: XCTestCase {
    /// Reads from the capture pipe end at arbitrary bytes. A read that ended inside a multi-byte character used
    /// to fail to decode, and the whole read was dropped.
    func testOutputSplitAtAnyByteIsReassembledWithoutLoss() {
        let original = "构建完成 ✅ café 👩‍👩‍👧‍👦 done\n第二行: ok\n"
        let bytes = [UInt8](original.utf8)
        for readSize in 1...7 {
            var carried = Data()
            var decoded = ""
            var position = 0
            while position < bytes.count {
                let end = min(position + readSize, bytes.count)
                carried.append(contentsOf: bytes[position..<end])
                position = end
                let complete = TaskExecutionCoordinator.takeCompleteUTF8Prefix(from: &carried)
                XCTAssertLessThanOrEqual(carried.count, 3, "At most one unfinished character is kept back")
                let text = String(data: complete, encoding: .utf8)
                XCTAssertNotNil(text, "Every returned piece must decode on its own (read size \(readSize))")
                decoded += text ?? ""
            }
            XCTAssertTrue(carried.isEmpty)
            XCTAssertEqual(decoded, original, "read size \(readSize)")
        }
    }

    func testCompleteAndInvalidBytesPassThroughUnchanged() {
        var ascii = Data("plain output\n".utf8)
        XCTAssertEqual(TaskExecutionCoordinator.takeCompleteUTF8Prefix(from: &ascii), Data("plain output\n".utf8))
        XCTAssertTrue(ascii.isEmpty)

        // Bytes that can never become valid text are not held back: they are returned as they came.
        var invalid = Data([0x61, 0xFF, 0x80, 0x80, 0x80])
        XCTAssertEqual(TaskExecutionCoordinator.takeCompleteUTF8Prefix(from: &invalid), Data([0x61, 0xFF, 0x80, 0x80, 0x80]))
        XCTAssertTrue(invalid.isEmpty)

        var empty = Data()
        XCTAssertTrue(TaskExecutionCoordinator.takeCompleteUTF8Prefix(from: &empty).isEmpty)
    }
}

// MARK: - Paired device store

final class PairedDeviceStoreRegressionTests: XCTestCase {
    /// In-memory backend that counts reads, standing in for Keychain items (each real read can raise a prompt).
    private final class CountingSecureStore: MobileSecureKeyValueStore, @unchecked Sendable {
        private var values: [String: String] = [:]
        private(set) var readCount = 0
        private let lock = NSLock()

        func string(for account: String) throws -> String? {
            lock.lock()
            defer { lock.unlock() }
            readCount += 1
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

        func resetReadCount() {
            lock.lock()
            readCount = 0
            lock.unlock()
        }
    }

    private func key(_ byte: UInt8) -> Data {
        Data(repeating: byte, count: 32)
    }

    func testFindReadsOnlyTheIndexAndTheRequestedRecord() throws {
        let store = CountingSecureStore()
        let first = try PairedDeviceStore.add(displayName: "iPhone", publicKeyData: key(1), store: store)
        _ = try PairedDeviceStore.add(displayName: "iPad", publicKeyData: key(2), store: store)
        _ = try PairedDeviceStore.add(displayName: "Old iPhone", publicKeyData: key(3), store: store)

        store.resetReadCount()
        XCTAssertEqual(PairedDeviceStore.find(id: first.id, store: store)?.displayName, "iPhone")
        XCTAssertEqual(store.readCount, 2, "One read for the index and one for the record, however many devices are paired")

        XCTAssertNil(PairedDeviceStore.find(id: UUID(), store: store))
    }

    func testFindIgnoresARecordThatIsNoLongerIndexed() throws {
        let store = CountingSecureStore()
        let device = try PairedDeviceStore.add(displayName: "iPhone", publicKeyData: key(1), store: store)
        // The record item is still stored, but the index no longer lists it — exactly what list() reports.
        try store.save("[]", for: PairedDeviceStore.indexAccount)
        XCTAssertTrue(PairedDeviceStore.list(store: store).isEmpty)
        XCTAssertNil(PairedDeviceStore.find(id: device.id, store: store))
    }

    func testAddDropsRevokedAndRepairedRecordsAndKeepsTheOthers() throws {
        let store = CountingSecureStore()
        let kept = try PairedDeviceStore.add(displayName: "iPad", publicKeyData: key(1), store: store)
        let revoked = try PairedDeviceStore.add(displayName: "Lost iPhone", publicKeyData: key(2), store: store)
        let repaired = try PairedDeviceStore.add(displayName: "iPhone", publicKeyData: key(3), store: store)
        try PairedDeviceStore.revoke(id: revoked.id, store: store)

        store.resetReadCount()
        let replacement = try PairedDeviceStore.add(displayName: "iPhone (new)", publicKeyData: key(3), store: store)
        XCTAssertEqual(store.readCount, 4, "One pass: the index plus the three existing records")

        XCTAssertEqual(PairedDeviceStore.list(store: store).map(\.id), [kept.id, replacement.id])
        XCTAssertNil(PairedDeviceStore.find(id: revoked.id, store: store))
        XCTAssertNil(PairedDeviceStore.find(id: repaired.id, store: store))
        XCTAssertNil(try store.string(for: PairedDeviceStore.deviceAccount(revoked.id)), "The revoked item is removed")
        XCTAssertNil(try store.string(for: PairedDeviceStore.deviceAccount(repaired.id)), "The re-paired device's old item is removed")
    }
}

// MARK: - Name matching for descriptions and icons

final class KnownToolMatchingRegressionTests: XCTestCase {
    /// "lazygit-gh" contains both "lazygit" and "gh". The match used to depend on dictionary order, which
    /// changes from launch to launch; the longest key now always wins.
    func testDescriptionForANameContainingSeveralKnownToolsIsStable() {
        let tool = TerminalTool(
            name: "lazygit-gh",
            executablePath: "/usr/local/bin/lazygit-gh",
            commandTemplate: "lazygit-gh")
        for _ in 0..<20 {
            let content = ToolDescriptionPresentation.hoverContent(for: tool, language: .english)
            XCTAssertEqual(
                content.purpose,
                "Inspect changes and manage Git commits and branches through an interactive interface.")
        }
    }

    func testIconForANameContainingSeveralKnownToolsIsStable() {
        // "gitui-helper" contains "gitui" and "git"; "nvim-qt" contains "nvim" and "vim".
        XCTAssertEqual(ToolIconCatalog.definition(for: "gitui-helper", category: .development).styleIdentifier, "known.gitui")
        XCTAssertEqual(ToolIconCatalog.definition(for: "nvim-qt", category: .development).styleIdentifier, "known.nvim")
        // Equal-length keys ("act", "aws", "bat", "git", "vim", "zed", …): the alphabetically first one.
        XCTAssertEqual(ToolIconCatalog.definition(for: "bat-git", category: .development).styleIdentifier, "known.bat")
    }
}

// MARK: - Update check preference

final class UpdateCheckPreferenceRegressionTests: XCTestCase {
    /// The key the Settings switch stores its state under.
    private let settingsSwitchKey = "TermiPad.updateChecksEnabled"
    private var savedValue: Any?

    private final class StubReleaseProtocol: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(#"{"tag_name":"v9.9.9","html_url":"release-page"}"#.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    override func setUp() {
        super.setUp()
        savedValue = UserDefaults.standard.object(forKey: settingsSwitchKey)
    }

    override func tearDown() {
        if let savedValue {
            UserDefaults.standard.set(savedValue, forKey: settingsSwitchKey)
        } else {
            UserDefaults.standard.removeObject(forKey: settingsSwitchKey)
        }
        super.tearDown()
    }

    private func stubbedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubReleaseProtocol.self]
        return URLSession(configuration: configuration)
    }

    /// The service read a differently spelled key than the switch wrote, so a check always came back "disabled".
    func testTurningTheSettingsSwitchOnEnablesTheCheck() async {
        XCTAssertEqual(UpdateCheckService.enabledDefaultsKey, settingsSwitchKey)

        UserDefaults.standard.set(true, forKey: settingsSwitchKey)
        let result = await UpdateCheckService.check(session: stubbedSession(), currentVersion: "1.0.0")
        XCTAssertEqual(result, .updateAvailable(latest: "v9.9.9", url: "release-page"))
    }

    func testTheCheckStaysOffWhileTheSwitchIsOff() async {
        UserDefaults.standard.set(false, forKey: settingsSwitchKey)
        let result = await UpdateCheckService.check(session: stubbedSession(), currentVersion: "1.0.0")
        XCTAssertEqual(result, .disabled)
    }
}

// MARK: - Localized copy

final class LocalizedCopyRegressionTests: XCTestCase {
    /// The recovery screen formats this template with String(format:). It takes %@ placeholders, so the counts
    /// have to be passed as strings; passing Int values made String(format:) read them as object pointers.
    func testRestoreSummaryTemplateFormatsCountsPassedAsStrings() {
        for language in AppLanguage.allCases {
            let template = AppCopy.text("restoreSummary", language: language)
            XCTAssertEqual(template.components(separatedBy: "%@").count - 1, 4)
            let message = String(format: template, String(3), String(0), String(12), String(1))
            XCTAssertFalse(message.contains("%"))
            for count in ["3", "0", "12", "1"] {
                XCTAssertTrue(message.contains(count), "\(language.rawValue): \(message)")
            }
        }
    }

    func testLookupsAreStableAcrossRepeatedCalls() {
        for _ in 0..<3 {
            XCTAssertEqual(AppCopy.text("allTools", language: .english), "All Tools")
            XCTAssertEqual(AppCopy.text("allTools", language: .simplifiedChinese), "所有工具")
            XCTAssertEqual(AppCopy.text("no-such-key", language: .english), "no-such-key")
        }
    }
}
