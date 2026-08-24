import XCTest

final class TermiPadUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["TERMIPAD_UI_TEST_MODE"] = "1"
        app.launch()
    }

    func testLaunchShowsPrimaryControls() throws {
        let onboardingFinish = app.buttons["onboarding-finish"]
        XCTAssertTrue(
            onboardingFinish.waitForExistence(timeout: 10),
            "TermiPad 首次启动应显示边界说明并允许用户确认。"
        )
        onboardingFinish.click()

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

        let settingsEntry = app.descendants(matching: .any)["sidebar-settings"]
        XCTAssertTrue(
            settingsEntry.waitForExistence(timeout: 5),
            "TermiPad 应在左边栏提供常驻设置入口。"
        )
        settingsEntry.click()
        XCTAssertTrue(
            app.descendants(matching: .any)["preferences-content"].waitForExistence(timeout: 5),
            "左边栏设置入口应展示与菜单栏共用的设置内容。"
        )

        attachScreenshot(named: "termipad-launch")
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
