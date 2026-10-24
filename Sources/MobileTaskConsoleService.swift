// M2b task session center (docs/m2b-remote-task-console-design.md §5).
// Responsibilities: aggregate the "session entry feed" (a unified timeline of tool launches + fixed tasks) and handle the phone's
// task session operations. Data-minimization discipline: the phone sees only references, display names, status enums, and exit codes,
// never rootPath / commands / arguments / variables / the terminal output of tool launches.
// M2b-1 scope: the three read-only operations listScopes / listFixedTasks / getTaskStatus +
// entry records for tool launch events. M2b-3: the requestTaskProposal verification chain + cancelTask.
import CoreGraphics
import Foundation
import SwiftData

@MainActor
final class MobileTaskConsoleService: ObservableObject {
    static let shared = MobileTaskConsoleService()

    /// Entry ring buffer limit (design §5.3): one getTaskStatus from the phone gets the full snapshot,
    /// ≤50 entries × at most a few hundred bytes each, far below the 64 KB frame limit.
    static let entryLimit = 50
    /// How long an entry keeps more than its status summary (design §5.3): outputSnippet is cleared after 10 minutes
    /// — the retention window of output snippets is naturally bounded by the in-memory ring.
    static let outputRetentionInterval: TimeInterval = 600

    struct SessionEntry: Identifiable, Equatable {
        let id: UUID
        let title: String
        let kind: MobileSessionEntry.SessionKind
        /// Raw T1 TaskExecutionState string / launched|launchFailed for tool launches.
        let executionState: String
        let exitCode: Int?
        let startedAt: Date
        var finishedAt: Date?
        var outputSnippet: String?

        var isFinished: Bool { finishedAt != nil }
    }

    @Published private(set) var entries: [SessionEntry] = []

    /// Same test pattern as MobileLaunchSession: the singleton uses the system clock, and tests inject
    /// a fixed clock to get an isolated instance (singleton state does not leak between tests).
    private let now: () -> Date

    init(now: @escaping () -> Date = { Date() }) {
        self.now = now
    }

    // MARK: - Entry feed (tool launch events)

    /// The launch result callback of the M1 requestLaunch chain registers the entry here (the TerminalLauncher
    /// handoff path has no exit code and no output — that is a red line, not a to-do).
    func recordToolLaunch(id: UUID, title: String, succeeded: Bool) {
        append(SessionEntry(
            id: id,
            title: title,
            kind: .toolLaunch,
            executionState: succeeded ? "launched" : "launchFailed",
            exitCode: nil,
            startedAt: now(),
            finishedAt: now(),
            outputSnippet: nil))
        DiagnosticsStore.shared.record(.mobileConsoleEntryRecorded)
    }

    /// Registers T1 task lifecycle events (called by TaskExecutionCoordinator once M2b-3 wires it in;
    /// M2b-1 lands the data plane first). The output snippet is passed in by the caller only when the visibility is ≥ restricted
    /// (the §5.4 decision is made in the service layer, see outputVisibility).
    func recordTaskState(
        id: UUID,
        title: String,
        executionState: TaskExecutionState,
        exitCode: Int?,
        startedAt: Date?,
        finishedAt: Date?,
        outputSnippet: String?
    ) {
        let timestamp = now()
        let entry = SessionEntry(
            id: id,
            title: title,
            kind: .fixedTask,
            executionState: executionState.rawValue,
            exitCode: exitCode,
            startedAt: startedAt ?? timestamp,
            finishedAt: finishedAt,
            outputSnippet: currentVisibility == .minimal ? nil : outputSnippet)
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index] = entry
        } else {
            append(entry)
        }
    }

    private func append(_ entry: SessionEntry) {
        entries.insert(entry, at: 0)
        if entries.count > Self.entryLimit {
            entries.removeLast(entries.count - Self.entryLimit)
        }
    }

    /// Clear the snippet as soon as the output retention period expires (reclaimed in one place before a getTaskStatus snapshot).
    private func sweepExpiredOutput(now: Date = Date()) {
        for index in entries.indices {
            guard entries[index].outputSnippet != nil,
                  let finished = entries[index].finishedAt,
                  now.timeIntervalSince(finished) > Self.outputRetentionInterval else {
                continue
            }
            entries[index].outputSnippet = nil
        }
    }

    // MARK: - Output visibility (design §5.4; the Mac is the authority, UserDefaults is not backed up)

    enum OutputVisibility: String {
        case minimal
        case restricted
        case full
    }

    static let outputVisibilityDefaultsKey = "TermiPad.remoteOutputVisibility"

    var currentVisibility: OutputVisibility {
        OutputVisibility(rawValue: UserDefaults.standard.string(forKey: Self.outputVisibilityDefaultsKey) ?? "")
            ?? .restricted
    }

    // MARK: - Phone operations (the dispatch layer has already done pairing/decryption; this is the data plane only)

    /// listScopes: registered project scopes → id + display name (rootPath is never sent).
    func scopeSummaries(modelContext: ModelContext) -> [MobileScopeSummary] {
        let descriptor = FetchDescriptor<TaskProjectScope>(
            predicate: #Predicate { !$0.isRevoked })
        let scopes = (try? modelContext.fetch(descriptor)) ?? []
        return scopes.map { MobileScopeSummary(id: $0.id, displayName: $0.displayName) }
    }

    /// listFixedTasks: fixed catalog literals (kind + purpose + command preview — all
    /// catalog information FixedTaskCatalog already exposes, not user data).
    func fixedTaskSummaries(language: AppLanguage) -> [MobileFixedTaskSummary] {
        FixedTaskCatalog.definitions.map { definition in
            MobileFixedTaskSummary(
                kind: definition.kind.rawValue,
                purpose: definition.purpose(language: language),
                commandPreview: definition.commandPreview,
                requiredRelativePaths: definition.requiredRelativePaths)
        }
    }

    /// getTaskStatus: full snapshot of the entry feed (≤50 entries; output is decided by the visibility level and retention period).
    func sessionEntries(now: Date = Date()) -> [MobileSessionEntry] {
        sweepExpiredOutput(now: now)
        // One read of the setting for the whole snapshot instead of one per entry.
        let hidesOutput = currentVisibility == .minimal
        return entries.map { entry in
            MobileSessionEntry(
                id: entry.id,
                title: entry.title,
                kind: entry.kind,
                executionState: entry.executionState,
                exitCode: entry.exitCode,
                startedAt: entry.startedAt,
                finishedAt: entry.finishedAt,
                outputSnippet: hidesOutput ? nil : entry.outputSnippet)
        }
    }

    // MARK: - M2b-3 task submission verification chain (design §5.2 — the order is the attack-surface check order)

    /// Full verification and execution of requestTaskProposal. Returns the minimal receipt to the phone.
    /// 1 Pairing validity is guaranteed by the handshake layer (reaching here means already paired); this starts from the lock screen.
    func handleTaskProposal(
        taskKind: String?,
        projectScopeID: UUID?,
        modelContext: ModelContext,
        confirm: (String) async -> Bool
    ) async -> MobileTaskProposalResponse {
        // 3. Reject while locked (defense line 3): no remote tasks are accepted while the Mac is locked.
        if Self.isLoginSessionLocked() {
            DiagnosticsStore.shared.record(.remoteTaskBlockedScreenLocked)
            return MobileTaskProposalResponse(
                status: .rejected, reason: "The Mac is locked. The remote task was rejected.", taskIntentID: nil)
        }
        // 4. taskKind allowlist (FixedTaskCatalog is the attack surface).
        guard let taskKind, let kind = TaskKind(rawValue: taskKind),
              let definition = FixedTaskCatalog.definition(for: kind) else {
            return MobileTaskProposalResponse(
                status: .rejected, reason: "Unknown task type.", taskIntentID: nil)
        }
        // 5. The scope is registered, not revoked, and its directory is available.
        let scopeID = projectScopeID ?? UUID()
        var scopeDescriptor = FetchDescriptor<TaskProjectScope>(
            predicate: #Predicate { $0.id == scopeID })
        scopeDescriptor.fetchLimit = 1
        guard let scope = try? modelContext.fetch(scopeDescriptor).first,
              !scope.isRevoked, scope.directoryIsAvailable else {
            return MobileTaskProposalResponse(
                status: .rejected, reason: "The project scope is unavailable (not registered or revoked).", taskIntentID: nil)
        }
        // 6. Full T0 policy verification: risk / window / nonce / expiry.
        let intent = TaskIntentPolicy.makeIntent(scope: scope, kind: kind)
        let windows = (try? modelContext.fetch(FetchDescriptor<TaskReviewWindow>())) ?? []
        let existing = (try? modelContext.fetch(FetchDescriptor<TaskIntent>())) ?? []
        let decision = TaskIntentPolicy.review(
            intent, scope: scope, windows: windows, existingIntents: existing)
        guard case .allowed = decision else {
            // Rejection reasons are mapped to fixed copy; the specific reason is written to diagMac (review() is
            // a pure decision and does not persist rejectionReason — take it straight from the decision; 2026-09-15:
            // reading intent.rejectionReason before was always nil).
            let reason: TaskRejectionReason?
            if case .rejected(let r) = decision { reason = r } else { reason = nil }
            let text = Self.rejectionText(reason)
            DiagnosticsStore.shared.record(.remoteTaskRejectedByPolicy)
            MobilePairingService.diagMac("Phone task rejected by T0 policy: \(reason?.rawValue ?? "unknown")")
            return MobileTaskProposalResponse(
                status: .rejected, reason: text, taskIntentID: nil)
        }
        // 7. Confirmation tier (the three M1.1 tiers extended + the M3 daily window): lowRisk with risk==.low
        //    hitting the allowlist, or the daily remote window being open → no confirmation; everything else shows the 60-second local confirmation.
        let needsConfirmation: Bool
        if definition.risk == .low,
           MobileLaunchSession.shared.canSkipConfirmation(
               policy: .lowRiskSessionOnly, toolID: intent.id,
               commandTemplate: definition.commandPreview) {
            needsConfirmation = false
            DiagnosticsStore.shared.record(.mobileTaskAutoConfirmed)
        } else if RemoteAllowWindow.shared.allowsSkipConfirmation() {
            needsConfirmation = false
            DiagnosticsStore.shared.record(.remoteAllowWindowUsed)
            MobilePairingService.diagMac("Daily remote window hit, task runs without confirmation")
        } else {
            needsConfirmation = true
        }
        if needsConfirmation {
            let accepted = await confirm(definition.purpose(language: .current))
            guard accepted else {
                DiagnosticsStore.shared.record(.remoteTaskRejectedByUser)
                return MobileTaskProposalResponse(
                    status: .rejected, reason: "This task was denied on the Mac.", taskIntentID: nil)
            }
            MobileLaunchSession.shared.recordConfirmation(toolID: intent.id)
        }
        // 8. approve → T1 execution (fixed executable / arguments / timeout / stoppable / empty stdin).
        _ = TaskIntentPolicy.approve(intent, scope: scope, windows: windows, existingIntents: existing)
        try? modelContext.insert(intent)
        let title = definition.purpose(language: .current)
        let started = TaskExecutionCoordinator.shared.start(intent: intent, scope: scope) {}
        if case .rejected(let rejection) = started {
            // Precise feedback (requested by the user on 2026-09-10): a failed pre-check must say what is missing —
            // the red line allows returning "the task's fixed directory requirements" (FixedTaskCatalog literals,
            // not user data), but not the scope path itself.
            let missingPaths = definition.requiredRelativePaths.filter { relative in
                !FileManager.default.fileExists(
                    atPath: URL(fileURLWithPath: scope.rootPath, isDirectory: true)
                        .appendingPathComponent(relative).path)
            }
            let reason: String
            if !missingPaths.isEmpty {
                reason = "The target directory is missing files this task requires: \(missingPaths.joined(separator: ", ")). Register a project directory that contains these files."
            } else {
                reason = "The task start pre-check did not pass (the required executable does not exist on this Mac, or the target directory is unavailable)."
            }
            MobilePairingService.diagMac("Phone task start pre-check rejected: \(rejection.rawValue), missing files=\(missingPaths.count)")
            return MobileTaskProposalResponse(status: .rejected, reason: reason, taskIntentID: intent.id)
        }
        recordTaskState(
            id: intent.id, title: title, executionState: intent.executionState,
            exitCode: nil, startedAt: intent.executionStartedAt, finishedAt: nil,
            outputSnippet: nil)
        return MobileTaskProposalResponse(
            status: .accepted, reason: nil, taskIntentID: intent.id)
    }

    /// T0 rejection reason → fixed copy for the phone (no paths and no commands — enum semantics, not data).
    private static func rejectionText(_ reason: TaskRejectionReason?) -> String {
        switch reason {
        case .localReviewRequired: return "No active project review window is open on the Mac."
        case .reviewWindowExpired: return "The project review window has expired. Open it again on the Mac."
        case .riskNotPermitted: return "The task's risk level exceeds what the review window allows."
        case .projectScopeUnavailable: return "The project scope is unavailable (not registered or revoked)."
        case .unknownTaskKind: return "Unknown task type."
        case .taskExpired: return "The task proposal has expired."
        case .taskNotPending: return "The task is not pending review."
        case .nonceReplayed: return "The task request was replayed and has been rejected."
        case .taskCancelled: return "The task was cancelled."
        default: return "The task was rejected by local policy (\(reason?.rawValue ?? "unknown reason"))."
        }
    }

    /// Lock detection for the Mac login session (defense line 3). Single CGSessionCopyCurrentDictionary call site,
    /// guarded (the verify-macos.sh allowlist contains only this file).
    nonisolated static func isLoginSessionLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            // If the session dictionary cannot be read (no GUI / abnormal environment), be conservative: treat it as locked.
            return true
        }
        if let locked = session["CGSSessionScreenIsLocked"] as? Bool {
            return locked
        }
        return false
    }

    // MARK: - M2b-3 cancelTask (design §5.1: only tasks submitted by the phone that are running)

    /// Cancel a running task. The phone can only stop T1 tasks (tool launches are terminal handoffs, and the terminal
    /// owns stopping — no new execution entry point).
    func cancelTask(taskIntentID: UUID) -> MobileTaskProposalResponse {
        let coordinator = TaskExecutionCoordinator.shared
        if coordinator.runningIntentIDs.contains(taskIntentID) {
            // Finding the intent object is handled by the coordinator's internal activeIntents;
            // stop needs the intent — the entry's registered lifecycle is enough to stop the process.
            if let intent = coordinator.intent(forID: taskIntentID) {
                coordinator.stop(intent: intent)
                return MobileTaskProposalResponse(
                    status: .accepted, reason: nil, taskIntentID: taskIntentID)
            }
        }
        return MobileTaskProposalResponse(
            status: .rejected, reason: "The task is not running and cannot be stopped.", taskIntentID: nil)
    }
}
