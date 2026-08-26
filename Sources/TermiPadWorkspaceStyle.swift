import SwiftUI

/// TermiPad 以 11 英寸 iPad Pro 纵向工作区为视觉基准，但始终服从 macOS 的可见屏幕区域与用户窗口调整。
enum TermiPadWorkspaceMetrics {
    /// 11 英寸 iPad Pro 纵向工作区的逻辑点尺寸，用作首次窗口的优选基准而非强制尺寸。
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
    /// 为详情区域提供可触达的「终端工具面板」层次，不模拟 iPad 机身、状态栏或触控导航。
    func termiPadWorkspacePanel() -> some View {
        modifier(TermiPadWorkspacePanelModifier())
    }
}
