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
        XCTAssertTrue(
            reachedForeground,
            "TermiPad 未能在 10 秒内进入前台。当前 UI 层级：\n\(app.debugDescription)"
        )
        ensureMainWindow()
        attachTextDiagnostic(
            named: "termipad-launch-state",
            text: "bundleIdentifier=com.termipad.app\nstate=\(app.state.rawValue)\n\(app.debugDescription)"
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
