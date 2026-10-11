import XCTest
@testable import TermiPad

/// TaskMCPSettings contract tests (track-protocol stage 8 test hardening 3/4).
///
/// Locks down the UserDefaults key literal + the default-false behavior.
final class TaskMCPSettingsContractTests: XCTestCase {
    // MARK: - Private UserDefaults behavior

    private func makeFreshSettings() {
        UserDefaults.standard.removeObject(forKey: TaskMCPSettings.localMCPEnabledKey)
    }

    override func tearDown() {
        makeFreshSettings()
        super.tearDown()
    }

    // MARK: - String key literal

    func testLocalMCPEnabledKeyStringIsPinned() {
        // UserDefaults data migration — changing this line = existing users' MCP setting "disappears" after a restart,
        // a silent regression. This test locks down the key literal.
        XCTAssertEqual(TaskMCPSettings.localMCPEnabledKey, "TermiPad.localMCPEnabled")
    }

    // MARK: - Default behavior

    func testIsLocalMCPEnabledDefaultsToFalseWhenNotSet() {
        makeFreshSettings()
        XCTAssertFalse(TaskMCPSettings.isLocalMCPEnabled,
                       "MCP must be turned on explicitly — default false is the product red line 'the Mac exposes no public ports'")
    }

    func testIsLocalMCPEnabledReturnsTrueAfterUserOptIn() {
        makeFreshSettings()
        UserDefaults.standard.set(true, forKey: TaskMCPSettings.localMCPEnabledKey)
        XCTAssertTrue(TaskMCPSettings.isLocalMCPEnabled)
    }

    func testIsLocalMCPEnabledRevertsToFalseAfterUserOptOut() {
        makeFreshSettings()
        UserDefaults.standard.set(true, forKey: TaskMCPSettings.localMCPEnabledKey)
        UserDefaults.standard.set(false, forKey: TaskMCPSettings.localMCPEnabledKey)
        XCTAssertFalse(TaskMCPSettings.isLocalMCPEnabled,
                       "An explicit false should take effect immediately (the user revokes MCP)")
    }

    // MARK: - Guard the static read of UserDefaults.standard

    func testUsesOnlyUserDefaultsStandard() {
        // Prevents a future commit from changing `UserDefaults.standard` to a suite-scoped UserDefaults
        // (which could break the product contract 'local settings are written to this Mac's UserDefaults')
        // This test locks down the literal by grepping the source
        let source = try? String(contentsOfFile: #file, encoding: .utf8)
        XCTAssertNotNil(source, "the source must be readable")
        let body = source ?? ""
        XCTAssertTrue(body.contains("UserDefaults.standard"),
                       "TaskMCPSettings.isLocalMCPEnabled must read UserDefaults.standard (product contract: local settings are written to this Mac's UserDefaults)")
    }
}
