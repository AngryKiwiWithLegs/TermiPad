import XCTest
import SwiftData
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


extension ToolWorkflowTests {
    func testBackupDoesNotExportLegacyRemoteIconURL() {
        let tool = TerminalTool(
            name: "legacy-cli",
            executablePath: "/opt/homebrew/bin/legacy-cli",
            commandTemplate: "legacy-cli",
            category: .development
        )
        tool.iconURLString = "https://avatars.githubusercontent.com/u/1"

        let backup = TermiPadBackup.make(
            tools: [tool],
            candidates: [],
            includeSavedVariableValues: false
        )

        XCTAssertNil(backup.tools.first?.iconURLString)
    }

    func testLegacySchemaOneBackupDefaultsTrustFieldsAndStripsRemoteIcon() throws {
        let legacyJSON = """
        {
          "schemaVersion": 1,
          "exportedAt": "2024-01-02T03:04:05Z",
          "includesSavedVariableValues": false,
          "tools": [
            {
              "id": "00000000-0000-0000-0000-000000000001",
              "name": "legacy-cli",
              "executablePath": "/opt/homebrew/bin/legacy-cli",
              "commandTemplate": "legacy-cli",
              "toolDescription": "Legacy CLI",
              "categoryRawValue": "开发工具",
              "iconSymbol": "terminal",
              "iconURLString": "https://avatars.githubusercontent.com/u/1",
              "repositoryFullName": "example/legacy-cli",
              "isUserCustomized": false,
              "isHidden": false,
              "variableValuesJSON": null,
              "lastLaunchedAt": null,
              "createdAt": "2024-01-02T03:04:05Z"
            }
          ],
          "candidates": [
            {
              "id": "00000000-0000-0000-0000-000000000002",
              "name": "legacy-candidate",
              "executablePath": "/Users/example/.cargo/bin/legacy-candidate",
              "categoryRawValue": "其他/未分类",
              "statusRawValue": "pending",
              "discoveredAt": "2024-01-02T03:04:05Z"
            }
          ]
        }
        """

        let backup = try BackupService.decode(Data(legacyJSON.utf8))
        let record = try XCTUnwrap(backup.tools.first)
        let restored = record.makeTool(includesSavedVariableValues: backup.includesSavedVariableValues)
        XCTAssertNil(restored.iconURLString)
        XCTAssertFalse(restored.favorite)
        XCTAssertEqual(restored.installationSource, .homebrew)
        XCTAssertEqual(restored.metadataProvenance, .local)
        XCTAssertEqual(restored.metadataMatchConfidence, 0)

        let existing = TerminalTool(
            name: "existing-cli",
            executablePath: "/usr/local/bin/existing-cli",
            commandTemplate: "existing-cli"
        )
        existing.iconURLString = "https://avatars.githubusercontent.com/u/2"
        existing.favorite = true
        record.apply(to: existing, includesSavedVariableValues: backup.includesSavedVariableValues)
        XCTAssertNil(existing.iconURLString)
        XCTAssertTrue(existing.favorite)

        let candidate = try XCTUnwrap(backup.candidates.first).makeCandidate()
        XCTAssertEqual(candidate.installationSource, .cargo)
    }
}


extension ToolWorkflowTests {
    func testAcceptedCandidateKeepsLocalCommandAndTrustMetadata() {
        let candidate = CandidateTool(
            name: "custom-cli",
            executablePath: "/Users/example/.cargo/bin/custom-cli",
            category: .development,
            installationSource: .cargo
        )

        let tool = candidate.makeToolForAcceptance()
        XCTAssertEqual(tool.name, "custom-cli")
        XCTAssertEqual(tool.executablePath, "/Users/example/.cargo/bin/custom-cli")
        XCTAssertEqual(tool.commandTemplate, "custom-cli")
        XCTAssertEqual(tool.category, .development)
        XCTAssertEqual(tool.installationSource, .cargo)
        XCTAssertEqual(tool.metadataProvenance, .local)
        XCTAssertEqual(tool.metadataMatchConfidence, 0)
        XCTAssertNil(tool.iconURLString)
    }

    func testTerminalErrorMessagesGiveSafeRecoveryGuidance() {
        let unavailable = TerminalLauncherError.applicationUnavailable("Warp")
        XCTAssertTrue(unavailable.message(language: .simplifiedChinese).contains("仅复制命令"))
        XCTAssertTrue(unavailable.message(language: .english).contains("copy the command only"))

        let denied = TerminalLauncherError.automationPermissionDenied(.iTerm)
        XCTAssertTrue(denied.message(language: .simplifiedChinese).contains("自动化"))
        XCTAssertTrue(denied.message(language: .english).contains("Automation"))
    }

    func testCopyOnlyTargetHasNoApplicationIdentifierAndClearBoundary() {
        XCTAssertNil(TerminalTarget.copyOnly.bundleIdentifier)
        XCTAssertTrue(TerminalTarget.copyOnly.helpText(.simplifiedChinese).contains("不启动任何终端"))
        XCTAssertTrue(TerminalTarget.copyOnly.helpText(.english).contains("without opening a terminal"))
    }
}


extension ToolWorkflowTests {
    func testPersistentDataStoreReopensExistingToolsAndCandidates() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermiPadStoreTests-\(UUID().uuidString)", isDirectory: true)
        let storeURL = directory.appendingPathComponent("TermiPad.store")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let toolID = UUID()
        let candidateID = UUID()
        do {
            let container = try TermiPadDataStore.makeContainer(storeURL: storeURL)
            let context = ModelContext(container)
            let tool = TerminalTool(
                name: "persisted-cli",
                executablePath: "/opt/homebrew/bin/persisted-cli",
                commandTemplate: "persisted-cli --safe",
                toolDescription: "Persistent test tool",
                category: .development,
                installationSource: .homebrew
            )
            tool.id = toolID
            tool.metadataProvenance = .githubOfficial
            tool.metadataMatchConfidence = 100
            context.insert(tool)

            let candidate = CandidateTool(
                name: "persisted-candidate",
                executablePath: "/Users/example/.cargo/bin/persisted-candidate",
                category: .other,
                installationSource: .cargo
            )
            candidate.id = candidateID
            context.insert(candidate)
            try context.save()
        }

        let reopenedContainer = try TermiPadDataStore.makeContainer(storeURL: storeURL)
        let reopenedContext = ModelContext(reopenedContainer)
        let tools = try reopenedContext.fetch(FetchDescriptor<TerminalTool>())
        let candidates = try reopenedContext.fetch(FetchDescriptor<CandidateTool>())

        let restoredTool = try XCTUnwrap(tools.first(where: { $0.id == toolID }))
        XCTAssertEqual(restoredTool.commandTemplate, "persisted-cli --safe")
        XCTAssertEqual(restoredTool.installationSource, .homebrew)
        XCTAssertEqual(restoredTool.metadataProvenance, .githubOfficial)
        XCTAssertEqual(restoredTool.metadataMatchConfidence, 100)

        let restoredCandidate = try XCTUnwrap(candidates.first(where: { $0.id == candidateID }))
        XCTAssertEqual(restoredCandidate.installationSource, .cargo)
        XCTAssertEqual(restoredCandidate.status, .pending)
    }

    func testInMemoryDataStoreSupportsIsolatedRecoveryTests() throws {
        let container = try TermiPadDataStore.makeContainer(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        context.insert(TerminalTool(
            name: "memory-cli",
            executablePath: "/usr/local/bin/memory-cli",
            commandTemplate: "memory-cli"
        ))
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<TerminalTool>()).count, 1)
    }
}


extension ToolWorkflowTests {
    func testBackupRestoreMergesByPathPreservesPrivateValuesAndPersists() throws {
        let container = try TermiPadDataStore.makeContainer(isStoredInMemoryOnly: true)
        let context = ModelContext(container)

        let existingTool = TerminalTool(
            name: "old-name",
            executablePath: "/opt/homebrew/bin/merge-cli",
            commandTemplate: "merge-cli --old",
            toolDescription: "Old description",
            category: .other,
            installationSource: .homebrew
        )
        existingTool.variableValuesJSON = "{\"token\":\"keep-local\"}"
        let existingToolID = existingTool.id
        context.insert(existingTool)
        try context.save()

        let incomingTool = TerminalTool(
            name: "merge-cli",
            executablePath: "/opt/homebrew/bin/merge-cli",
            commandTemplate: "merge-cli --new",
            toolDescription: "Restored description",
            category: .development,
            installationSource: .homebrew
        )
        incomingTool.metadataProvenance = .githubOfficial
        incomingTool.metadataMatchConfidence = 100
        incomingTool.variableValuesJSON = "{\"token\":\"should-not-import\"}"

        let incomingCandidate = CandidateTool(
            name: "restored-candidate",
            executablePath: "/Users/example/.cargo/bin/restored-candidate",
            category: .other,
            installationSource: .cargo
        )
        let backup = TermiPadBackup.make(
            tools: [incomingTool],
            candidates: [incomingCandidate],
            includeSavedVariableValues: false
        )

        let summary = BackupService.restore(
            backup,
            existingTools: [existingTool],
            existingCandidates: [],
            modelContext: context
        )
        try context.save()

        XCTAssertEqual(summary.addedTools, 0)
        XCTAssertEqual(summary.updatedTools, 1)
        XCTAssertEqual(summary.addedCandidates, 1)
        XCTAssertEqual(summary.updatedCandidates, 0)
        XCTAssertEqual(existingTool.id, existingToolID)
        XCTAssertEqual(existingTool.name, "merge-cli")
        XCTAssertEqual(existingTool.commandTemplate, "merge-cli --new")
        XCTAssertEqual(existingTool.metadataProvenance, .githubOfficial)
        XCTAssertEqual(existingTool.metadataMatchConfidence, 100)
        XCTAssertEqual(existingTool.variableValuesJSON, "{\"token\":\"keep-local\"}")

        let tools = try context.fetch(FetchDescriptor<TerminalTool>())
        let candidates = try context.fetch(FetchDescriptor<CandidateTool>())
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.installationSource, .cargo)
    }
}


extension ToolWorkflowTests {
    func testFavoriteDefaultsFalseAndCanBeToggledLocally() {
        let tool = TerminalTool(
            name: "favorite-cli",
            executablePath: "/usr/local/bin/favorite-cli",
            commandTemplate: "favorite-cli"
        )

        XCTAssertFalse(tool.favorite)
        tool.favorite = true
        XCTAssertTrue(tool.favorite)
        tool.favorite = false
        XCTAssertFalse(tool.favorite)
    }
}


extension ToolWorkflowTests {
    func testRecentToolOrderingPrefersLastLaunchAndUsesStableNameFallback() {
        let older = TerminalTool(name: "zulu", executablePath: "/usr/local/bin/zulu", commandTemplate: "zulu")
        older.lastLaunchedAt = Date(timeIntervalSince1970: 10)

        let newer = TerminalTool(name: "bravo", executablePath: "/usr/local/bin/bravo", commandTemplate: "bravo")
        newer.lastLaunchedAt = Date(timeIntervalSince1970: 20)

        let sameTime = TerminalTool(name: "alpha", executablePath: "/usr/local/bin/alpha", commandTemplate: "alpha")
        sameTime.lastLaunchedAt = Date(timeIntervalSince1970: 20)

        let neverLaunched = TerminalTool(name: "charlie", executablePath: "/usr/local/bin/charlie", commandTemplate: "charlie")

        let ordered = ToolLibraryOrdering.recentFirst([older, newer, neverLaunched, sameTime])
        XCTAssertEqual(ordered.map(\.name), ["alpha", "bravo", "zulu", "charlie"])
    }
}
