import XCTest

final class TermiPadUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        if app != nil {
            attachScreenshot(named: "termipad-final-ui-state")
        }
        app?.terminate()
    }

    func testLibraryLaunchShowsPrimaryControls() throws {
        launchApp()
        completeOnboarding()

        let discoveryButton = element("discover-tools-button")
        XCTAssertTrue(
            discoveryButton.waitForExistence(timeout: 10),
            "完成首次引导后，TermiPad 应显示“发现工具”按钮。"
        )
        XCTAssertTrue(
            element("language-segmented-control").waitForExistence(timeout: 5),
            "TermiPad 应显示中英文分段切换控件。"
        )
        XCTAssertTrue(
            element("appearance-segmented-control").waitForExistence(timeout: 5),
            "TermiPad 应显示三档外观分段切换控件。"
        )
        XCTAssertTrue(
            element("sidebar-settings").waitForExistence(timeout: 5),
            "TermiPad 应在左边栏提供常驻设置入口。"
        )
        XCTAssertTrue(
            element("sidebar-favorites").waitForExistence(timeout: 5),
            "TermiPad 应在左边栏提供收藏入口。"
        )
        XCTAssertTrue(
            element("sidebar-recent").waitForExistence(timeout: 5),
            "TermiPad 应在左边栏提供最近使用入口。"
        )

        attachScreenshot(named: "termipad-library")
    }

    func testDiscoveryPreviewIsDisabledByDefault() throws {
        launchApp()
        completeOnboarding()

        let discoverySidebarItem = element("sidebar-discovery-preview")
        XCTAssertTrue(
            discoverySidebarItem.waitForExistence(timeout: 5),
            "TermiPad 应在侧边栏提供项目发现预览入口。"
        )
        discoverySidebarItem.click()

        XCTAssertTrue(
            element("discovery-preview").waitForExistence(timeout: 5),
            "项目发现预览应显示独立页面，而非混入候选收件箱。"
        )
        // macOS 会折叠 ContentUnavailableView 的内部标识；以页面存在且没有刷新控件作为可观察的默认关闭证据。
        XCTAssertFalse(
            element("discovery-refresh").exists,
            "默认关闭的项目发现预览不应显示或触发刷新操作。"
        )

        attachScreenshot(named: "termipad-discovery-preview-disabled")
    }

    func testInstallEnvironmentRequiresUserAction() throws {
        launchApp()
        completeOnboarding()

        let installEnvironmentSidebarItem = element("sidebar-install-environment")
        XCTAssertTrue(
            installEnvironmentSidebarItem.waitForExistence(timeout: 5),
            "TermiPad 应在侧边栏提供独立的安装审查与环境报告入口。"
        )
        installEnvironmentSidebarItem.click()

        XCTAssertTrue(
            element("install-environment").waitForExistence(timeout: 5),
            "安装审查与环境报告应显示独立页面，而非混入工具启动界面。"
        )
        XCTAssertTrue(
            element("environment-report-check").waitForExistence(timeout: 5),
            "环境报告必须提供由用户主动触发的检查操作。"
        )
        XCTAssertFalse(
            element("install-plan-review").exists,
            "初始状态不应自动打开安装计划审查或交接任何命令。"
        )

        attachScreenshot(named: "termipad-install-environment-idle")
    }

    func testTaskWorkbenchShowsLocalExecutionBoundary() throws {
        launchApp()
        completeOnboarding()

        let taskWorkbenchSidebarItem = element("sidebar-task-workbench")
        XCTAssertTrue(
            taskWorkbenchSidebarItem.waitForExistence(timeout: 5),
            "TermiPad 应在侧边栏提供独立的本地任务工作台入口。"
        )
        taskWorkbenchSidebarItem.click()

        XCTAssertTrue(
            element("task-policy-workbench").waitForExistence(timeout: 5),
            "本地任务策略应显示独立工作台，而不混入工具终端启动界面。"
        )
        XCTAssertTrue(
            element("task-policy-boundary").waitForExistence(timeout: 5),
            "任务工作台应明确显示受限本地执行边界。"
        )
        XCTAssertTrue(
            element("task-mcp-local-section").waitForExistence(timeout: 5),
            "任务工作台应显示默认关闭的本机 MCP 许可说明，而不自动启动任何本机客户端。"
        )
        XCTAssertTrue(
            element("task-mcp-toggle").exists,
            "用户应能在 Mac 本机明确选择是否允许受限 MCP 提出待审阅任务。"
        )
        XCTAssertTrue(
            element("task-policy-auto-save-status").waitForExistence(timeout: 5),
            "任务工作台应说明本地设置会自动保存，避免用户误以为还需要全局保存按钮。"
        )
        XCTAssertTrue(
            element("task-mcp-persistence-status").waitForExistence(timeout: 5),
            "本机 MCP 开关应显示已自动保存的当前启用状态。"
        )
        XCTAssertFalse(
            element("discover-tools-button").exists,
            "任务工作台不应显示工具扫描操作，也不应暴露远程终端入口。"
        )

        attachScreenshot(named: "termipad-task-execution-workbench")
    }

    func testRecoveryLaunchOffersBackupImport() throws {
        launchApp(forceRecovery: true)

        XCTAssertTrue(
            element("data-recovery-screen").waitForExistence(timeout: 10),
            "强制恢复模式应显示受控数据恢复页面。"
        )
        XCTAssertTrue(
            element("data-recovery-import-backup").waitForExistence(timeout: 5),
            "默认数据容器无法打开时，恢复模式应提供用户主动导入 JSON 备份的入口。"
        )
        XCTAssertFalse(
            element("discover-tools-button").exists,
            "恢复模式不应假装默认工具库可用。"
        )

        attachScreenshot(named: "termipad-data-recovery")
    }

    func testSettingsLaunchShowsSharedPreferences() throws {
        launchApp(openSettings: true)
        completeOnboarding()

        XCTAssertTrue(
            element("settings-terminal-picker").waitForExistence(timeout: 10),
            "设置启动场景应展示默认终端偏好。"
        )
        XCTAssertTrue(
            element("settings-export-backup").waitForExistence(timeout: 5),
            "设置启动场景应展示备份导出操作。"
        )
        XCTAssertTrue(
            element("settings-export-diagnostics").waitForExistence(timeout: 5),
            "设置启动场景应展示用户主动导出的隐私化诊断包入口。"
        )
        XCTAssertTrue(
            element("settings-update-check-enabled").waitForExistence(timeout: 5),
            "设置启动场景应展示默认关闭的手动更新检查开关。"
        )
        XCTAssertFalse(
            element("discover-tools-button").exists,
            "设置页不应显示只属于工具库的“发现工具”操作。"
        )

        attachScreenshot(named: "termipad-settings")
    }

    private func launchApp(openSettings: Bool = false, forceRecovery: Bool = false) {
        app = XCUIApplication(bundleIdentifier: "com.termipad.app")
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["TERMIPAD_UI_TEST_MODE"] = "1"
        if openSettings {
            app.launchEnvironment["TERMIPAD_UI_TEST_OPEN_SETTINGS"] = "1"
        }
        if forceRecovery {
            app.launchEnvironment["TERMIPAD_UI_TEST_FORCE_RECOVERY"] = "1"
        }
        app.launch()
        let reachedForeground = app.wait(for: .runningForeground, timeout: 10)
        ensureMainWindow()
        let hasAccessibleMainWindow = app.windows.firstMatch.exists
        XCTAssertTrue(
            reachedForeground || hasAccessibleMainWindow,
            "TermiPad 未能在 10 秒内进入前台或呈现可访问的主窗口。当前 UI 层级：\n\(app.debugDescription)"
        )
        attachTextDiagnostic(
            named: "termipad-launch-state",
            text: "bundleIdentifier=com.termipad.app\nstate=\(app.state.rawValue)\nreachedForeground=\(reachedForeground)\nhasAccessibleMainWindow=\(hasAccessibleMainWindow)\n\(app.debugDescription)"
        )
    }

    private func ensureMainWindow() {
        let mainWindow = app.windows.firstMatch
        if !mainWindow.waitForExistence(timeout: 3) {
            let newWindow = app.menuBars.menuItems["New Window"]
            XCTAssertTrue(
                newWindow.waitForExistence(timeout: 5),
                "TermiPad 未恢复主窗口时，应用菜单应提供 New Window。"
            )
            newWindow.click()
        }
        XCTAssertTrue(
            mainWindow.waitForExistence(timeout: 10),
            "TermiPad 在 UI 测试中应呈现可访问的主窗口。"
        )
    }

    private func completeOnboarding() {
        XCTAssertTrue(
            element("onboarding-sheet").waitForExistence(timeout: 10),
            "TermiPad 首次启动应显示边界说明。"
        )
        let onboardingFinish = element("onboarding-finish")
        XCTAssertTrue(
            onboardingFinish.waitForExistence(timeout: 5),
            "TermiPad 首次启动应显示边界说明并允许用户确认。"
        )
        onboardingFinish.click()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func attachTextDiagnostic(named name: String, text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
