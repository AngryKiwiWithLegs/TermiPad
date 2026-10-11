import Foundation

enum TaskPolicyDecision: Equatable {
    case allowed
    case rejected(TaskRejectionReason)
}

/// T0's purely local policy. This type runs no commands, creates no processes, accesses no network, and handles no terminal input or output.
enum TaskIntentPolicy {
    static let proposalLifetime: TimeInterval = 5 * 60
    static let localReviewWindowLifetime: TimeInterval = 15 * 60

    static func makeIntent(
        scope: TaskProjectScope,
        kind: TaskKind,
        now: Date = Date(),
        nonce: UUID = UUID()
    ) -> TaskIntent {
        let risk = FixedTaskCatalog.definition(for: kind)?.risk ?? .standard
        return TaskIntent(
            projectScopeID: scope.id,
            kind: kind,
            risk: risk,
            nonce: nonce,
            proposedAt: now,
            expiresAt: now.addingTimeInterval(proposalLifetime)
        )
    }

    static func review(
        _ intent: TaskIntent,
        scope: TaskProjectScope?,
        windows: [TaskReviewWindow],
        existingIntents: [TaskIntent],
        now: Date = Date()
    ) -> TaskPolicyDecision {
        guard intent.state == .pendingReview else {
            return .rejected(intent.state == .cancelled ? .taskCancelled : .taskNotPending)
        }
        guard let kind = intent.kind, FixedTaskCatalog.definition(for: kind) != nil else {
            return .rejected(.unknownTaskKind)
        }
        guard let scope, scope.id == intent.projectScopeID, !scope.isRevoked, scope.directoryIsAvailable else {
            return .rejected(.projectScopeUnavailable)
        }
        guard intent.expiresAt > now else {
            return .rejected(.taskExpired)
        }
        let duplicateNonceExists = existingIntents.contains { other in
            other.id != intent.id && other.nonce == intent.nonce && other.state != .rejected
        }
        guard !duplicateNonceExists else {
            return .rejected(.nonceReplayed)
        }
        let configuredWindows = windows.filter {
            $0.projectScopeID == scope.id && $0.revokedAt == nil
        }
        guard !configuredWindows.isEmpty else {
            return .rejected(.localReviewRequired)
        }
        let activeWindows = configuredWindows.filter { $0.isActive(at: now) }
        guard !activeWindows.isEmpty else {
            return .rejected(.reviewWindowExpired)
        }
        guard activeWindows.contains(where: { $0.maximumRisk.permits(intent.risk) }) else {
            return .rejected(.riskNotPermitted)
        }
        return .allowed
    }

    @discardableResult
    static func approve(
        _ intent: TaskIntent,
        scope: TaskProjectScope?,
        windows: [TaskReviewWindow],
        existingIntents: [TaskIntent],
        now: Date = Date()
    ) -> TaskPolicyDecision {
        let decision = review(intent, scope: scope, windows: windows, existingIntents: existingIntents, now: now)
        switch decision {
        case .allowed:
            intent.state = .approved
            intent.approvedAt = now
            intent.resolvedAt = now
            intent.rejectionReason = nil
        case .rejected(let reason):
            intent.rejectionReason = reason
            intent.resolvedAt = now
            intent.state = reason == .taskExpired ? .expired : .rejected
        }
        return decision
    }

    static func cancel(_ intent: TaskIntent, now: Date = Date()) {
        guard intent.state == .pendingReview || intent.state == .approved else { return }
        intent.state = .cancelled
        intent.resolvedAt = now
        intent.rejectionReason = nil
    }

    static func revoke(scope: TaskProjectScope, intents: [TaskIntent], now: Date = Date()) {
        scope.isRevoked = true
        scope.revokedAt = now
        for intent in intents where intent.projectScopeID == scope.id && (intent.state == .pendingReview || intent.state == .approved) {
            intent.state = .revoked
            intent.resolvedAt = now
            intent.rejectionReason = .projectScopeUnavailable
        }
    }

    static func revoke(window: TaskReviewWindow, now: Date = Date()) {
        window.revokedAt = now
    }
}
