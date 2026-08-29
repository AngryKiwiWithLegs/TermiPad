import XCTest
import Foundation
@testable import TermiPad

/// M0 移动端入口字段不进 JSON 备份（track-protocol stage 4.3）。
///
/// 对应 docs/m0-m1-mobile-entry-design.md §2.5 "6 字段永不出 JSON 备份"。
/// 镜像 commit 6b931c4 BackupServiceTaskExclusionTests 的模式——类型系统已保证
/// (`TermiPadBackup.make(tools:candidates:...)` 签名只接 TerminalTool 列表，
/// `ToolRecord.init` 显式字段赋值)，本测试把这条事实固化成可执行断言。
final class BackupServiceMobileFieldExclusionTests: XCTestCase {
    func testEmptyBackupDoesNotMentionMobileEntryFields() throws {
        let backup = TermiPadBackup.make(
            tools: [],
            candidates: [],
            includeSavedVariableValues: false
        )
        let data = try BackupService.encode(backup)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        // docs/m0-m1-mobile-entry-design.md §2.2 — 6 字段名
        XCTAssertFalse(json.contains("mobileDisplayName"), "JSON 备份中不能含 mobileDisplayName。")
        XCTAssertFalse(json.contains("mobileDescription"), "JSON 备份中不能含 mobileDescription。")
        XCTAssertFalse(json.contains("showInMobileEntry"), "JSON 备份中不能含 showInMobileEntry。")
        XCTAssertFalse(json.contains("allowMobileLaunchRequest"), "JSON 备份中不能含 allowMobileLaunchRequest。")
        XCTAssertFalse(json.contains("mobileLocalConfirmPolicy"), "JSON 备份中不能含 mobileLocalConfirmPolicy。")
        XCTAssertFalse(json.contains("revokeMobilePermissionAt"), "JSON 备份中不能含 revokeMobilePermissionAt。")
        // 枚举名 (MobileLocalConfirmPolicy) 本身也不该出现
        XCTAssertFalse(json.contains("MobileLocalConfirmPolicy"), "JSON 备份中不能含 MobileLocalConfirmPolicy 枚举名。")
    }

    func testPopulatedMobileToolStillDoesNotMentionMobileFields() throws {
        // 最坏情况：用户开了所有 mobile 字段，导出
        let tool = TerminalTool(
            name: "mobile-cli",
            executablePath: "/usr/local/bin/mobile-cli",
            commandTemplate: "mobile-cli --sync"
        )
        tool.mobileDisplayName = "项目同步"
        tool.mobileDescription = "运行 git pull --rebase"
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

        // 6 字段名不应出现
        XCTAssertFalse(json.contains("mobileDisplayName"))
        XCTAssertFalse(json.contains("mobileDescription"))
        XCTAssertFalse(json.contains("showInMobileEntry"))
        XCTAssertFalse(json.contains("allowMobileLaunchRequest"))
        XCTAssertFalse(json.contains("mobileLocalConfirmPolicy"))
        XCTAssertFalse(json.contains("revokeMobilePermissionAt"))
        // 中文 mobile 字段值也不应出现
        XCTAssertFalse(json.contains("项目同步"), "手机显示名中文值不出现在备份。")
        XCTAssertFalse(json.contains("git pull"), "手机说明中的命令相关文字不出现在备份。")
    }

    func testRoundTripDoesNotIntroduceMobileFields() throws {
        // encode → decode → re-encode 不应凭空冒出 mobile 字段
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
