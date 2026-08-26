import AppKit
import Foundation

/// 仅在首次展示主窗口时以 iPad 纵向基准放入主屏可见区域。
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

        let reference = TermiPadWorkspaceMetrics.iPadReferenceSize
        let minimum = TermiPadWorkspaceMetrics.minimumSize
        let scale = min(1, visibleFrame.width / reference.width, visibleFrame.height / reference.height)
        let fittedWidth = max(minimum.width, floor(reference.width * scale))
        let fittedHeight = max(minimum.height, floor(reference.height * scale))
        let width = min(fittedWidth, visibleFrame.width)
        let height = min(fittedHeight, visibleFrame.height)
        let frame = NSRect(
            x: visibleFrame.minX + floor((visibleFrame.width - width) / 2),
            y: visibleFrame.minY + floor((visibleFrame.height - height) / 2),
            width: width,
            height: height
        )
        window.setFrame(frame, display: true, animate: false)
        UserDefaults.standard.set(true, forKey: hasPlacedInitialWindowKey)
    }
}
