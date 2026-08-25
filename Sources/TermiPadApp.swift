import SwiftUI
import SwiftData

@main
struct TermiPadApp: App {
    @AppStorage("TermiPad.appearance") private var appearanceRawValue = AppAppearance.system.rawValue
    private let sharedModelContainer: ModelContainer

    init() {
        do {
            sharedModelContainer = try TermiPadDataStore.makeContainer()
        } catch {
            fatalError("Unable to create TermiPad data store: \(error)")
        }

        if ProcessInfo.processInfo.environment["TERMIPAD_UI_TEST_MODE"] == "1" {
            UserDefaults.standard.set(false, forKey: "TermiPad.hasCompletedOnboarding")
        }
        WindowPlacementCoordinator.shared.installIfNeeded()
    }

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRawValue) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            LaunchpadView()
                .frame(minWidth: 680, minHeight: 560)
                .preferredColorScheme(appearance.colorScheme)
                .softMacWindow(appearanceKey: appearanceRawValue)
        }
        .defaultSize(width: 920, height: 720)
        .modelContainer(sharedModelContainer)

        Settings {
            PreferencesView()
                .preferredColorScheme(appearance.colorScheme)
                .softMacWindow(appearanceKey: appearanceRawValue)
        }
        .modelContainer(sharedModelContainer)
    }
}
