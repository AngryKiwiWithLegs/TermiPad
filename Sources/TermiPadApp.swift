import SwiftUI
import SwiftData

@main
struct TermiPadApp: App {
    @AppStorage("TermiPad.appearance") private var appearanceRawValue = AppAppearance.system.rawValue
    private let sharedModelContainer: ModelContainer
    private let primaryStoreErrorDescription: String?

    init() {
        let environment = ProcessInfo.processInfo.environment
        if environment["TERMIPAD_UI_TEST_FORCE_RECOVERY"] == "1" {
            do {
                sharedModelContainer = try TermiPadDataStore.makeContainer(isStoredInMemoryOnly: true)
                primaryStoreErrorDescription = "UI test forced recovery mode"
            } catch {
                fatalError("Unable to create the in-memory recovery test data store: \(error)")
            }
        } else {
            do {
                sharedModelContainer = try TermiPadDataStore.makeContainer()
                primaryStoreErrorDescription = nil
            } catch {
                primaryStoreErrorDescription = error.localizedDescription
                do {
                    sharedModelContainer = try TermiPadDataStore.makeRecoveryContainer()
                } catch {
                    fatalError("Unable to create either the primary or recovery TermiPad data store: \(error)")
                }
            }
        }

        if environment["TERMIPAD_UI_TEST_MODE"] == "1" {
            UserDefaults.standard.set(false, forKey: "TermiPad.hasCompletedOnboarding")
        }
        WindowPlacementCoordinator.shared.installIfNeeded()
    }

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRawValue) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let primaryStoreErrorDescription {
                    DataStoreRecoveryView(primaryStoreErrorDescription: primaryStoreErrorDescription)
                } else {
                    LaunchpadView()
                }
            }
            .frame(minWidth: 680, minHeight: 560)
            .preferredColorScheme(appearance.colorScheme)
            .softMacWindow(appearanceKey: appearanceRawValue)
            .modelContainer(sharedModelContainer)
        }
        .defaultSize(width: 920, height: 720)
        .commands {
            TermiPadMenuCommands()
        }

        Settings {
            PreferencesView()
                .preferredColorScheme(appearance.colorScheme)
                .softMacWindow(appearanceKey: appearanceRawValue)
        }
        .modelContainer(sharedModelContainer)

        TermiPadMenuBarExtra()
    }
}
