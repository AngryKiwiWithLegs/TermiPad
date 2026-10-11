import SwiftUI

/// TermiPad uses the 11-inch iPad Pro portrait workspace as its visual baseline, but always defers to macOS's visible screen area and the user's window adjustments.
enum TermiPadWorkspaceMetrics {
    /// Logical point size of the 11-inch iPad Pro portrait workspace, used as the preferred baseline for the first window rather than an enforced size.
    static let iPadReferenceSize = CGSize(width: 834, height: 1_194)
    static let minimumSize = CGSize(width: 640, height: 560)
    static let contentPanelCornerRadius: CGFloat = 18
    static let contentPanelInset: CGFloat = 12
}

struct TermiPadWorkspacePanelModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let theme = SoftMacTheme(colorScheme: colorScheme)
        content
            .padding(TermiPadWorkspaceMetrics.contentPanelInset)
            .background(
                theme.workspacePanelSurface,
                in: RoundedRectangle(
                    cornerRadius: TermiPadWorkspaceMetrics.contentPanelCornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: TermiPadWorkspaceMetrics.contentPanelCornerRadius,
                    style: .continuous
                )
                .strokeBorder(theme.workspacePanelStroke, lineWidth: 1)
            }
            .shadow(color: theme.workspacePanelShadow, radius: 12, y: 5)
            .padding(TermiPadWorkspaceMetrics.contentPanelInset)
    }
}

extension View {
    /// Gives the detail area a reachable "terminal tool panel" layer without imitating an iPad body, status bar, or touch navigation.
    func termiPadWorkspacePanel() -> some View {
        modifier(TermiPadWorkspacePanelModifier())
    }
}
