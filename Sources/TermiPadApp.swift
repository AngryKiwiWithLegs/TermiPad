import SwiftUI
import SwiftData

@main
struct TermiPadApp: App {
    var body: some Scene {
        WindowGroup {
            LaunchpadView()
                .frame(minWidth: 900, minHeight: 620)
        }
        .modelContainer(for: [TerminalTool.self, CandidateTool.self])

        Settings {
            PreferencesView()
        }
    }
}
