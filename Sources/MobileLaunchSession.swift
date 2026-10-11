// M1.1 session allowlist (docs/m0-m1-mobile-entry-design.md §3.3.2, added 2026-09-08).
// Confirmation-free decision for the perSession / lowRiskSessionOnly policies: an in-memory [toolID: confirmation time] map on the Mac,
// never written to disk or backups, and never outliving the Mac's main process.
// Pure logic, no network and no persistence — the clock is injectable, so unit tests need not wait for real time.
import Foundation

@MainActor
final class MobileLaunchSession {
    /// Session window length: it expires if not refreshed in time (fixed at 5 minutes by the design doc; there is no never-expire option).
    static let sessionWindow: TimeInterval = 5 * 60

    static let shared = MobileLaunchSession()

    private var confirmedAt: [UUID: Date] = [:]
    private let now: () -> Date

    init(now: @escaping () -> Date = { Date() }) {
        self.now = now
    }

    /// Decide whether a direct launch without confirmation is allowed. The caller has already ensured the eligibility pre-check passed (including revokeMobilePermissionAt == nil).
    /// - Parameters:
    ///   - policy: the tool's local confirmation policy
    ///   - toolID: the target tool
    ///   - commandTemplate: the tool's command template — lowRiskSessionOnly additionally requires
    ///     no shell metacharacters (the eligibility pre-check already guarantees no template variables; this is the second line of defense)
    func canSkipConfirmation(
        policy: MobileLocalConfirmPolicy,
        toolID: UUID,
        commandTemplate: String
    ) -> Bool {
        guard let lastConfirmed = confirmedAt[toolID],
              now().timeIntervalSince(lastConfirmed) <= Self.sessionWindow else {
            return false
        }
        switch policy {
        case .everyTime:
            return false
        case .perSession:
            return true
        case .lowRiskSessionOnly:
            return !Self.containsShellMetacharacters(commandTemplate)
        }
    }

    /// Refresh the tool's session timestamp after local confirmation succeeds (called every time an everyTime prompt succeeds —
    /// a refresh rather than an insert, so perSession and lowRisk count from the same confirmation).
    func recordConfirmation(toolID: UUID) {
        confirmedAt[toolID] = now()
    }

    /// Invalidate immediately: called when the Mac revokes a tool's mobile permission or the user turns off the pairing listener.
    func invalidate(toolID: UUID) {
        confirmedAt[toolID] = nil
    }

    func invalidateAll() {
        confirmedAt.removeAll()
    }

    /// lowRisk second line of defense: any shell metacharacter means it is no longer treated as low risk.
    /// Complements the pre-check's no-variables check — the pre-check blocks variables, this blocks metacharacters used for injection.
    private static func containsShellMetacharacters(_ template: String) -> Bool {
        let metacharacters: Set<Character> = [";", "|", "&", "`", "$", ">", "<", "\\", "'", "\"", "("]
        return template.contains { metacharacters.contains($0) }
    }
}
