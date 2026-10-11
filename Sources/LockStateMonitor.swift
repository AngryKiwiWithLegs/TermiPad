// M3 lock-screen monitor (docs/m3-remote-allow-window-design.md §3.2):
// while the remote window is open, check the login session's lock state every 5 seconds — locking the screen closes the window.
// No polling while the window is closed (zero overhead); the check reuses MobileTaskConsoleService's
// single CGSessionCopyCurrentDictionary call site (guarded by verify-macos.sh).
import Foundation

@MainActor
final class LockStateMonitor: ObservableObject {
    static let shared = LockStateMonitor()
    static let pollInterval: TimeInterval = 5

    private var timer: Timer?
    /// The most recently detected lock state (not shown in the UI; for test assertions only).
    private(set) var lastKnownLocked: Bool?

    /// Start monitoring when the window opens; stop when it closes. The first check is delayed by 5 seconds — during the LA
    /// authentication that opens the window, the lock state reported by the system is unreliable (2026-09-19 real device: the window was
    /// judged locked and closed as soon as it opened); the delay avoids the authentication period.
    func setActive(_ active: Bool) {
        guard active != (timer != nil) else { return }
        if active {
            let timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.checkOnce() }
            }
            self.timer = timer
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
