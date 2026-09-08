// M1 启动请求的本机确认中心（docs/m0-m1-mobile-entry-design.md §3.3.2）。
// 手机 requestLaunch 到达后，Mac 必须经本中心获得**本机用户**的明确同意；
// 60 秒无响应 = 拒绝（防无人值守 Mac 上请求悬挂——Mac 始终是唯一执行权威）。
// 只承载"是否同意"这一个布尔决策，不承载命令、路径或任何工具数据。
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

    /// 等待本机用户决策；60 秒超时视为拒绝。
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

    /// alert 按钮回调：启动 / 拒绝。
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
