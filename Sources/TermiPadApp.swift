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
                // UI 测试绝不触及用户的持久化 store；这也确保所有冒烟场景从同一份空白数据开始。
                sharedModelContainer = try TermiPadDataStore.makeContainer(isStoredInMemoryOnly: true)
                primaryStoreErrorDescription = nil
            } catch {
                fatalError("Unable to create the in-memory UI test data store: \(error)")
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

        if isUITest {
            UserDefaults.standard.set(false, forKey: "TermiPad.hasCompletedOnboarding")
            UserDefaults.standard.set(false, forKey: "TermiPad.discoveryPreviewEnabled")
            UserDefaults.standard.set(false, forKey: TaskMCPSettings.localMCPEnabledKey)
            DiscoveryCacheStore.clear()
            // M0 UI 测试 fixture（track-protocol stage 5.1）：当显式 env var 设了 SEED_TOOL
            // 时插入一个 pre-seeded TerminalTool。默认不插——保持现有 6 个 UI 测试
            // 行为不变（它们只检查侧边栏入口存在性）。
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
        }
        .defaultSize(
            width: TermiPadWorkspaceMetrics.iPadReferenceSize.width,
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

    /// M0 UI 测试 fixture（track-protocol stage 5.1）：在 in-memory SwiftData
    /// 容器里插入一个 pre-seeded TerminalTool，让 UI 测试可以打开工具编辑面板
    /// 断言"手机入口" section 的 5 个 accessibility identifier + revoke 按钮。
    ///
    /// **仅**在 `TERMIPAD_UI_TEST_MODE=1` 且 `TERMIPAD_UI_TEST_SEED_TOOL=1` 时由
    /// init() 调用。默认不插任何数据——保持现有 6 个 UI 测试行为完全不变。
    private static func seedUITestFixtureTool(in context: ModelContext) {
        let tool = TerminalTool(
            name: "merge-cli",
            executablePath: "/usr/local/bin/merge-cli",
            commandTemplate: "merge-cli --sync",
            category: .development
        )
        tool.toolDescription = "Test fixture tool for M0 UI assertions."
        // 显式设一个 M0 字段为 true，验证 toggle 在 UI 上能被定位。
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
