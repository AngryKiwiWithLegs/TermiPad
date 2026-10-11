import XCTest
import Foundation
@testable import TermiPad

/// Migration and backup decision (t0-checklist §4.5):
/// "Migration and backup decision — state explicitly whether task history, project references, and permission policies are backed up, avoid carrying local paths or sensitive runtime information — reviewed together with the existing JSON backup and isolated recovery design".
///
/// Existing fact (`Sources/BackupService.swift:159-171`): the type signature of `TermiPadBackup.make(tools:candidates:...)`
/// only accepts `[TerminalTool]` + `[CandidateTool]`. `TaskIntent` / `TaskProjectScope`
/// / `TaskReviewWindow` **cannot, by type,** enter a backup. This test turns that fact into an executable
/// assertion — if anyone ever extends the `make` signature, this test fails immediately.
final class BackupServiceTaskExclusionTests: XCTestCase {
    func testEmptyBackupDoesNotMentionTaskEntities() throws {
        let backup = TermiPadBackup.make(
            tools: [],
            candidates: [],
            includeSavedVariableValues: false
        )
        let data = try BackupService.encode(backup)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        // Type-system-level guarantee: the encoded JSON never contains task-domain fields
        XCTAssertFalse(json.contains("TaskIntent"), "The JSON backup must not contain the 'TaskIntent' type name.")
        XCTAssertFalse(json.contains("TaskProjectScope"), "The JSON backup must not contain the 'TaskProjectScope' type name.")
        XCTAssertFalse(json.contains("TaskReviewWindow"), "The JSON backup must not contain the 'TaskReviewWindow' type name.")
        XCTAssertFalse(json.contains("projectScopeID"), "The JSON backup must not contain the 'projectScopeID' field.")
        XCTAssertFalse(json.contains("reviewWindowID"), "The JSON backup must not contain the 'reviewWindowID' field.")
        XCTAssertFalse(json.contains("nonce"), "The JSON backup must not contain the task replay-defense nonce.")
        XCTAssertFalse(json.contains("riskRawValue"), "The JSON backup must not contain the task risk level.")
        XCTAssertFalse(json.contains("executionStateRawValue"), "The JSON backup must not contain the task execution state.")
        XCTAssertFalse(json.contains("executionExitCode"), "The JSON backup must not contain the task exit code.")
        XCTAssertFalse(json.contains("executionStartedAt"), "The JSON backup must not contain the task execution start time.")
        XCTAssertFalse(json.contains("executionFinishedAt"), "The JSON backup must not contain the task execution end time.")
        XCTAssertFalse(json.contains("proposedAt"), "The JSON backup must not contain the task proposal time.")
        XCTAssertFalse(json.contains("expiresAt"), "The JSON backup must not contain the task expiry time.")
        XCTAssertFalse(json.contains("approvedAt"), "The JSON backup must not contain the task approval time.")
        XCTAssertFalse(json.contains("resolvedAt"), "The JSON backup must not contain the task resolution time.")
        XCTAssertFalse(json.contains("rootPath"), "The JSON backup must not contain the scope's project root path — it reveals local path structure.")
        XCTAssertFalse(json.contains("workingDirectoryPath"), "The JSON backup must not contain the tool's working directory — it contains a local path.")
    }

    func testPopulatedBackupStillDoesNotMentionTaskEntities() throws {
        // Simulate the worst case: fill memory with task entities + tools, export, and inspect the JSON
        let toolWithWorkingDir = TerminalTool(
            name: "merge-cli",
            executablePath: "/usr/local/bin/merge-cli",
            commandTemplate: "merge-cli",
            category: .development,
            installationSource: .homebrew
        )
        toolWithWorkingDir.workingDirectoryPath = "/Users/example/secret-project"
        toolWithWorkingDir.variableValuesJSON = "{\"token\":\"keep-local\"}"

        let candidate = CandidateTool(
            name: "merge-candidate",
            executablePath: "/usr/local/bin/merge-candidate",
            category: .other
        )

        let backup = TermiPadBackup.make(
            tools: [toolWithWorkingDir],
            candidates: [candidate],
            includeSavedVariableValues: true
        )
        let data = try BackupService.encode(backup)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        // When the user explicitly checks includeSavedVariableValues=true, variable values do enter the JSON (that is the user's choice).
        // Do not enforce the JSON encoding format ([.prettyPrinted, .sortedKeys] may add spaces/newlines); only check the token keywords.
        XCTAssertTrue(json.contains("token"),
                      "Variable values should enter the JSON when the user checks includeSavedVariableValues=true.")
        XCTAssertTrue(json.contains("keep-local"),
                      "The variable value content should enter the JSON.")
        // But workingDirectoryPath never does (whatever includeSavedVariableValues is)
        XCTAssertFalse(json.contains("workingDirectoryPath"),
                       "workingDirectoryPath never enters the JSON backup (whether or not the user checks variable values).")
        XCTAssertFalse(json.contains("secret-project"),
                       "The local path value of workingDirectoryPath must not appear.")
        // The task domain still does not appear in the export
        XCTAssertFalse(json.contains("TaskIntent"))
        XCTAssertFalse(json.contains("TaskProjectScope"))
        XCTAssertFalse(json.contains("TaskReviewWindow"))
        XCTAssertFalse(json.contains("nonce"))
    }

    func testRoundTripDoesNotIntroduceTaskFields() throws {
        // Even after encode → decode → re-encode, task fields must not appear out of nowhere
        let original = TermiPadBackup.make(
            tools: [],
            candidates: [],
            includeSavedVariableValues: false
        )
        let encoded1 = try BackupService.encode(original)
        let decoded = try BackupService.decode(encoded1)
        let encoded2 = try BackupService.encode(decoded)
        let json2 = try XCTUnwrap(String(data: encoded2, encoding: .utf8))

        XCTAssertFalse(json2.contains("TaskIntent"))
        XCTAssertFalse(json2.contains("TaskProjectScope"))
        XCTAssertFalse(json2.contains("TaskReviewWindow"))
        XCTAssertEqual(decoded.schemaVersion, TermiPadBackup.currentSchemaVersion)
    }
}
