import XCTest

final class TermiPadUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app?.terminate()
    }

    func testLibraryLaunchShowsPrimaryControls() throws {
        launchApp()
        completeOnboarding()

        let discoveryButton = app.buttons["discover-tools-button"]
        XCTAssertTrue(
            discoveryButton.waitForExistence(timeout: 10),
            "完成首次引导后，TermiPad 应显示“发现工具”按钮。"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["language-segmented-control"].waitForExistence(timeout: 5),
            "TermiPad 应显示中英文分段切换控件。"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["appearance-segmented-control"].waitForExistence(timeout: 5),
            "TermiPad 应显示三档外观分段切换控件。"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["sidebar-settings"].waitForExistence(timeout: 5),
            "TermiPad 应在左边栏提供常驻设置入口。"
        )

        attachScreenshot(named: "termipad-library")
    }

    func testSettingsLaunchShowsSharedPreferences() throws {
        launchApp(openSettings: true)
        completeOnboarding()

        XCTAssertTrue(
            app.descendants(matching: .any)["settings-terminal-picker"].waitForExistence(timeout: 10),
            "设置启动场景应展示默认终端偏好。"
        )
        XCTAssertTrue(
            app.buttons["settings-export-backup"].waitForExistence(timeout: 5),
            "设置启动场景应展示备份导出操作。"
        )
        XCTAssertFalse(
            app.buttons["discover-tools-button"].exists,
            "设置页不应显示只属于工具库的“发现工具”操作。"
        )

        attachScreenshot(named: "termipad-settings")
    }

    private func launchApp(openSettings: Bool = false) {
        app = XCUIApplication()
        app.launchEnvironment["TERMIPAD_UI_TEST_MODE"] = "1"
        if openSettings {
            app.launchEnvironment["TERMIPAD_UI_TEST_OPEN_SETTINGS"] = "1"
        }
        app.launch()
    }

    private func completeOnboarding() {
        let onboardingFinish = app.buttons["onboarding-finish"]
        XCTAssertTrue(
            onboardingFinish.waitForExistence(timeout: 10),
            "TermiPad 首次启动应显示边界说明并允许用户确认。"
        )
        onboardingFinish.click()
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
