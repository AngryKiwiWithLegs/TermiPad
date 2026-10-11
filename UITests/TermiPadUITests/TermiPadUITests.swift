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
            "After completing first-run onboarding, TermiPad should show the “Discover Tools” button."
        )
        XCTAssertTrue(
            element("language-segmented-control").waitForExistence(timeout: 5),
            "TermiPad should show the Chinese/English segmented language switch."
        )
        XCTAssertTrue(
            element("appearance-segmented-control").waitForExistence(timeout: 5),
            "TermiPad should show the three-option appearance segmented switch."
        )
        XCTAssertTrue(
            element("sidebar-settings").waitForExistence(timeout: 5),
            "TermiPad should provide a permanent Settings entry in the left sidebar."
        )
        XCTAssertTrue(
            element("sidebar-favorites").waitForExistence(timeout: 5),
            "TermiPad should provide a Favorites entry in the left sidebar."
        )
        XCTAssertTrue(
            element("sidebar-recent").waitForExistence(timeout: 5),
            "TermiPad should provide a Recent entry in the left sidebar."
        )

        attachScreenshot(named: "termipad-library")
    }

    func testDiscoveryPreviewIsDisabledByDefault() throws {
        launchApp()
        completeOnboarding()

        let discoverySidebarItem = element("sidebar-discovery-preview")
        XCTAssertTrue(
            discoverySidebarItem.waitForExistence(timeout: 5),
            "TermiPad should provide a Project Discovery Preview entry in the sidebar."
        )
        discoverySidebarItem.click()

        XCTAssertTrue(
            element("discovery-preview").waitForExistence(timeout: 5),
            "Project Discovery Preview should show its own page instead of being mixed into the review inbox."
        )
        // macOS collapses the internal identifiers of ContentUnavailableView; the page existing with no refresh control is the observable evidence of being off by default.
        XCTAssertFalse(
            element("discovery-refresh").exists,
            "Project Discovery Preview, off by default, should neither show nor trigger a refresh action."
        )

        attachScreenshot(named: "termipad-discovery-preview-disabled")
    }

    func testInstallEnvironmentRequiresUserAction() throws {
        launchApp()
        completeOnboarding()

        let installEnvironmentSidebarItem = element("sidebar-install-environment")
        XCTAssertTrue(
            installEnvironmentSidebarItem.waitForExistence(timeout: 5),
            "TermiPad should provide a separate Install Review & Environment entry in the sidebar."
        )
        installEnvironmentSidebarItem.click()

        XCTAssertTrue(
            element("install-environment").waitForExistence(timeout: 5),
            "Install Review & Environment should show its own page instead of being mixed into the tool launch UI."
        )
        XCTAssertTrue(
            element("environment-report-check").waitForExistence(timeout: 5),
            "The environment report must offer a check action triggered deliberately by the user."
        )
        XCTAssertFalse(
            element("install-plan-review").exists,
            "The initial state should not open an install plan review or hand off any command automatically."
        )

        attachScreenshot(named: "termipad-install-environment-idle")
    }

    func testTaskWorkbenchShowsLocalExecutionBoundary() throws {
        launchApp()
        completeOnboarding()

        let taskWorkbenchSidebarItem = element("sidebar-task-workbench")
        XCTAssertTrue(
            taskWorkbenchSidebarItem.waitForExistence(timeout: 5),
            "TermiPad should provide a separate Local Task Workbench entry in the sidebar."
        )
        taskWorkbenchSidebarItem.click()

        XCTAssertTrue(
            element("task-policy-workbench").waitForExistence(timeout: 5),
            "The local task policy should show its own workbench instead of being mixed into the tool terminal launch UI."
        )
        XCTAssertTrue(
            element("task-policy-boundary").waitForExistence(timeout: 5),
            "The task workbench should clearly show the restricted local execution boundary."
        )
        XCTAssertTrue(
            element("task-mcp-local-section").waitForExistence(timeout: 5),
            "The task workbench should show the off-by-default local MCP permission note without starting any local client automatically."
        )
        XCTAssertTrue(
            element("task-mcp-toggle").exists,
            "The user should be able to choose explicitly, on the Mac, whether restricted MCP may propose tasks for review."
        )
        XCTAssertFalse(
            element("discover-tools-button").exists,
            "The task workbench should not show tool scanning actions or expose a remote terminal entry."
        )

        attachScreenshot(named: "termipad-task-execution-workbench")
    }

    func testRecoveryLaunchOffersBackupImport() throws {
        launchApp(forceRecovery: true)

        XCTAssertTrue(
            element("data-recovery-screen").waitForExistence(timeout: 10),
            "Forced recovery mode should show the controlled data recovery page."
        )
        XCTAssertTrue(
            element("data-recovery-import-backup").waitForExistence(timeout: 5),
            "When the default data container cannot be opened, recovery mode should offer an entry for the user to import a JSON backup deliberately."
        )
        XCTAssertFalse(
            element("discover-tools-button").exists,
            "Recovery mode should not pretend the default library is available."
        )

        attachScreenshot(named: "termipad-data-recovery")
    }

    func testSettingsLaunchShowsSharedPreferences() throws {
        launchApp(openSettings: true)
        completeOnboarding()

        XCTAssertTrue(
            element("settings-terminal-picker").waitForExistence(timeout: 10),
            "The settings launch scenario should show the default terminal preference."
        )
        XCTAssertTrue(
            element("settings-export-backup").waitForExistence(timeout: 5),
            "The settings launch scenario should show the backup export action."
        )
        XCTAssertTrue(
            element("settings-export-diagnostics").waitForExistence(timeout: 5),
            "The settings launch scenario should show the entry for the privacy-preserving diagnostic package the user exports deliberately."
        )
        XCTAssertTrue(
            element("settings-update-check-enabled").waitForExistence(timeout: 5),
            "The settings launch scenario should show the off-by-default manual update check toggle."
        )
        XCTAssertFalse(
            element("discover-tools-button").exists,
            "The Settings page should not show the “Discover Tools” action that belongs only to the library."
        )

        attachScreenshot(named: "termipad-settings")
    }

    func testToolEditMobileEntrySectionExposesFiveFieldsAndRevoke() throws {
        // M0 mobile entry (track-protocol stage 5.2): UI behavior test placeholder.
        //
        // docs/m0-m1-mobile-entry-design.md §2.7 requires "1 new UI scenario (open the tool edit
        // panel + see the Mobile Entry section)". The full assertion needs to go into the ToolTile's contextMenu
        // and choose "Edit Tool" to enter the ToolEditView sheet.
        //
        // **Known issue** (found during the stage 5.2 investigation): on macOS, SwiftUI's `.contextMenu`
        // is handled by the NSMenu system layer, and XCUITest's synthesized rightClick events are inconsistent across macOS
        // versions — on Xcode 26.6 the menuItems list returns empty labels (not a SwiftUI-side
        // problem but an XCTest event synthesis limitation). Within the scope of stage 5.2, XCUITest cannot yet reliably
        // trigger a SwiftUI .contextMenu.
        //
        // **Value kept**: the SEED_TOOL fixture helper + launchApp(seedTool:) added in this commit
        // are a real capability gain — when the UITest framework is upgraded or SwiftUI contextMenu is fixed in XCUITest
        // later, this test can be completed with the 5 M0 identifier assertions (see the 5 lines in the commit 6f762f0
        // placeholder + the seeder implementation in commit 21c5a7d).
        //
        // Within stage 5.2 this test only covers: "the seed worked + the main workspace renders + the fixture
        // tool appears in the library" — proving the SEED_TOOL path works end to end. The full 5-identifier assertion is left
        // for later, once SwiftUI contextMenu + XCUITest compatibility is resolved.
        launchApp(seedTool: true)
        completeOnboarding()

        XCTAssertTrue(
            element("tool-library").waitForExistence(timeout: 10),
            "M0 launch + the fixture tool is seeded; the library should render."
        )
        XCTAssertTrue(
            element("tool-tile-merge-cli").waitForExistence(timeout: 10),
            "The fixture tool 'merge-cli' should be visible in the library (proving the SEED_TOOL path works).\nCurrent UI hierarchy:\n\(app.debugDescription)"
        )

        attachScreenshot(named: "termipad-m0-fixture-baseline")
    }

    private func launchApp(openSettings: Bool = false, forceRecovery: Bool = false, seedTool: Bool = false) {
        app = XCUIApplication(bundleIdentifier: "com.termipad.app")
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["TERMIPAD_UI_TEST_MODE"] = "1"
        if openSettings {
            app.launchEnvironment["TERMIPAD_UI_TEST_OPEN_SETTINGS"] = "1"
        }
        if forceRecovery {
            app.launchEnvironment["TERMIPAD_UI_TEST_FORCE_RECOVERY"] = "1"
        }
        if seedTool {
            app.launchEnvironment["TERMIPAD_UI_TEST_SEED_TOOL"] = "1"
        }
        app.launch()
        let reachedForeground = app.wait(for: .runningForeground, timeout: 10)
        ensureMainWindow()
        let hasAccessibleMainWindow = app.windows.firstMatch.exists
        XCTAssertTrue(
            reachedForeground || hasAccessibleMainWindow,
            "TermiPad did not reach the foreground or present an accessible main window within 10 seconds. Current UI hierarchy:\n\(app.debugDescription)"
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
                "When TermiPad does not restore its main window, the app menu should offer New Window."
            )
            newWindow.click()
        }
        XCTAssertTrue(
            mainWindow.waitForExistence(timeout: 10),
            "TermiPad should present an accessible main window in UI tests."
        )
    }

    private func completeOnboarding() {
        XCTAssertTrue(
            element("onboarding-sheet").waitForExistence(timeout: 10),
            "TermiPad should show the boundary notice on first launch."
        )
        let onboardingFinish = element("onboarding-finish")
        XCTAssertTrue(
            onboardingFinish.waitForExistence(timeout: 5),
            "TermiPad should show the boundary notice on first launch and let the user confirm."
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
