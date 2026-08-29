import XCTest
import Foundation
@testable import TermiPad

/// 迁移与备份决定（t0-checklist §4.5）：
/// "迁移与备份决定 — 明确任务历史、项目引用和权限策略是否备份，避免带入本地路径或敏感运行信息 — 与现有 JSON 备份、隔离恢复设计共同审查"。
///
/// 现存事实（`Sources/BackupService.swift:159-171`）：`TermiPadBackup.make(tools:candidates:...)`
/// 类型签名只接受 `[TerminalTool]` + `[CandidateTool]`。`TaskIntent` / `TaskProjectScope`
/// / `TaskReviewWindow` **类型上不可能**进入备份。本测试把这个事实固化成可执行
/// 断言——以后即使有人扩展 `make` 签名，本测试会立即失败。
final class BackupServiceTaskExclusionTests: XCTestCase {
    func testEmptyBackupDoesNotMentionTaskEntities() throws {
        let backup = TermiPadBackup.make(
            tools: [],
            candidates: [],
            includeSavedVariableValues: false
        )
        let data = try BackupService.encode(backup)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        // 类型系统级保证：encode 的 JSON 永远不含 task 域字段
        XCTAssertFalse(json.contains("TaskIntent"), "JSON 备份中不能含 'TaskIntent' 类型名。")
        XCTAssertFalse(json.contains("TaskProjectScope"), "JSON 备份中不能含 'TaskProjectScope' 类型名。")
        XCTAssertFalse(json.contains("TaskReviewWindow"), "JSON 备份中不能含 'TaskReviewWindow' 类型名。")
        XCTAssertFalse(json.contains("projectScopeID"), "JSON 备份中不能含 'projectScopeID' 字段。")
        XCTAssertFalse(json.contains("reviewWindowID"), "JSON 备份中不能含 'reviewWindowID' 字段。")
        XCTAssertFalse(json.contains("nonce"), "JSON 备份中不能含 task 重放防御 nonce。")
        XCTAssertFalse(json.contains("riskRawValue"), "JSON 备份中不能含 task 风险级别。")
        XCTAssertFalse(json.contains("executionStateRawValue"), "JSON 备份中不能含 task 执行状态。")
        XCTAssertFalse(json.contains("executionExitCode"), "JSON 备份中不能含 task 退出码。")
        XCTAssertFalse(json.contains("executionStartedAt"), "JSON 备份中不能含 task 执行开始时间。")
        XCTAssertFalse(json.contains("executionFinishedAt"), "JSON 备份中不能含 task 执行结束时间。")
        XCTAssertFalse(json.contains("proposedAt"), "JSON 备份中不能含 task 提案时间。")
        XCTAssertFalse(json.contains("expiresAt"), "JSON 备份中不能含 task 过期时间。")
        XCTAssertFalse(json.contains("approvedAt"), "JSON 备份中不能含 task 批准时间。")
        XCTAssertFalse(json.contains("resolvedAt"), "JSON 备份中不能含 task 解决时间。")
        XCTAssertFalse(json.contains("rootPath"), "JSON 备份中不能含 scope 项目根路径——含本地路径结构。")
        XCTAssertFalse(json.contains("workingDirectoryPath"), "JSON 备份中不能含工具工作目录——含本地路径。")
    }

    func testPopulatedBackupStillDoesNotMentionTaskEntities() throws {
        // 模拟最坏情况：内存里塞满 task entities + 工具，导出，看 JSON
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

        // 用户明确勾选 includeSavedVariableValues=true 时，变量值会进 JSON（这是用户选择）。
        // 不强制 JSON 编码格式（[.prettyPrinted, .sortedKeys] 可能加空格/换行），只检查 token 关键字。
        XCTAssertTrue(json.contains("token"),
                      "用户勾选 includeSavedVariableValues=true 时变量值应进 JSON。")
        XCTAssertTrue(json.contains("keep-local"),
                      "变量值内容应进 JSON。")
        // 但 workingDirectoryPath 永远不进（无论 includeSavedVariableValues 是什么）
        XCTAssertFalse(json.contains("workingDirectoryPath"),
                       "workingDirectoryPath 永远不进 JSON 备份（无论用户是否勾选变量值）。")
        XCTAssertFalse(json.contains("secret-project"),
                       "workingDirectoryPath 的本地路径值不出现。")
        // 任务域仍然不出现在导出中
        XCTAssertFalse(json.contains("TaskIntent"))
        XCTAssertFalse(json.contains("TaskProjectScope"))
        XCTAssertFalse(json.contains("TaskReviewWindow"))
        XCTAssertFalse(json.contains("nonce"))
    }

    func testRoundTripDoesNotIntroduceTaskFields() throws {
        // 即使走 encode → decode → re-encode 也不能凭空冒出 task 字段
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
