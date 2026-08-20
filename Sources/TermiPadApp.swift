import SwiftUI
import SwiftData

@main
struct TermiPadApp: App {
    var body: some Scene {
        WindowGroup {
            LaunchpadView()
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .modelContainer(for: TerminalTool.self)
    }
}
