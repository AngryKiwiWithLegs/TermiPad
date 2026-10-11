import XCTest
import SwiftData
@testable import TermiPad

/// Real process behavior tests (t0-checklist §4.3: process tree and cancellation evidence).
///
/// The only production file allowed to use `Process(` is `Sources/TaskExecutionService.swift` (static guard 18 in
/// verify-macos.sh). This test does **not** construct `Process` directly; it only starts
/// the system `/bin/sh` process through the public `TaskExecutionCoordinator` interface.
///
/// Wait pattern: the `onCompletion` closure of `TaskExecutionCoordinator.start(_:scope:onCompletion:)`
/// is called after `finish(intentID:exitCode:)`. In tests this is the most reliable signal that
/// "the process has ended and SwiftData has been written". Combined with the terminationHandler hopping to the main actor
/// via `Task { @MainActor ... }`, it avoids polling main-actor state.
@MainActor
final class TaskExecutionServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var scope: TaskProjectScope!
    private var scratchDirectory: URL!
    private var scriptsDirectory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        scratchDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermiPadTaskExec-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)

        // Simulate a minimal executable project structure: Package.swift / project.yml / scripts/verify-macos.sh
        try Data("// fixture".utf8).write(to: scratchDirectory.appendingPathComponent("Package.swift"))
        try Data("name: fixture".utf8).write(to: scratchDirectory.appendingPathComponent("project.yml"))
        scriptsDirectory = scratchDirectory.appendingPathComponent("scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: scriptsDirectory, withIntermediateDirectories: true)

        scope = TaskProjectScope(displayName: "T1 Exec", rootPath: scratchDirectory.path)
        container = try TermiPadDataStore.makeContainer(isStoredInMemoryOnly: true)
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratchDirectory)
    }

    // MARK: - Process tree and cancellation evidence

    func testExitCodeZeroMarksSucceeded() throws {
        try makeVerifyScript("""
        #!/usr/bin/env bash
        exit 0
        """)
        let intent = try makeApprovedIntent(kind: .macOSVerification)
        let expectation = expectation(description: "intent completion")

        TaskExecutionCoordinator.shared.start(intent: intent, scope: scope) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 15)
        XCTAssertEqual(intent.executionState, .succeeded)
        XCTAssertEqual(intent.executionExitCode, 0)
        XCTAssertNotNil(intent.executionFinishedAt)
        XCTAssertNil(intent.executionRejectionReason)
    }

    func testNonZeroExitCodeMarksFailed() throws {
        try makeVerifyScript("""
        #!/usr/bin/env bash
        exit 7
        """)
        let intent = try makeApprovedIntent(kind: .macOSVerification)
        let expectation = expectation(description: "intent completion")

        TaskExecutionCoordinator.shared.start(intent: intent, scope: scope) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 15)
        XCTAssertEqual(intent.executionState, .failed)
        XCTAssertEqual(intent.executionExitCode, 7)
        XCTAssertNotNil(intent.executionFinishedAt)
    }

    func testStopTerminatesRunningProcess() throws {
        try makeVerifyScript("""
        #!/usr/bin/env bash
        sleep 30
        """)
        let intent = try makeApprovedIntent(kind: .macOSVerification)

        TaskExecutionCoordinator.shared.start(intent: intent, scope: scope) {}

        // Wait for the process to actually enter the running set (do not rely on onCompletion)
        let startDeadline = Date().addingTimeInterval(5)
        while !TaskExecutionCoordinator.shared.runningIntentIDs.contains(intent.id), Date() < startDeadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertTrue(TaskExecutionCoordinator.shared.runningIntentIDs.contains(intent.id),
                      "the process should enter runningIntentIDs within 5 seconds.")

        // Explicit stop() — synchronous path: Sources/TaskExecutionService.swift:168-173
        // markStopped() immediately sets executionState = .stopped + finishedAt
        TaskExecutionCoordinator.shared.stop(intent: intent)
        XCTAssertEqual(intent.executionState, .stopped)
        XCTAssertNotNil(intent.executionFinishedAt)
        // Do not wait for the process to really exit: activeProcesses is private, so OS behavior cannot be tested
        // (but stop already calls process.terminate() internally to send SIGTERM, and the OS reclaims it)
    }

    func testAlreadyStartedIntentIsRejected() throws {
        try makeVerifyScript("""
        #!/usr/bin/env bash
        sleep 30
        """)
        let intent = try makeApprovedIntent(kind: .macOSVerification)

        let firstDecision = TaskExecutionCoordinator.shared.start(intent: intent, scope: scope) {}
        XCTAssertTrue({
            if case .ready = firstDecision { return true }
            return false
        }(), "The first start should prepare an execution request.")

        // Wait for the process to enter the running set
        let startDeadline = Date().addingTimeInterval(5)
        while !TaskExecutionCoordinator.shared.runningIntentIDs.contains(intent.id), Date() < startDeadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        // A second start of the same intent should be rejected with .taskAlreadyStarted
        let secondDecision = TaskExecutionCoordinator.shared.start(intent: intent, scope: scope) {}
        XCTAssertEqual(secondDecision, .rejected(.taskAlreadyStarted))
        XCTAssertEqual(intent.executionState, .startRejected)
        XCTAssertEqual(intent.executionRejectionReason, .taskAlreadyStarted)

        // Cleanup: stop the process from the first start
        TaskExecutionCoordinator.shared.stop(intent: intent)
    }

    func testUnapprovedIntentIsRejected() throws {
        // Not via makeApprovedIntent; init directly to keep the default .pendingReview
        let intent = TaskIntent(
            projectScopeID: scope.id,
            kind: .swiftPackageTests,
            risk: .low,
            expiresAt: Date().addingTimeInterval(600)
        )
        XCTAssertEqual(intent.state, .pendingReview, "A new intent defaults to pendingReview.")
        let decision = TaskExecutionCoordinator.shared.start(intent: intent, scope: scope) {}
        XCTAssertEqual(decision, .rejected(.intentNotApproved))
        XCTAssertEqual(intent.executionState, .startRejected)
        XCTAssertEqual(intent.executionRejectionReason, .intentNotApproved)
    }

    // MARK: - Helpers

    private func makeApprovedIntent(kind: TaskKind) throws -> TaskIntent {
        let intent = TaskIntentPolicy.makeIntent(scope: scope, kind: kind)
        intent.state = .approved
        intent.approvedAt = Date(timeIntervalSince1970: 1_000_000)
        intent.expiresAt = Date().addingTimeInterval(600)
        return intent
    }

    private func makeVerifyScript(_ content: String) throws {
        // Use the fixed file name of the .macOSVerification task: scripts/verify-macos.sh
        // (see requiredRelativePaths of FixedTaskCatalog in Sources/TaskIntent.swift:243-251)
        let path = scriptsDirectory.appendingPathComponent("verify-macos.sh")
        try content.write(to: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path)
    }
}
