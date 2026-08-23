import SwiftUI

/// 比纯白/纯黑更柔和的 macOS 原生语义配色。
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
