import AppKit
import Foundation

/// Only when the main window is first shown, place it in the main screen's visible area using the iPad portrait baseline.
/// After that, respect macOS's window restoration and the user's manual adjustments; never grab the window position repeatedly.
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
        // UI test mode: place unconditionally (a persistent flag would make later test instances skip placement,
        // and SwiftUI's window frame restoration would override defaultSize — 2026-09-09 test:
        // the window was stuck at the narrow 729pt width). The real user path is unchanged: placed only once.
        let isUITest = ProcessInfo.processInfo.environment["TERMIPAD_UI_TEST_MODE"] == "1"
        let minimum = TermiPadWorkspaceMetrics.minimumSize
        guard isUITest || !UserDefaults.standard.bool(forKey: hasPlacedInitialWindowKey),
              let window,
              // SwiftUI's navigation title ("All Tools" / "Settings", etc.) replaces NSWindow.title —
              // so the main window cannot be identified by title == "TermiPad". Use contentMinSize instead:
              // the main window has the workspace minimum-size constraint; other panels (such as About) do not.
              (window.contentMinSize.width >= minimum.width),
              let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame else {
            return
        }

        let reference = TermiPadWorkspaceMetrics.iPadReferenceSize
        // UI test mode uses a wide window: at the actual 729pt width the appearance segmented control gets squeezed into the toolbar
        // overflow popover and the identifier lookup fails (confirmed by a snapshot on 2026-09-09). Widened on the test path only;
        // the real user's iPad reference layout is unaffected.
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
