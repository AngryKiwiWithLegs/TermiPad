import SwiftUI

/// Native macOS semantic colors that are softer than pure white / pure black.
struct SoftMacTheme {
    let colorScheme: ColorScheme

    var windowBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.135, green: 0.145, blue: 0.165)
            : Color(red: 0.948, green: 0.955, blue: 0.970)
    }

    var sidebarTint: Color {
        colorScheme == .dark
            ? Color(red: 0.160, green: 0.170, blue: 0.195)
            : Color(red: 0.905, green: 0.918, blue: 0.940)
    }

    var cardSurface: Color {
        colorScheme == .dark
            ? Color(red: 0.190, green: 0.200, blue: 0.230)
            : Color(red: 0.992, green: 0.994, blue: 1.0)
    }

    var cardStroke: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.095)
            : Color.black.opacity(0.075)
    }

    var cardShadow: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.25)
            : Color(red: 0.19, green: 0.24, blue: 0.34).opacity(0.10)
    }

    var contentSurface: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.035)
            : Color.white.opacity(0.58)
    }

    /// The iPad-style workspace only borrows the soft glass-panel layering; it does not imitate a device body, status bar, or touch system controls.
    var workspacePanelSurface: Color {
        colorScheme == .dark
            ? Color(red: 0.178, green: 0.190, blue: 0.224).opacity(0.94)
            : Color(red: 0.988, green: 0.991, blue: 0.998).opacity(0.88)
    }

    var workspacePanelStroke: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.115)
            : Color(red: 0.22, green: 0.29, blue: 0.42).opacity(0.12)
    }

    var workspacePanelShadow: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.28)
            : Color(red: 0.17, green: 0.25, blue: 0.39).opacity(0.14)
    }

    /// Hover tips use a macOS-style neutral grey material; in dark mode they keep enough layering instead of a harsh, high-contrast light block.
    var hoverSurface: Color {
        colorScheme == .dark
            ? Color(red: 0.285, green: 0.295, blue: 0.325).opacity(0.92)
            : Color(red: 0.900, green: 0.908, blue: 0.925).opacity(0.94)
    }

    var hoverStroke: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.16)
            : Color.black.opacity(0.12)
    }

    var hoverShadow: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.40)
            : Color.black.opacity(0.18)
    }
}

struct SoftMacWindowModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let appearanceKey: String

    func body(content: Content) -> some View {
        let theme = SoftMacTheme(colorScheme: colorScheme)
        content
            .background(theme.windowBackground.ignoresSafeArea())
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.30), value: appearanceKey)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.30), value: colorScheme)
    }
}

extension View {
    func softMacWindow(appearanceKey: String) -> some View {
        modifier(SoftMacWindowModifier(appearanceKey: appearanceKey))
    }
}
