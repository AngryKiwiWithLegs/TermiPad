import Foundation
import SwiftData
import XCTest
@testable import TermiPad

final class TaskIntentPolicyTests: XCTestCase {
    func testTaskCatalogContainsOnlyFixedLocalDefinitions() {
        XCTAssertEqual(Set(FixedTaskCatalog.definitions.map(\.kind)), Set(TaskKind.allCases))
        XCTAssertTrue(FixedTaskCatalog.definitions.allSatisfy { definition in
            !definition.commandPreview.contains("\n")
                && !definition.commandPreview.contains(";")
                && !definition.commandPreview.contains("http")
        })
    }

    func testTaskIntentRequiresLocalReviewWindowAndApprovesFixedDefinition() throws {
        let directory = try makeTemporaryDirectory(named: "review")
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 2_000)
        let scope = TaskProjectScope(displayName: "Task Policy", rootPath: directory.path, createdAt: now)
        let intent = TaskIntentPolicy.makeIntent(scope: scope, kind: .swiftPackageTests, now: now)

        XCTAssertEqual(
            TaskIntentPolicy.review(intent, scope: scope, windows: [], existingIntents: [intent], now: now),
            .rejected(.localReviewRequired)
        )

        let window = TaskReviewWindow(
            projectScopeID: scope.id,
            maximumRisk: .low,
            openedAt: now,
            expiresAt: now.addingTimeInterval(TaskIntentPolicy.localReviewWindowLifetime)
        )
        XCTAssertEqual(
            TaskIntentPolicy.approve(intent, scope: scope, windows: [window], existingIntents: [intent], now: now),
            .allowed
        )
        XCTAssertEqual(intent.state, .approved)
        XCTAssertNotNil(intent.approvedAt)
        XCTAssertNil(intent.rejectionReason)
        XCTAssertEqual(intent.kind, .swiftPackageTests)
    }

    func testTaskIntentRejectsExpiredNonceReplayAndRiskMismatch() throws {
        let directory = try makeTemporaryDirectory(named: "rejection")
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 3_000)
        let scope = TaskProjectScope(displayName: "Task Policy", rootPath: directory.path, createdAt: now)
        let lowWindow = TaskReviewWindow(
            projectScopeID: scope.id,
            maximumRisk: .low,
            openedAt: now,
            expiresAt: now.addingTimeInterval(60)
        )

        let standardIntent = TaskIntentPolicy.makeIntent(scope: scope, kind: .macOSVerification, now: now)
        XCTAssertEqual(
            TaskIntentPolicy.review(standardIntent, scope: scope, windows: [lowWindow], existingIntents: [standardIntent], now: now),
            .rejected(.riskNotPermitted)
        )

        let expired = TaskIntentPolicy.makeIntent(
            scope: scope,
            kind: .swiftPackageTests,
            now: now.addingTimeInterval(-TaskIntentPolicy.proposalLifetime - 1)
        )
        XCTAssertEqual(
            TaskIntentPolicy.review(expired, scope: scope, windows: [lowWindow], existingIntents: [expired], now: now),
            .rejected(.taskExpired)
        )

        let sharedNonce = UUID()
        let first = TaskIntentPolicy.makeIntent(scope: scope, kind: .swiftPackageTests, now: now, nonce: sharedNonce)
        let replay = TaskIntentPolicy.makeIntent(scope: scope, kind: .swiftPackageTests, now: now, nonce: sharedNonce)
        XCTAssertEqual(
            TaskIntentPolicy.review(replay, scope: scope, windows: [lowWindow], existingIntents: [first, replay], now: now),
            .rejected(.nonceReplayed)
        )

        let unknown = TaskIntentPolicy.makeIntent(scope: scope, kind: .swiftPackageTests, now: now)
        unknown.kindRawValue = "not-shipped-with-termipad"
        XCTAssertEqual(
            TaskIntentPolicy.review(unknown, scope: scope, windows: [lowWindow], existingIntents: [unknown], now: now),
            .rejected(.unknownTaskKind)
        )

        let expiredWindow = TaskReviewWindow(
            projectScopeID: scope.id,
            maximumRisk: .standard,
            openedAt: now.addingTimeInterval(-120),
            expiresAt: now.addingTimeInterval(-1)
        )
        let afterWindowExpiry = TaskIntentPolicy.makeIntent(scope: scope, kind: .swiftPackageTests, now: now)
        XCTAssertEqual(
            TaskIntentPolicy.review(afterWindowExpiry, scope: scope, windows: [expiredWindow], existingIntents: [afterWindowExpiry], now: now),
            .rejected(.reviewWindowExpired)
        )

        TaskIntentPolicy.revoke(window: lowWindow, now: now)
        let afterWindowRevocation = TaskIntentPolicy.makeIntent(scope: scope, kind: .swiftPackageTests, now: now)
        XCTAssertEqual(
            TaskIntentPolicy.review(afterWindowRevocation, scope: scope, windows: [lowWindow], existingIntents: [afterWindowRevocation], now: now),
            .rejected(.localReviewRequired)
        )
    }

    // MARK: - 拒绝路径逐项独立测试（t0-checklist §4.2：每种拒绝路径至少一个单测）

    func testRejects_unknownTaskKind() throws {
        let directory = try makeTemporaryDirectory(named: "reject-unknown-kind")
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 10_000)
        let scope = TaskProjectScope(displayName: "S", rootPath: directory.path, createdAt: now)
        let window = TaskReviewWindow(
            projectScopeID: scope.id,
            maximumRisk: .standard,
            openedAt: now,
            expiresAt: now.addingTimeInterval(60)
        )
        let intent = TaskIntentPolicy.makeIntent(scope: scope, kind: .swiftPackageTests, now: now)
        intent.kindRawValue = "not-in-fixed-catalog"
        XCTAssertEqual(
            TaskIntentPolicy.review(intent, scope: scope, windows: [window], existingIntents: [intent], now: now),
            .rejected(.unknownTaskKind)
        )
    }

    func testRejects_projectScopeUnavailable() throws {
        let directory = try makeTemporaryDirectory(named: "reject-scope-unavail")
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 11_000)
        let scope = TaskProjectScope(displayName: "S", rootPath: directory.path, createdAt: now)
        let window = TaskReviewWindow(
            projectScopeID: scope.id,
            maximumRisk: .standard,
            openedAt: now,
            expiresAt: now.addingTimeInterval(60)
        )
        let intent = TaskIntentPolicy.makeIntent(scope: scope, kind: .swiftPackageTests, now: now)
        // 删除 scope 目录 → directoryIsAvailable 变 false
        try FileManager.default.removeItem(at: directory)
        XCTAssertEqual(
            TaskIntentPolicy.review(intent, scope: scope, windows: [window], existingIntents: [intent], now: now),
            .rejected(.projectScopeUnavailable)
        )
        // scope 已被撤销也应拒绝
        let freshDirectory = try makeTemporaryDirectory(named: "reject-scope-revoked")
        defer { try? FileManager.default.removeItem(at: freshDirectory) }
        let revokedScope = TaskProjectScope(displayName: "R", rootPath: freshDirectory.path, createdAt: now)
        TaskIntentPolicy.revoke(scope: revokedScope, intents: [])
        XCTAssertTrue(revokedScope.isRevoked)
        let intent2 = TaskIntentPolicy.makeIntent(scope: revokedScope, kind: .swiftPackageTests, now: now)
        let window2 = TaskReviewWindow(
            projectScopeID: revokedScope.id,
            maximumRisk: .standard,
            openedAt: now,
            expiresAt: now.addingTimeInterval(60)
        )
        XCTAssertEqual(
            TaskIntentPolicy.review(intent2, scope: revokedScope, windows: [window2], existingIntents: [intent2], now: now),
            .rejected(.projectScopeUnavailable)
        )
    }

    func testRejects_localReviewRequired() throws {
        let directory = try makeTemporaryDirectory(named: "reject-no-window")
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 12_000)
        let scope = TaskProjectScope(displayName: "S", rootPath: directory.path, createdAt: now)
        let intent = TaskIntentPolicy.makeIntent(scope: scope, kind: .swiftPackageTests, now: now)
        // 完全没开窗
        XCTAssertEqual(
            TaskIntentPolicy.review(intent, scope: scope, windows: [], existingIntents: [intent], now: now),
            .rejected(.localReviewRequired)
        )
    }

    func testRejects_reviewWindowExpired() throws {
        let directory = try makeTemporaryDirectory(named: "reject-window-expired")
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 13_000)
        let scope = TaskProjectScope(displayName: "S", rootPath: directory.path, createdAt: now)
        let expiredWindow = TaskReviewWindow(
            projectScopeID: scope.id,
            maximumRisk: .standard,
            openedAt: now.addingTimeInterval(-120),
            expiresAt: now.addingTimeInterval(-1)
        )
        let intent = TaskIntentPolicy.makeIntent(scope: scope, kind: .swiftPackageTests, now: now)
        XCTAssertEqual(
            TaskIntentPolicy.review(intent, scope: scope, windows: [expiredWindow], existingIntents: [intent], now: now),
            .rejected(.reviewWindowExpired)
        )
    }

    func testRejects_riskNotPermitted() throws {
        let directory = try makeTemporaryDirectory(named: "reject-risk")
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 14_000)
        let scope = TaskProjectScope(displayName: "S", rootPath: directory.path, createdAt: now)
        // 低风险窗口
        let lowWindow = TaskReviewWindow(
            projectScopeID: scope.id,
            maximumRisk: .low,
            openedAt: now,
            expiresAt: now.addingTimeInterval(60)
        )
        // 但发起的是 .standard 风险（macOSVerification）
        let standardIntent = TaskIntentPolicy.makeIntent(scope: scope, kind: .macOSVerification, now: now)
        XCTAssertEqual(
            TaskIntentPolicy.review(standardIntent, scope: scope, windows: [lowWindow], existingIntents: [standardIntent], now: now),
            .rejected(.riskNotPermitted)
        )
    }

    func testRejects_nonceReplayed() throws {
        let directory = try makeTemporaryDirectory(named: "reject-replay")
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 15_000)
        let scope = TaskProjectScope(displayName: "S", rootPath: directory.path, createdAt: now)
        let window = TaskReviewWindow(
            projectScopeID: scope.id,
            maximumRisk: .standard,
            openedAt: now,
            expiresAt: now.addingTimeInterval(60)
        )
        let sharedNonce = UUID()
        let first = TaskIntentPolicy.makeIntent(scope: scope, kind: .swiftPackageTests, now: now, nonce: sharedNonce)
        let replay = TaskIntentPolicy.makeIntent(scope: scope, kind: .swiftPackageTests, now: now, nonce: sharedNonce)
        XCTAssertEqual(
            TaskIntentPolicy.review(replay, scope: scope, windows: [window], existingIntents: [first, replay], now: now),
            .rejected(.nonceReplayed)
        )
    }

    func testRejects_taskExpired() throws {
        let directory = try makeTemporaryDirectory(named: "reject-task-expired")
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 16_000)
        let scope = TaskProjectScope(displayName: "S", rootPath: directory.path, createdAt: now)
        let window = TaskReviewWindow(
            projectScopeID: scope.id,
            maximumRisk: .standard,
            openedAt: now,
            expiresAt: now.addingTimeInterval(60)
        )
        // 在 now-proposalLifetime-1 时创建
        let expired = TaskIntentPolicy.makeIntent(
            scope: scope,
            kind: .swiftPackageTests,
            now: now.addingTimeInterval(-TaskIntentPolicy.proposalLifetime - 1)
        )
        XCTAssertEqual(
            TaskIntentPolicy.review(expired, scope: scope, windows: [window], existingIntents: [expired], now: now),
            .rejected(.taskExpired)
        )
    }

    func testRejects_taskNotPending() throws {
        let directory = try makeTemporaryDirectory(named: "reject-not-pending")
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 17_000)
        let scope = TaskProjectScope(displayName: "S", rootPath: directory.path, createdAt: now)
        let window = TaskReviewWindow(
            projectScopeID: scope.id,
            maximumRisk: .standard,
            openedAt: now,
            expiresAt: now.addingTimeInterval(60)
        )
        // 已批准
        let intent = TaskIntentPolicy.makeIntent(scope: scope, kind: .swiftPackageTests, now: now)
        intent.state = .approved
        XCTAssertEqual(
            TaskIntentPolicy.review(intent, scope: scope, windows: [window], existingIntents: [intent], now: now),
            .rejected(.taskNotPending)
        )
        // 已取消
        let cancelled = TaskIntentPolicy.makeIntent(scope: scope, kind: .swiftPackageTests, now: now)
        TaskIntentPolicy.cancel(cancelled, now: now)
        XCTAssertEqual(
            TaskIntentPolicy.review(cancelled, scope: scope, windows: [window], existingIntents: [cancelled], now: now),
            .rejected(.taskCancelled)
        )
    }

    func testRejects_taskCancelled() throws {
        let directory = try makeTemporaryDirectory(named: "reject-cancelled")
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 18_000)
        let scope = TaskProjectScope(displayName: "S", rootPath: directory.path, createdAt: now)
        let window = TaskReviewWindow(
            projectScopeID: scope.id,
            maximumRisk: .standard,
            openedAt: now,
            expiresAt: now.addingTimeInterval(60)
        )
        let intent = TaskIntentPolicy.makeIntent(scope: scope, kind: .swiftPackageTests, now: now)
        TaskIntentPolicy.cancel(intent, now: now)
        XCTAssertEqual(
            TaskIntentPolicy.review(intent, scope: scope, windows: [window], existingIntents: [intent], now: now),
            .rejected(.taskCancelled)
        )
    }

    func testRejects_scopeIDMismatch() throws {
        // 隐式拒绝路径：intent.projectScopeID 指向一个不存在的 scope。
        // review() 内 guard scope.id == intent.projectScopeID 会失败 → .projectScopeUnavailable
        let directory = try makeTemporaryDirectory(named: "reject-id-mismatch")
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 19_000)
        let realScope = TaskProjectScope(displayName: "Real", rootPath: directory.path, createdAt: now)
        let intent = TaskIntentPolicy.makeIntent(scope: realScope, kind: .swiftPackageTests, now: now)
        let fakeScope = TaskProjectScope(displayName: "Fake", rootPath: directory.path, createdAt: now)
        let window = TaskReviewWindow(
            projectScopeID: fakeScope.id,
            maximumRisk: .standard,
            openedAt: now,
            expiresAt: now.addingTimeInterval(60)
        )
        XCTAssertEqual(
            TaskIntentPolicy.review(intent, scope: fakeScope, windows: [window], existingIntents: [intent], now: now),
            .rejected(.projectScopeUnavailable)
        )
    }

    func testTaskScopeRevocationAndCancellationResolveLocalIntents() throws {
        let directory = try makeTemporaryDirectory(named: "revoke")
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 4_000)
        let scope = TaskProjectScope(displayName: "Task Policy", rootPath: directory.path, createdAt: now)
        let pending = TaskIntentPolicy.makeIntent(scope: scope, kind: .swiftPackageTests, now: now)
        let cancelled = TaskIntentPolicy.makeIntent(scope: scope, kind: .xcodegenGeneration, now: now)
        TaskIntentPolicy.cancel(cancelled, now: now)
        XCTAssertEqual(cancelled.state, .cancelled)

        TaskIntentPolicy.revoke(scope: scope, intents: [pending, cancelled], now: now)
        XCTAssertTrue(scope.isRevoked)
        XCTAssertEqual(pending.state, .revoked)
        XCTAssertEqual(pending.rejectionReason, .projectScopeUnavailable)
        XCTAssertEqual(cancelled.state, .cancelled)
    }

    func testTaskModelsPersistWithoutEnteringBackupPayload() throws {
        let directory = try makeTemporaryDirectory(named: "persist")
        let storeURL = directory.appendingPathComponent("TermiPad.store")
        defer { try? FileManager.default.removeItem(at: directory) }
        let projectPath = "/Users/example/private-task-project"
        let scopeID: UUID
        do {
            let container = try TermiPadDataStore.makeContainer(storeURL: storeURL)
            let context = ModelContext(container)
            let scope = TaskProjectScope(displayName: "Private Task", rootPath: projectPath)
            let intent = TaskIntentPolicy.makeIntent(scope: scope, kind: .swiftPackageTests)
            scopeID = scope.id
            context.insert(scope)
            context.insert(intent)
            try context.save()
        }
        let reopened = try TermiPadDataStore.makeContainer(storeURL: storeURL)
        let reopenedContext = ModelContext(reopened)
        XCTAssertEqual(try reopenedContext.fetch(FetchDescriptor<TaskProjectScope>()).map(\.id), [scopeID])

        let backup = TermiPadBackup.make(tools: [], candidates: [], includeSavedVariableValues: false)
        let json = try XCTUnwrap(String(data: try BackupService.encode(backup), encoding: .utf8))
        XCTAssertFalse(json.contains("private-task-project"))
        XCTAssertFalse(json.contains("TaskProjectScope"))
    }

    func testTaskDiagnosticsUseFixedPrivateEventCategories() throws {
        let suiteName = "TermiPadTests.task-diagnostics.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = DiagnosticsStore(defaults: defaults, storageKey: "events", now: { Date(timeIntervalSince1970: 5_000) })

        store.record(.taskProposalCreated)
        store.record(.taskReviewWindowOpened)
        store.record(.taskPolicyApproved)
        store.record(.taskScopeRevoked)

        XCTAssertEqual(store.events.map(\.kind), [.taskProposalCreated, .taskReviewWindowOpened, .taskPolicyApproved, .taskScopeRevoked])
        let report = try XCTUnwrap(String(data: JSONEncoder().encode(store.makePrivacyReport()), encoding: .utf8))
        XCTAssertFalse(report.contains("swift test"))
        XCTAssertFalse(report.contains("private-task-project"))
        XCTAssertFalse(report.contains("commandPreview"))
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermiPadTaskPolicy-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
