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
                // M2a：用户上次开启过异地隧道则随 app 启动自动恢复
                // （UI 测试模式下跳过——绝不碰真实 Keychain/CLI/网络）。
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
            // M2b：手机启动/任务确认弹窗挂载在 app 根视图——此前只在
            // PreferencesView 上挂载，用户不在设置页时弹窗无处显示，
            // 手机端提交/启动请求无限挂起（2026-09-10 实测：任务提交
            // "没反应"即此因）。根视图常驻 → 任何页面都能弹。
            MobileLaunchConfirmationRootView()
        }
        .defaultSize(
            // UI 测试用宽窗口：729pt 实际默认宽度下外观分段控件会被挤进
            // 工具栏溢出弹层，identifier 查找失败（2026-09-09 快照实证）。
            // 只在 TERMIPAD_UI_TEST_MODE 下加宽，不影响真实窗口默认值。
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

/// 手机启动/任务确认弹窗的全局挂载点（M2b，2026-09-10）。
/// 此前弹窗只挂在 PreferencesView——用户不在设置页时 alert 无处显示，
/// 手机端的启动/任务请求在"等本机确认"一步无限挂起。根视图常驻，
/// 任何页面都能弹。
struct MobileLaunchConfirmationRootView: View {
    @ObservedObject private var launchPrompt = MobileLaunchPromptCenter.shared
    @AppStorage("TermiPad.language") private var languageRawValue = AppLanguage.simplifiedChinese.rawValue

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRawValue) ?? .simplifiedChinese
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .alert(
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
