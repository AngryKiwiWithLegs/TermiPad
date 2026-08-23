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
        let title = app.staticTexts["app-title"]
        XCTAssertTrue(
            title.waitForExistence(timeout: 10),
            "TermiPad 应显示应用标题。"
        )

        let discoveryButton = app.buttons["discover-tools-button"]
        XCTAssertTrue(
            discoveryButton.exists,
            "TermiPad 应显示“发现工具”按钮。"
        )

        XCTAssertTrue(
            app.segmentedControls["language-segmented-control"].exists,
            "TermiPad 应显示中英文分段切换控件。"
        )
        XCTAssertTrue(
            app.segmentedControls["appearance-segmented-control"].exists,
            "TermiPad 应显示三档外观分段切换控件。"
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
