// M3 锁屏监测（docs/m3-remote-allow-window-design.md §3.2）：
// 远程窗口开启期间每 5 秒检查登录会话锁定状态——锁屏即关窗。
// 窗口关闭时不轮询（零开销）；检查逻辑复用 MobileTaskConsoleService
// 的 CGSessionCopyCurrentDictionary 单点（verify-macos.sh 守卫）。
import Foundation

@MainActor
final class LockStateMonitor: ObservableObject {
    static let shared = LockStateMonitor()
    static let pollInterval: TimeInterval = 5

    private var timer: Timer?
    /// 最近一次检测到的锁屏状态（UI 无需展示，仅供测试断言）。
    private(set) var lastKnownLocked: Bool?

    /// 窗口开启时启动监测；关闭时停止。
    func setActive(_ active: Bool) {
        guard active != (timer != nil) else { return }
        if active {
            let timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.checkOnce() }
            }
            self.timer = timer
            // 立即查一次——开窗瞬间 Mac 恰已锁屏则窗口立即失效。
            checkOnce()
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    private func checkOnce() {
        let locked = MobileTaskConsoleService.isLoginSessionLocked()
        if locked {
            RemoteAllowWindow.shared.invalidateOnLock()
        }
        lastKnownLocked = locked
    }
}
