// Local confirmation center for M1 launch requests (docs/m0-m1-mobile-entry-design.md §3.3.2).
// After a phone's requestLaunch arrives, the Mac must obtain the explicit consent of the **local user** through this center;
// no response within 60 seconds = denied (prevents requests from hanging on an unattended Mac — the Mac is always the sole execution authority).
// It carries only the single boolean decision "consent or not", never commands, paths, or any tool data.
import Foundation

@MainActor
final class MobileLaunchPromptCenter: ObservableObject {
    struct PendingLaunch: Identifiable {
        let id: UUID
        let toolName: String
        let deviceName: String
    }

    static let shared = MobileLaunchPromptCenter()
    static let confirmationTimeoutSeconds: TimeInterval = 60

    @Published private(set) var pending: PendingLaunch?

    private var continuations: [UUID: CheckedContinuation<Bool, Never>] = [:]
    private var timeoutTasks: [UUID: Task<Void, Never>] = [:]

    /// Wait for the local user's decision; a 60-second timeout counts as a denial.
    func requestConfirmation(toolName: String, deviceName: String) async -> Bool {
        let id = UUID()
        let accepted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            continuations[id] = continuation
            pending = PendingLaunch(id: id, toolName: toolName, deviceName: deviceName)
            timeoutTasks[id] = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.confirmationTimeoutSeconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.respond(false, for: id)
            }
        }
        return accepted
    }

    /// Alert button callbacks: launch / deny.
    func respond(_ accepted: Bool) {
        guard let current = pending else { return }
        respond(accepted, for: current.id)
    }

    private func respond(_ accepted: Bool, for id: UUID) {
        pending = nil
        timeoutTasks[id]?.cancel()
        timeoutTasks[id] = nil
        guard let continuation = continuations.removeValue(forKey: id) else { return }
        continuation.resume(returning: accepted)
    }
}
