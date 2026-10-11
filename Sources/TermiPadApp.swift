import SwiftUI
import SwiftData

@main
@MainActor
enum TermiPadBootstrap {
    static func main() {
        if ProcessInfo.processInfo.arguments.contains("--termipad-mcp-stdio") {
            TermiPadMCPStdIORuntime.run()
            return
        }
        TermiPadApplication.main()
    }
}

struct TermiPadApplication: App {
    @AppStorage("TermiPad.appearance") private var appearanceRawValue = AppAppearance.system.rawValue
    private let sharedModelContainer: ModelContainer
    private let primaryStoreErrorDescription: String?

    init() {
        let environment = ProcessInfo.processInfo.environment
        let isUITest = environment["TERMIPAD_UI_TEST_MODE"] == "1"
        if environment["TERMIPAD_UI_TEST_FORCE_RECOVERY"] == "1" {
            do {
                sharedModelContainer = try TermiPadDataStore.makeContainer(isStoredInMemoryOnly: true)
                primaryStoreErrorDescription = "UI test forced recovery mode"
            } catch {
                fatalError("Unable to create the in-memory recovery test data store: \(error)")
            }
        } else if isUITest {
            do {
                // UI tests never touch the user's persistent store; this also ensures every smoke scenario starts from the same blank data.
                sharedModelContainer = try TermiPadDataStore.makeContainer(isStoredInMemoryOnly: true)
                primaryStoreErrorDescription = nil
            } catch {
                fatalError("Unable to create the in-memory UI test data store: \(error)")
            }
        } else {
            do {
                sharedModelContainer = try TermiPadDataStore.makeContainer()
                primaryStoreErrorDescription = nil
                // M2a: if the user had the remote tunnel on last time, restore it automatically at app launch
                // (skipped in UI test mode — never touch the real Keychain / CLI / network).
                if !isUITest {
                    TailnetTunnelService.shared.restoreIfNeeded()
                }
            } catch {
                primaryStoreErrorDescription = error.localizedDescription
                do {
                    sharedModelContainer = try TermiPadDataStore.makeRecoveryContainer()
                } catch {
                    fatalError("Unable to create either the primary or recovery TermiPad data store: \(error)")
                }
            }
        }

        if isUITest {
            UserDefaults.standard.set(false, forKey: "TermiPad.hasCompletedOnboarding")
            UserDefaults.standard.set(false, forKey: "TermiPad.discoveryPreviewEnabled")
            UserDefaults.standard.set(false, forKey: TaskMCPSettings.localMCPEnabledKey)
            DiscoveryCacheStore.clear()
            // M0 UI test fixture (track-protocol stage 5.1): when the explicit env var SEED_TOOL is set,
            // insert one pre-seeded TerminalTool. Not inserted by default — the existing 6 UI tests keep
            // their behavior (they only check that the sidebar entries exist).
            if environment["TERMIPAD_UI_TEST_SEED_TOOL"] == "1" {
                let seedContext = sharedModelContainer.mainContext
                Self.seedUITestFixtureTool(in: seedContext)
            }
        }
        if primaryStoreErrorDescription == nil {
            TaskMCPBridge.install(modelContainer: sharedModelContainer)
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
            .frame(minWidth: TermiPadWorkspaceMetrics.minimumSize.width, minHeight: TermiPadWorkspaceMetrics.minimumSize.height)
            .preferredColorScheme(appearance.colorScheme)
            .softMacWindow(appearanceKey: appearanceRawValue)
            // M2b: the phone launch / task confirmation prompt is mounted on the app's root content — previously it lived only in
            // PreferencesView, so the prompt had nowhere to appear when the user was not on the Settings page (2026-09-10
            // test: "nothing happens"); it was then mounted on a separate zero-size view, but on macOS the alert of a zero-size
            // view is not rendered (2026-09-15 test: still no prompt). The right approach: the alert
            // is a modifier directly on the root content Group — its size is determined by LaunchpadView,
            // so the alert modifier is guaranteed to take effect in a real hierarchy.
            // M2b: the confirmation prompt is attached to the real hierarchy of the root content (the alert of a zero-size view is
            // not rendered on macOS). Skipped in UI test mode — the ObservedObject singleton
            // subscription blocks accessibility while the Runner connection is being established (2026-09-17,
            // confirmed by bisecting: with it disabled the UI tests all pass); the real-device path is unaffected.
            .modifier(MobileLaunchConfirmationAlertModifier(
                isDisabled: ProcessInfo.processInfo.environment["TERMIPAD_UI_TEST_MODE"] == "1"))
        }
        .defaultSize(
            // Wide window for UI tests: at the actual default width of 729pt the appearance segmented control gets squeezed into
            // the toolbar overflow popover and the identifier lookup fails (confirmed by a snapshot on 2026-09-09).
            // Widened only under TERMIPAD_UI_TEST_MODE; the real window default is unaffected.
            width: ProcessInfo.processInfo.environment["TERMIPAD_UI_TEST_MODE"] == "1"
                ? 1_600 : TermiPadWorkspaceMetrics.iPadReferenceSize.width,
            height: TermiPadWorkspaceMetrics.iPadReferenceSize.height
        )
        .modelContainer(sharedModelContainer)
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

    /// M0 UI test fixture (track-protocol stage 5.1): inserts one pre-seeded TerminalTool into the in-memory SwiftData
    /// container so UI tests can open the tool edit panel
    /// and assert the 5 accessibility identifiers + the revoke button of the "Mobile Entry" section.
    ///
    /// Called by init() **only** when `TERMIPAD_UI_TEST_MODE=1` and `TERMIPAD_UI_TEST_SEED_TOOL=1`.
    /// No data is inserted by default — the behavior of the existing 6 UI tests stays exactly the same.
    private static func seedUITestFixtureTool(in context: ModelContext) {
        let tool = TerminalTool(
            name: "merge-cli",
            executablePath: "/usr/local/bin/merge-cli",
            commandTemplate: "merge-cli --sync",
            category: .development
        )
        tool.toolDescription = "Test fixture tool for M0 UI assertions."
        // Explicitly set one M0 field to true to verify that the toggle can be located in the UI.
        tool.showInMobileEntry = true
        tool.mobileLocalConfirmPolicy = .everyTime
        context.insert(tool)
        do {
            try context.save()
        } catch {
            fatalError("Unable to insert M0 UI test fixture tool: \(error)")
        }
    }
}

/// Global mount for the phone launch / task confirmation prompt (M2b, 2026-09-10; changed to a
/// ViewModifier on 2026-09-15). Lessons learned: when mounted in PreferencesView the prompt had nowhere to appear if the user was not on the Settings page;
/// after moving it to a separate zero-size view, macOS still did not render the alert of a zero-size view.
/// The ViewModifier is applied directly to the WindowGroup's root content (the real hierarchy
/// LaunchpadView lives in) — the alert is guaranteed to take effect.
struct MobileLaunchConfirmationAlertModifier: ViewModifier {
    /// In UI test mode the confirmation center is not subscribed to (see the comment at the mount point); always false on a real device.
    let isDisabled: Bool
    @ObservedObject private var launchPrompt = MobileLaunchPromptCenter.shared
    @AppStorage("TermiPad.language") private var languageRawValue = AppLanguage.defaultLanguage.rawValue

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRawValue) ?? .defaultLanguage
    }

    func body(content: Content) -> some View {
        if isDisabled {
            content
        } else {
            alertContent(content)
        }
    }

    private func alertContent(_ content: Content) -> some View {
        content.alert(
            AppCopy.text("mobileLaunchPromptTitle", language: language),
            isPresented: Binding(
                get: { launchPrompt.pending != nil },
                set: { _ in launchPrompt.respond(false) })
        ) {
            Button(AppCopy.text("mobileLaunchPromptAccept", language: language)) {
                launchPrompt.respond(true)
            }
            Button(AppCopy.text("mobileLaunchPromptDeny", language: language), role: .cancel) {
                launchPrompt.respond(false)
            }
        } message: {
            if let pending = launchPrompt.pending {
                Text(AppCopy.format(
                    "mobileLaunchPromptBody",
                    "\(pending.toolName) · \(pending.deviceName)",
                    language: language))
            }
        }
    }
}
