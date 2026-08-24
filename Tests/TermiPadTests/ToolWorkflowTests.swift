import XCTest
@testable import TermiPad

final class ToolWorkflowTests: XCTestCase {
    func testTemplateExtractsUniqueVariablesInOrder() {
        let template = "claude --model {{model}} --path {{path}} {{model}}"
        XCTAssertEqual(CommandTemplate.variables(in: template), ["model", "path"])
    }

    func testTemplateRefusesMissingVariables() {
        XCTAssertThrowsError(try CommandTemplate.render(template: "tool {{required}}", values: [:])) { error in
            XCTAssertEqual(error as? CommandTemplateError, .missingValues(["required"]))
        }
    }

    func testTemplateEscapesShellVariableValues() throws {
        let command = try CommandTemplate.render(
            template: "tool --prompt {{prompt}}",
            values: ["prompt": "it's ready"]
        )
        XCTAssertEqual(command, "tool --prompt 'it'\u{22}'\u{22}'s ready'")
    }

    func testDefaultTerminalPreferenceExists() {
        XCTAssertEqual(TerminalTarget(rawValue: "Terminal.app"), .systemTerminal)
        XCTAssertEqual(TerminalTarget(rawValue: "仅复制命令"), .copyOnly)
    }

    func testScannerExcludesSystemCommandsAndKeepsInteractiveTools() {
        XCTAssertTrue(ToolScanner.shouldExclude(commandName: "curl"))
        XCTAssertTrue(ToolScanner.shouldExclude(commandName: "tool.py"))
        XCTAssertFalse(ToolScanner.shouldExclude(commandName: "claude"))
        XCTAssertFalse(ToolScanner.shouldExclude(commandName: "yt-dlp"))
    }

    func testTemplateRendersVariableWithWhitespaceInsideBraces() throws {
        let command = try CommandTemplate.render(template: "tool {{ model }}", values: ["model": "sonnet"])
        XCTAssertEqual(command, "tool 'sonnet'")
    }

    func testLanguageAndAppearancePreferencesHaveStableValues() {
        XCTAssertEqual(AppLanguage(rawValue: "zh-Hans"), .simplifiedChinese)
        XCTAssertEqual(AppLanguage(rawValue: "en"), .english)
        XCTAssertEqual(AppAppearance.system.colorScheme, nil)
        XCTAssertEqual(AppAppearance.light.colorScheme, .light)
        XCTAssertEqual(AppAppearance.dark.colorScheme, .dark)
    }

    func testCoreCopyAndCategoryAreLocalized() {
        XCTAssertEqual(AppCopy.text("discover", language: .simplifiedChinese), "发现工具")
        XCTAssertEqual(AppCopy.text("discover", language: .english), "Discover Tools")
        XCTAssertEqual(ToolCategory.development.displayName(.english), "Development")
        XCTAssertEqual(TerminalTarget.copyOnly.displayName(.english), "Copy Command Only")
    }

    func testAppearanceOptionsExposeNativeLabelsAndSymbols() {
        XCTAssertEqual(AppAppearance.system.displayName(.english), "System")
        XCTAssertEqual(AppAppearance.light.displayName(.simplifiedChinese), "浅色")
        XCTAssertEqual(AppAppearance.dark.symbol, "moon.stars")
    }

    func testPlaceholderDescriptionsNeverBecomeHoverCopy() {
        let tool = TerminalTool(
            name: "example-cli",
            executablePath: "/usr/local/bin/example-cli",
            commandTemplate: "example-cli",
            toolDescription: "正在尝试 AI 增强…",
            category: .development
        )

        let content = ToolDescriptionPresentation.hoverContent(for: tool, language: .simplifiedChinese)
        XCTAssertFalse(content.purpose.contains("正在尝试 AI 增强"))
        XCTAssertTrue(content.purpose.contains("开发"))
        XCTAssertTrue(content.gettingStarted.contains("编辑工具"))
    }

    func testKnownToolGetsFriendlyPurposeAndGettingStartedCopy() {
        let tool = TerminalTool(
            name: "claude",
            executablePath: "/usr/local/bin/claude",
            commandTemplate: "claude",
            toolDescription: "",
            category: .ai
        )

        let content = ToolDescriptionPresentation.hoverContent(for: tool, language: .simplifiedChinese)
        XCTAssertTrue(content.purpose.contains("Claude"))
        XCTAssertTrue(content.gettingStarted.contains("描述"))
        XCTAssertTrue(content.accessibilitySummary(language: .simplifiedChinese).contains("如何开始"))
    }

    func testSavedDescriptionIsThePurposeAndUsesFriendlyGettingStartedCopy() {
        let tool = TerminalTool(
            name: "example-cli",
            executablePath: "/usr/local/bin/example-cli",
            commandTemplate: "example-cli --interactive",
            toolDescription: "A compiler for source code.",
            category: .development
        )

        let content = ToolDescriptionPresentation.hoverContent(for: tool, language: .english)
        XCTAssertEqual(content.purpose, "A compiler for source code.")
        XCTAssertTrue(content.gettingStarted.contains("Edit Tool"))
        XCTAssertFalse(ToolDescriptionPresentation.isPlaceholder("A compiler for source code."))
    }
}


extension ToolWorkflowTests {
    func testBackupRoundTripKeepsSchemaAndPrivacyChoice() throws {
        let backup = TermiPadBackup(
            schemaVersion: TermiPadBackup.currentSchemaVersion,
            exportedAt: Date(timeIntervalSince1970: 1_700_000_000),
            includesSavedVariableValues: false,
            tools: [],
            candidates: []
        )

        let decoded = try BackupService.decode(BackupService.encode(backup))
        XCTAssertEqual(decoded.schemaVersion, TermiPadBackup.currentSchemaVersion)
        XCTAssertFalse(decoded.includesSavedVariableValues)
        XCTAssertTrue(decoded.tools.isEmpty)
        XCTAssertTrue(decoded.candidates.isEmpty)
    }

    func testBackupRejectsUnsupportedSchema() throws {
        let backup = TermiPadBackup(
            schemaVersion: TermiPadBackup.currentSchemaVersion + 1,
            exportedAt: Date(),
            includesSavedVariableValues: false,
            tools: [],
            candidates: []
        )

        XCTAssertThrowsError(try BackupService.decode(BackupService.encode(backup))) { error in
            XCTAssertEqual(error as? BackupServiceError, .unsupportedSchema(TermiPadBackup.currentSchemaVersion + 1))
        }
    }
}
