import XCTest
@testable import TermiPad

/// ToolHealth unit tests (track-protocol stage 6 test hardening).
///
/// ToolHealth is the last gate before `LaunchpadView.requestLaunch` launches a tool:
///  1. checks whether the executable path still exists + is executable
///  2. decides whether launching is allowed (`.permitsLaunch`) + shows the matching error recovery copy
///
/// Any accidental change (weakening the permitsLaunch condition / breaking recoveryMessage) would bypass the launch check
/// or leave users unable to see how to fix it. These 4 cases lock down the current 4 states + the key computation.
final class ToolHealthTests: XCTestCase {
    func testAvailablePermitsLaunch() {
        XCTAssertTrue(ToolHealth.available.permitsLaunch)
    }

    func testNotInspectablePermitsLaunch() {
        // A relative path / not under an allowlisted absolute path: the OS cannot be checked, but it should not be blocked either.
        XCTAssertTrue(ToolHealth.notInspectable.permitsLaunch,
                      "Non-inspectable paths should be allowed — the OS reports its own error later.")
    }

    func testMissingDoesNotPermitLaunch() {
        XCTAssertFalse(ToolHealth.missing.permitsLaunch,
                       "A missing executable must be blocked — weakening this would launch a binary that does not exist.")
    }

    func testNotExecutableDoesNotPermitLaunch() {
        XCTAssertFalse(ToolHealth.notExecutable.permitsLaunch,
                       "Missing execute permission must be blocked — the launch would fail and waste the user's time.")
    }

    func testRecoveryMessagePointsToEditToolForMissingFile() {
        // The recovery copy for missing must **explicitly** point to the "Edit Tool" entry, otherwise the user does not know what to do.
        let zh = ToolHealth.missing.recoveryMessage(.simplifiedChinese)
        let en = ToolHealth.missing.recoveryMessage(.english)
        XCTAssertTrue(zh.contains("编辑工具") || zh.contains("工具库"),
                       "The Chinese recovery copy should point to Edit Tool / the library. got: \(zh)")
        XCTAssertTrue(en.contains("Edit Tool") || en.contains("Edit the tool"),
                       "English recovery should point to Edit Tool. got: \(en)")
    }

    func testRecoveryMessageEmptyForPassableStates() {
        // available / notInspectable can launch, so they should not show an error.
        XCTAssertEqual(ToolHealth.available.recoveryMessage(.simplifiedChinese), "")
        XCTAssertEqual(ToolHealth.available.recoveryMessage(.english), "")
        XCTAssertEqual(ToolHealth.notInspectable.recoveryMessage(.simplifiedChinese), "")
        XCTAssertEqual(ToolHealth.notInspectable.recoveryMessage(.english), "")
    }
}
