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
