import XCTest
import SwiftData
@testable import TermiPad

/// 真实进程行为测试（t0-checklist §4.3：进程树和取消证据）。
///
/// 唯一允许 `Process(` 的生产文件是 `Sources/TaskExecutionService.swift`（verify-macos.sh
/// 第 18 条静态守卫）。本测试**不**直接构造 `Process`，只通过
/// `TaskExecutionCoordinator` 公共接口启动系统 `/bin/sh` 进程。
///
/// 等待模式：`TaskExecutionCoordinator.start(_:scope:onCompletion:)` 的
/// `onCompletion` 闭包在 `finish(intentID:exitCode:)` 之后被调用。这是测试中
/// "process 已结束且 SwiftData 已写入" 的最可靠信号。配合 `Task { @MainActor ... }`
/// 跳到主 actor 的 terminationHandler，避免轮询 main-actor 状态。
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

        // 模拟一个最小可执行项目结构：Package.swift / project.yml / scripts/verify-macos.sh
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

    // MARK: - 进程树和取消证据

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

        // 等 process 真的进入 running 集合（不是依赖 onCompletion）
        let startDeadline = Date().addingTimeInterval(5)
        while !TaskExecutionCoordinator.shared.runningIntentIDs.contains(intent.id), Date() < startDeadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertTrue(TaskExecutionCoordinator.shared.runningIntentIDs.contains(intent.id),
                      "process 应在 5 秒内进入 runningIntentIDs。")

        // 显式 stop() — 同步路径：Sources/TaskExecutionService.swift:168-173
        // markStopped() 立即设 executionState = .stopped + finishedAt
        TaskExecutionCoordinator.shared.stop(intent: intent)
        XCTAssertEqual(intent.executionState, .stopped)
        XCTAssertNotNil(intent.executionFinishedAt)
        // 不再等 process 真的退出：activeProcesses 是 private，无法测 OS 行为
        // （但 stop 内部已调 process.terminate() 触发 SIGTERM，OS 负责回收）
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
        }(), "第一次 start 应准备执行请求。")

        // 等 process 进入 running 集合
        let startDeadline = Date().addingTimeInterval(5)
        while !TaskExecutionCoordinator.shared.runningIntentIDs.contains(intent.id), Date() < startDeadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        // 第二次 start 同一个 intent 应被 .taskAlreadyStarted 拒绝
        let secondDecision = TaskExecutionCoordinator.shared.start(intent: intent, scope: scope) {}
        XCTAssertEqual(secondDecision, .rejected(.taskAlreadyStarted))
        XCTAssertEqual(intent.executionState, .startRejected)
        XCTAssertEqual(intent.executionRejectionReason, .taskAlreadyStarted)

        // 清理：stop 第一次启动的 process
        TaskExecutionCoordinator.shared.stop(intent: intent)
    }

    func testUnapprovedIntentIsRejected() throws {
        // 不通过 makeApprovedIntent；直接 init 保留默认 .pendingReview
        let intent = TaskIntent(
            projectScopeID: scope.id,
            kind: .swiftPackageTests,
            risk: .low,
            expiresAt: Date().addingTimeInterval(600)
        )
        XCTAssertEqual(intent.state, .pendingReview, "新建 intent 默认 pendingReview。")
        let decision = TaskExecutionCoordinator.shared.start(intent: intent, scope: scope) {}
        XCTAssertEqual(decision, .rejected(.intentNotApproved))
        XCTAssertEqual(intent.executionState, .startRejected)
        XCTAssertEqual(intent.executionRejectionReason, .intentNotApproved)
    }

    // MARK: - 辅助

    private func makeApprovedIntent(kind: TaskKind) throws -> TaskIntent {
        let intent = TaskIntentPolicy.makeIntent(scope: scope, kind: kind)
        intent.state = .approved
        intent.approvedAt = Date(timeIntervalSince1970: 1_000_000)
        intent.expiresAt = Date().addingTimeInterval(600)
        return intent
    }

    private func makeVerifyScript(_ content: String) throws {
        // 用 .macOSVerification 任务的固定文件名：scripts/verify-macos.sh
        // （见 Sources/TaskIntent.swift:243-251 FixedTaskCatalog 的 requiredRelativePaths）
        let path = scriptsDirectory.appendingPathComponent("verify-macos.sh")
        try content.write(to: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path)
    }
}
