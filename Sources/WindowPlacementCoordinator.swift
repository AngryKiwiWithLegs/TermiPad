import AppKit
import Foundation

/// 仅在首次展示主窗口时将其放置到主屏可用区域的左半边。
/// 之后尊重 macOS 的窗口恢复机制和用户手动调整，不会反复抢占窗口位置。
final class WindowPlacementCoordinator {
    static let shared = WindowPlacementCoordinator()

    private let hasPlacedInitialWindowKey = "TermiPad.hasPlacedInitialMainWindow"
    private var observer: NSObjectProtocol?

    private init() {}

    func installIfNeeded() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.placeInitialWindowIfNeeded(notification.object as? NSWindow)
        }
    }

    private func placeInitialWindowIfNeeded(_ window: NSWindow?) {
        guard !UserDefaults.standard.bool(forKey: hasPlacedInitialWindowKey),
              let window,
              window.title == "TermiPad",
              let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame else {
            return
        }

        let halfWidth = floor(visibleFrame.width / 2)
        let frame = NSRect(
            x: visibleFrame.minX,
            y: visibleFrame.minY,
            width: halfWidth,
            height: visibleFrame.height
        )
        window.setFrame(frame, display: true, animate: false)
        UserDefaults.standard.set(true, forKey: hasPlacedInitialWindowKey)
    }
}
