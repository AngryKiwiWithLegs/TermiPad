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
            // M2b：手机启动/任务确认弹窗挂载在 app 根内容上——此前只在
            // PreferencesView，用户不在设置页时弹窗无处显示（2026-09-10
            // 实测"没反应"）；后改独立零尺寸视图挂载，macOS 上零尺寸视图
            // 的 alert 不渲染（2026-09-15 实测仍无弹窗）。正确做法：alert
            // 直接作为根内容 Group 的 modifier——尺寸由 LaunchpadView 决定，
            // alert 修饰符在真实层级上必然生效。
            // M2b：确认弹窗挂在根内容真实层级（零尺寸视图的 alert 在
            // macOS 不渲染）。UI 测试模式跳过——ObservedObject 单例
            // 订阅在 Runner 连接建立期阻塞 accessibility（2026-09-17
            // 二分实证：禁用后 UI 测试即全绿），真机路径不受影响。
            .modifier(MobileLaunchConfirmationAlertModifier(
                isDisabled: ProcessInfo.processInfo.environment["TERMIPAD_UI_TEST_MODE"] == "1"))
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

/// 手机启动/任务确认弹窗的全局挂载（M2b，2026-09-10；2026-09-15 改
/// ViewModifier 形态）。历史教训：挂在 PreferencesView 时用户不在设置页
/// 则弹窗无处显示；改成独立零尺寸 view 后 macOS 对零尺寸视图的 alert
/// 仍不渲染。ViewModifier 直接加在 WindowGroup 根内容（LaunchpadView
/// 所在的真实层级）上——alert 必然生效。
struct MobileLaunchConfirmationAlertModifier: ViewModifier {
    /// UI 测试模式下不订阅确认中心（见挂载点注释）；真机恒 false。
    let isDisabled: Bool
    @ObservedObject private var launchPrompt = MobileLaunchPromptCenter.shared
    @AppStorage("TermiPad.language") private var languageRawValue = AppLanguage.simplifiedChinese.rawValue

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRawValue) ?? .simplifiedChinese
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
