import SwiftUI
import SwiftData

@main
struct TermiPadApp: App {
    var body: some Scene {
        WindowGroup {
            LaunchpadView()
                .frame(minWidth: 800, minHeight: 600)
        }
        .modelContainer(for: TerminalTool.self)
    }
}
