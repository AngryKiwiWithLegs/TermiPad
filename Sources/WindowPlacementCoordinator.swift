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
        // UI 测试模式：无条件放置（持久 flag 会让后续测试实例跳过放置，
        // 而 SwiftUI 的窗口 frame 恢复会盖过 defaultSize——2026-09-09 实测
        // 窗口卡在 729pt 窄宽）。真实用户路径不变：只放一次。
        let isUITest = ProcessInfo.processInfo.environment["TERMIPAD_UI_TEST_MODE"] == "1"
        let minimum = TermiPadWorkspaceMetrics.minimumSize
        guard isUITest || !UserDefaults.standard.bool(forKey: hasPlacedInitialWindowKey),
              let window,
              // SwiftUI 的导航标题（"所有工具"/"设置"等）会替换 NSWindow.title——
              // 不能用 title == "TermiPad" 识别主窗口。用 contentMinSize 判：
              // 主窗口有 workspace 最小尺寸约束，其他面板（如 about）没有。
              (window.contentMinSize.width >= minimum.width),
              let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame else {
            return
        }

        let reference = TermiPadWorkspaceMetrics.iPadReferenceSize
        // UI 测试模式用宽窗口：729pt 实际宽度下外观分段控件会被挤进工具栏
        // 溢出弹层，identifier 查找失败（2026-09-09 快照实证）。仅测试路径加宽，
        // 不影响真实用户的 iPad 参考布局。
        let targetWidth = isUITest ? 1_600 : reference.width
        let scale = min(1, visibleFrame.width / targetWidth, visibleFrame.height / reference.height)
        let fittedWidth = max(minimum.width, floor(targetWidth * scale))
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
        if !isUITest {
            UserDefaults.standard.set(true, forKey: hasPlacedInitialWindowKey)
        }
    }
}
