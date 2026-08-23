import SwiftUI
import SwiftData

@main
struct TermiPadApp: App {
    @AppStorage("TermiPad.appearance") private var appearanceRawValue = AppAppearance.system.rawValue

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRawValue) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            LaunchpadView()
                .frame(minWidth: 900, minHeight: 620)
                .preferredColorScheme(appearance.colorScheme)
        }
        .modelContainer(for: [TerminalTool.self, CandidateTool.self])

        Settings {
            PreferencesView()
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}
