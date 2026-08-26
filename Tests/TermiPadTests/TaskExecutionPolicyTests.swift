import XCTest
@testable import TermiPad

final class TaskExecutionPolicyTests: XCTestCase {
    func testApprovedFixedProjectTaskPreparesBoundedRequest() throws {
        let root = try makeTaskProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let scope = TaskProjectScope(displayName: "T1 Fixture", rootPath: root.path)
        let intent = TaskIntentPolicy.makeIntent(scope: scope, kind: .macOSVerification, now: Date(timeIntervalSince1970: 1_000))
        intent.state = .approved

        let decision = TaskExecutionPolicy.prepare(intent: intent, scope: scope, now: Date(timeIntervalSince1970: 1_001))
        guard case .ready(let request) = decision else {
            return XCTFail("已批准的固定项目任务应能形成受限本地执行请求。")
        }

        XCTAssertEqual(request.executableURL.path, root.appendingPathComponent("scripts/verify-macos.sh").path)
        XCTAssertEqual(request.arguments, [])
        XCTAssertEqual(request.currentDirectoryURL.path, root.path)
        XCTAssertEqual(request.environment["HOME"], root.path)
        XCTAssertEqual(request.environment["PATH"], "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin")
        XCTAssertEqual(request.timeout, 300)
    }

    func testExecutionPolicyRejectsUnapprovedExpiredAndAlreadyStartedIntents() throws {
        let root = try makeTaskProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let scope = TaskProjectScope(displayName: "T1 Fixture", rootPath: root.path)
        let now = Date(timeIntervalSince1970: 1_000)
        let intent = TaskIntentPolicy.makeIntent(scope: scope, kind: .macOSVerification, now: now)

        XCTAssertEqual(TaskExecutionPolicy.prepare(intent: intent, scope: scope, now: now), .rejected(.intentNotApproved))

        intent.state = .approved
        intent.expiresAt = now.addingTimeInterval(-1)
        XCTAssertEqual(TaskExecutionPolicy.prepare(intent: intent, scope: scope, now: now), .rejected(.intentExpired))

        intent.expiresAt = now.addingTimeInterval(60)
        TaskExecutionPolicy.markStarted(intent, now: now)
        XCTAssertEqual(TaskExecutionPolicy.prepare(intent: intent, scope: scope, now: now), .rejected(.taskAlreadyStarted))
    }

    func testExecutionPolicyRequiresFixedPreflightFilesAndTracksMinimalResult() throws {
        let root = try makeTaskProject(includeVerificationScript: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let scope = TaskProjectScope(displayName: "T1 Fixture", rootPath: root.path)
        let now = Date(timeIntervalSince1970: 1_000)
        let intent = TaskIntentPolicy.makeIntent(scope: scope, kind: .macOSVerification, now: now)
        intent.state = .approved

        XCTAssertEqual(TaskExecutionPolicy.prepare(intent: intent, scope: scope, now: now), .rejected(.taskPreflightFailed))

        TaskExecutionPolicy.markStarted(intent, now: now)
        TaskExecutionPolicy.markExited(intent, exitCode: 7, now: now.addingTimeInterval(4))
        XCTAssertEqual(intent.executionState, .failed)
        XCTAssertEqual(intent.executionExitCode, 7)
        XCTAssertNotNil(intent.executionFinishedAt)
        XCTAssertNil(intent.executionRejectionReason)
    }

    private func makeTaskProject(includeVerificationScript: Bool = true) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TermiPad-T1-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("// fixture".utf8).write(to: root.appendingPathComponent("Package.swift"))
        try Data("name: fixture".utf8).write(to: root.appendingPathComponent("project.yml"))
        if includeVerificationScript {
            let scripts = root.appendingPathComponent("scripts", isDirectory: true)
            try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
            let script = scripts.appendingPathComponent("verify-macos.sh")
            try Data("#!/usr/bin/env bash\nexit 0\n".utf8).write(to: script)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        }
        return root
    }
}
