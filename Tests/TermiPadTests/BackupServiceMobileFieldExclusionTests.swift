import XCTest
import Foundation
@testable import TermiPad

/// M0 mobile entry fields stay out of the JSON backup (track-protocol stage 4.3).
///
/// Corresponds to docs/m0-m1-mobile-entry-design.md §2.5 "the 6 fields never leave in a JSON backup".
/// Mirrors the pattern of BackupServiceTaskExclusionTests from commit 6b931c4 — the type system already guarantees it
/// (the `TermiPadBackup.make(tools:candidates:...)` signature only takes a list of TerminalTool, and
/// `ToolRecord.init` assigns fields explicitly); this test turns that fact into an executable assertion.
final class BackupServiceMobileFieldExclusionTests: XCTestCase {
    func testEmptyBackupDoesNotMentionMobileEntryFields() throws {
        let backup = TermiPadBackup.make(
            tools: [],
            candidates: [],
            includeSavedVariableValues: false
        )
        let data = try BackupService.encode(backup)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        // docs/m0-m1-mobile-entry-design.md §2.2 — the 6 field names
        XCTAssertFalse(json.contains("mobileDisplayName"), "The JSON backup must not contain mobileDisplayName.")
        XCTAssertFalse(json.contains("mobileDescription"), "The JSON backup must not contain mobileDescription.")
        XCTAssertFalse(json.contains("showInMobileEntry"), "The JSON backup must not contain showInMobileEntry.")
        XCTAssertFalse(json.contains("allowMobileLaunchRequest"), "The JSON backup must not contain allowMobileLaunchRequest.")
        XCTAssertFalse(json.contains("mobileLocalConfirmPolicy"), "The JSON backup must not contain mobileLocalConfirmPolicy.")
        XCTAssertFalse(json.contains("revokeMobilePermissionAt"), "The JSON backup must not contain revokeMobilePermissionAt.")
        // The enum name itself (MobileLocalConfirmPolicy) should not appear either
        XCTAssertFalse(json.contains("MobileLocalConfirmPolicy"), "The JSON backup must not contain the MobileLocalConfirmPolicy enum name.")
    }

    func testPopulatedMobileToolStillDoesNotMentionMobileFields() throws {
        // Worst case: the user turned on every mobile field, then exported
        let tool = TerminalTool(
            name: "mobile-cli",
            executablePath: "/usr/local/bin/mobile-cli",
            commandTemplate: "mobile-cli --sync"
        )
        tool.mobileDisplayName = "Project Sync"
        tool.mobileDescription = "Run git pull --rebase"
        tool.showInMobileEntry = true
        tool.allowMobileLaunchRequest = true
        tool.mobileLocalConfirmPolicy = .perSession
        tool.revokeMobilePermissionAt = Date(timeIntervalSince1970: 1_700_000_000)

        let backup = TermiPadBackup.make(
            tools: [tool],
            candidates: [],
            includeSavedVariableValues: false
        )
        let data = try BackupService.encode(backup)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        // The 6 field names should not appear
        XCTAssertFalse(json.contains("mobileDisplayName"))
        XCTAssertFalse(json.contains("mobileDescription"))
        XCTAssertFalse(json.contains("showInMobileEntry"))
        XCTAssertFalse(json.contains("allowMobileLaunchRequest"))
        XCTAssertFalse(json.contains("mobileLocalConfirmPolicy"))
        XCTAssertFalse(json.contains("revokeMobilePermissionAt"))
        // The mobile field values should not appear either
        XCTAssertFalse(json.contains("Project Sync"), "The mobile display name value must not appear in the backup.")
        XCTAssertFalse(json.contains("git pull"), "Command-related text from the mobile description must not appear in the backup.")
    }

    func testRoundTripDoesNotIntroduceMobileFields() throws {
        // encode → decode → re-encode should not make mobile fields appear out of nowhere
        let original = TermiPadBackup.make(
            tools: [],
            candidates: [],
            includeSavedVariableValues: false
        )
        let encoded1 = try BackupService.encode(original)
        let decoded = try BackupService.decode(encoded1)
        let encoded2 = try BackupService.encode(decoded)
        let json2 = try XCTUnwrap(String(data: encoded2, encoding: .utf8))

        XCTAssertFalse(json2.contains("mobileDisplayName"))
        XCTAssertFalse(json2.contains("mobileDescription"))
        XCTAssertFalse(json2.contains("showInMobileEntry"))
        XCTAssertFalse(json2.contains("allowMobileLaunchRequest"))
        XCTAssertFalse(json2.contains("mobileLocalConfirmPolicy"))
        XCTAssertFalse(json2.contains("revokeMobilePermissionAt"))
        XCTAssertEqual(decoded.schemaVersion, TermiPadBackup.currentSchemaVersion)
    }
}
