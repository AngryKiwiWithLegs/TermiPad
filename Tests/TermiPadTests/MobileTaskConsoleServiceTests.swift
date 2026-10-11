import XCTest
@testable import TermiPad

/// M2b-1 task session center contract tests (docs/m2b-remote-task-console-design.md §5.3/§5.4):
/// entry feed cap, no output for tool launches, output visibility decisions, retention sweep. All pure logic.
@MainActor
final class MobileTaskConsoleServiceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: MobileTaskConsoleService.outputVisibilityDefaultsKey)
    }

    private func makeEntry(
        id: UUID = UUID(),
        offsetMinutes: TimeInterval = 0,
        output: String? = nil
    ) -> Date {
        Date().addingTimeInterval(-offsetMinutes * 60)
    }

    func testToolLaunchEntryNeverCarriesOutputOrExitCode() {
        let service = MobileTaskConsoleService()
        service.recordToolLaunch(id: UUID(), title: "Build", succeeded: true)
        service.recordToolLaunch(id: UUID(), title: "Build", succeeded: false)
        let snapshot = service.sessionEntries()
        XCTAssertEqual(snapshot.count, 2)
        for entry in snapshot where entry.kind == .toolLaunch {
            XCTAssertNil(entry.outputSnippet, "Tool launches (terminal handoff) never return output")
            XCTAssertNil(entry.exitCode, "The terminal handoff path has no exit code")
        }
        XCTAssertEqual(
            Set(snapshot.map(\.executionState)),
            Set(["launched", "launchFailed"]))
    }

    func testEntryStreamCapsAtLimit() {
        let service = MobileTaskConsoleService()
        let limit = MobileTaskConsoleService.entryLimit
        for index in 0..<(limit + 10) {
            service.recordToolLaunch(id: UUID(), title: "Tool \(index)", succeeded: true)
        }
        XCTAssertEqual(service.sessionEntries().count, limit)
        // The newest entry comes first — the ring keeps the most recent ones and the earliest are pushed out.
        let titles = service.sessionEntries().map(\.title)
        XCTAssertEqual(titles.first, "Tool \(limit + 9)")
    }

    func testTaskStateUpdatesInPlaceById() {
        let service = MobileTaskConsoleService()
        let taskID = UUID()
        service.recordTaskState(
            id: taskID, title: "swift test", executionState: .running,
            exitCode: nil, startedAt: Date(), finishedAt: nil, outputSnippet: nil)
        service.recordTaskState(
            id: taskID, title: "swift test", executionState: .succeeded,
            exitCode: 0, startedAt: Date(), finishedAt: Date(), outputSnippet: nil)
        let snapshot = service.sessionEntries()
        XCTAssertEqual(snapshot.count, 1, "The same task is updated in place by id and does not take a second slot")
        XCTAssertEqual(snapshot.first?.executionState, TaskExecutionState.succeeded.rawValue)
        XCTAssertEqual(snapshot.first?.exitCode, 0)
    }

    func testMinimalVisibilityStripsOutputSnippet() {
        UserDefaults.standard.set(
            MobileTaskConsoleService.OutputVisibility.minimal.rawValue,
            forKey: MobileTaskConsoleService.outputVisibilityDefaultsKey)
        let service = MobileTaskConsoleService()
        let taskID = UUID()
        service.recordTaskState(
            id: taskID, title: "swift test", executionState: .running,
            exitCode: nil, startedAt: Date(), finishedAt: nil,
            outputSnippet: "Test Suite passed")
        XCTAssertNil(service.sessionEntries().first?.outputSnippet, "At the minimal level output snippets are never sent")
    }

    func testRestrictedVisibilityKeepsOutputSnippet() {
        // The default level is restricted (the default suggested by design §5.4).
        UserDefaults.standard.set(
            MobileTaskConsoleService.OutputVisibility.restricted.rawValue,
            forKey: MobileTaskConsoleService.outputVisibilityDefaultsKey)
        let service = MobileTaskConsoleService()
        let taskID = UUID()
        service.recordTaskState(
            id: taskID, title: "swift test", executionState: .succeeded,
            exitCode: 0, startedAt: Date(), finishedAt: Date(),
            outputSnippet: "Test Suite passed")
        XCTAssertEqual(service.sessionEntries().first?.outputSnippet, "Test Suite passed")
    }

    func testDefaultVisibilityIsRestricted() {
        // Falls back to restricted when unset — the design's suggested default (applies unless the user says otherwise).
        let service = MobileTaskConsoleService()
        XCTAssertEqual(service.currentVisibility, .restricted)
    }

    func testExpiredOutputIsSweptAfterRetentionInterval() {
        UserDefaults.standard.set(
            MobileTaskConsoleService.OutputVisibility.restricted.rawValue,
            forKey: MobileTaskConsoleService.outputVisibilityDefaultsKey)
        let service = MobileTaskConsoleService()
        let oldFinished = Date().addingTimeInterval(
            -(MobileTaskConsoleService.outputRetentionInterval + 60))
        service.recordTaskState(
            id: UUID(), title: "Old task", executionState: .succeeded,
            exitCode: 0, startedAt: oldFinished, finishedAt: oldFinished,
            outputSnippet: "stale output")
        XCTAssertNil(service.sessionEntries().first?.outputSnippet, "Output snippets past the retention period are swept away")
    }

    func testFixedTaskSummariesCarryCatalogLiterals() {
        let service = MobileTaskConsoleService()
        let summaries = service.fixedTaskSummaries(language: .simplifiedChinese)
        XCTAssertEqual(summaries.count, FixedTaskCatalog.definitions.count)
        // The catalog fields are public FixedTaskCatalog literals (kind / purpose / command preview),
        // not user data — the count and the set of kinds must correspond one-to-one with the catalog.
        XCTAssertEqual(
            Set(summaries.map(\.kind)),
            Set(FixedTaskCatalog.definitions.map { $0.kind.rawValue }))
        XCTAssertTrue(summaries.allSatisfy { !$0.purpose.isEmpty && !$0.commandPreview.isEmpty })
    }
}

// MARK: - M4 stream replay (docs/m4-interactive-session-design.md §2.1)

/// The stream service tests must be constructed outside a MainActor context — use @MainActor test methods.
@MainActor
final class TaskOutputStreamServiceTests: XCTestCase {

    func testSubscribeReplaysBufferedOutputImmediately() {
        let service = TaskOutputStreamService()
        let taskID = UUID()
        // Simulate T1 producing output first (the buffer already has content before subscribing).
        service.dispatchOutput(taskID: taskID, rawText: "line one\nline two\n")

        var pushed: [MobileStreamChunk] = []
        let connectionID = UUID()
        service.registerSink(connectionID) { chunk in pushed.append(chunk) }
        let cursor = service.subscribe(
            connectionID: connectionID, taskID: taskID, resumeOffset: nil) { chunk in
                pushed.append(chunk)
            }

        // Replay: push the backlog immediately on subscribe (its absence was confirmed on a real device as the root cause of "waiting for output").
        XCTAssertFalse(pushed.isEmpty, "The buffered backlog must be pushed immediately on subscribe")
        XCTAssertEqual(pushed.reduce(0) { $0 + $1.text.utf8.count }, "line one\nline two\n".utf8.count)
        XCTAssertEqual(cursor, pushed.last!.offset + pushed.last!.text.utf8.count)
        // The content goes through the redaction pipeline (plain text is unchanged).
        XCTAssertTrue(pushed.contains { $0.text.contains("line one") })
    }

    func testSubscribeWithResumeOffsetContinuesFromCursor() {
        let service = TaskOutputStreamService()
        let taskID = UUID()
        service.dispatchOutput(taskID: taskID, rawText: "AAAA\nBBBB\n")
        var pushed: [MobileStreamChunk] = []
        let connectionID = UUID()
        service.registerSink(connectionID) { chunk in pushed.append(chunk) }
        // Reconnect after a drop: claims the first 5 bytes ("AAAA\n") were consumed — the resume pushes only the B part.
        _ = service.subscribe(
            connectionID: connectionID, taskID: taskID, resumeOffset: 5) { chunk in
                pushed.append(chunk)
            }
        XCTAssertTrue(pushed.contains { $0.text.contains("BBBB") })
        XCTAssertFalse(pushed.contains { $0.text.contains("AAAA") }, "The already-consumed part must not be pushed again")
    }

    func testDispatchOutputPushesToActiveSubscriber() {
        let service = TaskOutputStreamService()
        let taskID = UUID()
        var pushed: [MobileStreamChunk] = []
        let connectionID = UUID()
        service.registerSink(connectionID) { chunk in pushed.append(chunk) }
        _ = service.subscribe(
            connectionID: connectionID, taskID: taskID, resumeOffset: nil) { chunk in
                pushed.append(chunk)
            }
        // New T1 output after subscribing → pushed in real time.
        service.dispatchOutput(taskID: taskID, rawText: "live output\n")
        XCTAssertTrue(pushed.contains { $0.text.contains("live output") },
                      "New output after subscribing must be pushed in real time")
    }

    func testOutputIsRedactedBeforePush() {
        let service = TaskOutputStreamService()
        let taskID = UUID()
        var pushed: [MobileStreamChunk] = []
        let connectionID = UUID()
        service.registerSink(connectionID) { chunk in pushed.append(chunk) }
        _ = service.subscribe(
            connectionID: connectionID, taskID: taskID, resumeOffset: nil) { chunk in
                pushed.append(chunk)
            }
        service.dispatchOutput(taskID: taskID,
                               rawText: "token=supersecretvalue123\n")
        XCTAssertFalse(pushed.contains { $0.text.contains("supersecretvalue123") },
                       "Output must be redacted before being pushed")
        XCTAssertTrue(pushed.contains { $0.text.contains(OutputRedactor.mask) })
    }

    func testPurgeAllClearsBuffersAndSubscriptions() {
        let service = TaskOutputStreamService()
        let taskID = UUID()
        service.dispatchOutput(taskID: taskID, rawText: "data\n")
        var pushed: [MobileStreamChunk] = []
        let connectionID = UUID()
        service.registerSink(connectionID) { chunk in pushed.append(chunk) }
        _ = service.subscribe(
            connectionID: connectionID, taskID: taskID, resumeOffset: nil) { chunk in
                pushed.append(chunk)
            }
        service.purgeAll()
        pushed.removeAll()
        service.dispatchOutput(taskID: taskID, rawText: "after purge\n")
        XCTAssertTrue(pushed.isEmpty, "Buffers and subscriptions must be cleared after the window closes")
    }
}
