import XCTest
import AppKit
import Foundation
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

        let recoveryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermiPadTests-LegacyRecovery-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: recoveryRoot) }
        let recoveryContainer = try TermiPadDataStore.makeRecoveryContainer(applicationSupportDirectory: recoveryRoot)
        let recoveryContext = ModelContext(recoveryContainer)
        let summary = BackupService.restore(
            backup,
            existingTools: [],
            existingCandidates: [],
            modelContext: recoveryContext
        )
        XCTAssertEqual(summary.addedTools, 1)
        XCTAssertEqual(summary.addedCandidates, 1)
        try recoveryContext.save()

        let reopenedContainer = try TermiPadDataStore.makeRecoveryContainer(applicationSupportDirectory: recoveryRoot)
        let reopenedContext = ModelContext(reopenedContainer)
        let recoveredTools = try reopenedContext.fetch(FetchDescriptor<TerminalTool>())
        XCTAssertEqual(recoveredTools.first?.name, "legacy-cli")
        XCTAssertNil(recoveredTools.first?.iconURLString)
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
        existingTool.customIconFilename = "keep-local.png"
        existingTool.workingDirectoryPath = "/Users/example/keep-local"
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
        incomingTool.customIconFilename = "not-exported.png"
        incomingTool.workingDirectoryPath = "/Users/example/not-exported"

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
        XCTAssertEqual(existingTool.customIconFilename, "keep-local.png")
        XCTAssertEqual(existingTool.workingDirectoryPath, "/Users/example/keep-local")

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


extension ToolWorkflowTests {
    func testDiagnosticsStoreCreatesPrivacyReportWithoutSensitiveFields() throws {
        let suiteName = "TermiPadTests.diagnostics.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var timestamp = Date(timeIntervalSince1970: 100)
        let store = DiagnosticsStore(
            defaults: defaults,
            storageKey: "events",
            maximumEventCount: 2,
            now: { timestamp }
        )

        store.record(.scanCompleted, itemCount: 4)
        timestamp = Date(timeIntervalSince1970: 200)
        store.record(.launchSucceeded, terminalTarget: .iTerm)
        timestamp = Date(timeIntervalSince1970: 300)
        store.record(.backupExported, itemCount: 2)

        XCTAssertEqual(store.events.map(\.kind), [.launchSucceeded, .backupExported])
        XCTAssertEqual(store.events.first?.terminalTargetRawValue, TerminalTarget.iTerm.rawValue)
        XCTAssertEqual(store.events.last?.itemCount, 2)

        let reportData = try JSONEncoder().encode(store.makePrivacyReport())
        let reportJSON = try XCTUnwrap(String(data: reportData, encoding: .utf8))
        XCTAssertFalse(reportJSON.contains("executablePath"))
        XCTAssertFalse(reportJSON.contains("variableValuesJSON"))
        XCTAssertFalse(reportJSON.contains("repositoryFullName"))
        XCTAssertFalse(reportJSON.contains("apiKey"))

        store.clear()
        XCTAssertTrue(store.events.isEmpty)
    }
}


extension ToolWorkflowTests {
    func testAppActionsRoundTripUsingOnlyFixedIdentifiers() {
        let notification = Notification(
            name: .termiPadAppAction,
            object: nil,
            userInfo: ["action": TermiPadAppAction.showFavorites.rawValue]
        )
        XCTAssertEqual(TermiPadAppAction.from(notification), .showFavorites)

        let malformed = Notification(name: .termiPadAppAction, object: nil, userInfo: ["action": "unknown-action"])
        XCTAssertNil(TermiPadAppAction.from(malformed))
    }
}


extension ToolWorkflowTests {
    func testUpdateCheckRequiresHTTPSAndComparesNumericVersionsOnly() throws {
        XCTAssertEqual(UpdateCheckService.compare("1.2.0", to: "1.1.9"), .orderedDescending)
        XCTAssertEqual(UpdateCheckService.compare("1.2", to: "1.2.0"), .orderedSame)
        XCTAssertEqual(UpdateCheckService.compare("1.0.0", to: "2.0.0"), .orderedAscending)
        XCTAssertNil(UpdateCheckService.compare("1.0-beta", to: "1.0.0"))

        XCTAssertEqual(
            try UpdateCheckService.validatedFeedURL("https://updates.example.com/termipad.json"),
            URL(string: "https://updates.example.com/termipad.json")
        )
        XCTAssertThrowsError(try UpdateCheckService.validatedFeedURL("http://updates.example.com/termipad.json")) { error in
            XCTAssertEqual(error as? UpdateCheckError, .insecureFeedURL)
        }
        XCTAssertThrowsError(try UpdateCheckService.validatedFeedURL("not a url")) { error in
            XCTAssertEqual(error as? UpdateCheckError, .invalidFeedURL)
        }
    }
}


extension ToolWorkflowTests {
    func testLocalizedFormatSupportsStringAndIntegerPlaceholders() {
        XCTAssertEqual(
            AppCopy.format("updateAvailable", "1.2.3", language: .english),
            "Version 1.2.3 is available. Review the release notes and decide whether to obtain it."
        )
        XCTAssertEqual(
            AppCopy.format("foundCandidates", 3, language: .simplifiedChinese),
            "发现 3 个候选工具。请在“候选收件箱”中确认要收录的项目。"
        )
    }
}


extension ToolWorkflowTests {
    func testCustomIconStoreCopiesPNGRejectsPathsAndRemovesLocalFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermiPadTests-IconStore-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let sourceURL = directory.appendingPathComponent("source.png")
        let sourceImage = NSImage(size: NSSize(width: 16, height: 16))
        sourceImage.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 16, height: 16)).fill()
        sourceImage.unlockFocus()
        let tiffData = try XCTUnwrap(sourceImage.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiffData))
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: sourceURL)

        let store = ToolIconStore(directoryURL: directory.appendingPathComponent("stored", isDirectory: true))
        let filename = try store.storeImage(from: sourceURL)
        let storedURL = try XCTUnwrap(store.url(for: filename))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))
        XCTAssertNotNil(store.image(named: filename))
        XCTAssertNil(store.url(for: "../outside.png"))
        XCTAssertNil(store.url(for: "not-an-image.txt"))

        store.removeImage(named: filename)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storedURL.path))
    }

    func testBackupDoesNotEncodeCustomIconFilename() throws {
        let tool = TerminalTool(name: "custom-icon", executablePath: "/usr/local/bin/custom-icon", commandTemplate: "custom-icon")
        tool.customIconFilename = "local-only.png"
        let backup = TermiPadBackup.make(tools: [tool], candidates: [], includeSavedVariableValues: false)
        let json = try XCTUnwrap(String(data: try BackupService.encode(backup), encoding: .utf8))
        XCTAssertFalse(json.contains("customIconFilename"))
        XCTAssertFalse(json.contains("local-only.png"))
    }
}


extension ToolWorkflowTests {
    func testToolHealthChecksOnlyInspectableAbsolutePaths() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermiPadTests-Health-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let executableURL = directory.appendingPathComponent("available-tool")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        let nonExecutableURL = directory.appendingPathComponent("non-executable-tool")
        try Data("plain text".utf8).write(to: nonExecutableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: nonExecutableURL.path)

        XCTAssertEqual(ToolHealthChecker.check(executablePath: executableURL.path), .available)
        XCTAssertEqual(ToolHealthChecker.check(executablePath: nonExecutableURL.path), .notExecutable)
        XCTAssertEqual(ToolHealthChecker.check(executablePath: directory.appendingPathComponent("missing-tool").path), .missing)
        XCTAssertEqual(ToolHealthChecker.check(executablePath: "tool-on-path"), .notInspectable)
    }
}


extension ToolWorkflowTests {
    func testWorkingDirectoryContextUsesEscapedCDPrefixAndChecksFolders() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermiPadTests-Working Dir ' quoted", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let command = ToolLaunchContext.command("tool --flag", inWorkingDirectory: directory.path)
        let normalizedPath = try XCTUnwrap(ToolLaunchContext.normalizedDirectoryPath(directory.path))
        XCTAssertEqual(command, "cd -- \(CommandTemplate.shellEscape(normalizedPath)) && tool --flag")
        XCTAssertEqual(ToolLaunchContext.workingDirectoryHealth(for: directory.path), .available)
        XCTAssertEqual(ToolLaunchContext.workingDirectoryHealth(for: directory.appendingPathComponent("missing").path), .unavailable)
        XCTAssertEqual(ToolLaunchContext.workingDirectoryHealth(for: "relative-folder"), .notConfigured)
        XCTAssertEqual(ToolLaunchContext.command("tool --flag", inWorkingDirectory: nil), "tool --flag")
    }

    func testBackupDoesNotEncodeWorkingDirectoryPath() throws {
        let tool = TerminalTool(name: "directory-cli", executablePath: "/usr/local/bin/directory-cli", commandTemplate: "directory-cli")
        tool.workingDirectoryPath = "/Users/example/private-project"
        let backup = TermiPadBackup.make(tools: [tool], candidates: [], includeSavedVariableValues: false)
        let json = try XCTUnwrap(String(data: try BackupService.encode(backup), encoding: .utf8))
        XCTAssertFalse(json.contains("workingDirectoryPath"))
        XCTAssertFalse(json.contains("private-project"))
    }
}


extension ToolWorkflowTests {
    func testRecoveryContainerUsesDedicatedPersistentStore() throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermiPadTests-Recovery-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let firstContainer = try TermiPadDataStore.makeRecoveryContainer(applicationSupportDirectory: rootDirectory)
        let firstContext = ModelContext(firstContainer)
        firstContext.insert(TerminalTool(
            name: "recovered-cli",
            executablePath: "/usr/local/bin/recovered-cli",
            commandTemplate: "recovered-cli"
        ))
        try firstContext.save()

        let recoveryStoreURL = rootDirectory
            .appendingPathComponent("Recovery", isDirectory: true)
            .appendingPathComponent("TermiPad-recovery.store")
        XCTAssertTrue(FileManager.default.fileExists(atPath: recoveryStoreURL.path))

        let secondContainer = try TermiPadDataStore.makeRecoveryContainer(applicationSupportDirectory: rootDirectory)
        let secondContext = ModelContext(secondContainer)
        let tools = try secondContext.fetch(FetchDescriptor<TerminalTool>())
        XCTAssertEqual(tools.map(\.name), ["recovered-cli"])
    }
}


extension ToolWorkflowTests {
    func testDiscoveryRequestIsFixedPublicAndUsesMatchingCacheETagOnly() throws {
        let cached = DiscoveryCacheSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            query: DiscoveryService.query,
            entityTag: "\"cached-etag\"",
            isIncomplete: false,
            items: []
        )
        let request = try DiscoveryService.makeRequest(cache: cached)

        XCTAssertEqual(request.url?.host, "api.github.com")
        XCTAssertTrue(request.url?.absoluteString.contains("per_page=20") == true)
        XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "\"cached-etag\"")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), nil)
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "TermiPad-DiscoveryPreview")
        XCTAssertFalse(request.url?.absoluteString.contains("command") == true)
        XCTAssertFalse(request.url?.absoluteString.contains("path") == true)

        let staleQueryCache = DiscoveryCacheSnapshot(
            fetchedAt: cached.fetchedAt,
            query: "unrelated-query",
            entityTag: "\"must-not-send\"",
            isIncomplete: false,
            items: []
        )
        XCTAssertNil(try DiscoveryService.makeRequest(cache: staleQueryCache).value(forHTTPHeaderField: "If-None-Match"))
    }

    func testDiscoveryDecodingFiltersArchivedAndForksAndExplainsEvidence() throws {
        let payload = """
        {
          "incomplete_results": true,
          "items": [
            {
              "id": 1,
              "full_name": "example/active-cli",
              "name": "active-cli",
              "description": "An interactive command-line tool.",
              "html_url": "https://github.com/example/active-cli",
              "license": { "name": "MIT License" },
              "topics": ["cli", "terminal"],
              "stargazers_count": 1000,
              "forks_count": 10,
              "created_at": "2024-01-01T00:00:00Z",
              "pushed_at": "2026-08-20T00:00:00Z",
              "archived": false,
              "fork": false
            },
            {
              "id": 2,
              "full_name": "example/archived-cli",
              "name": "archived-cli",
              "description": "Archived.",
              "html_url": "https://github.com/example/archived-cli",
              "license": null,
              "topics": ["cli"],
              "stargazers_count": 9999,
              "forks_count": 0,
              "created_at": "2024-01-01T00:00:00Z",
              "pushed_at": "2026-08-20T00:00:00Z",
              "archived": true,
              "fork": false
            },
            {
              "id": 3,
              "full_name": "example/forked-cli",
              "name": "forked-cli",
              "description": "Fork.",
              "html_url": "https://github.com/example/forked-cli",
              "license": null,
              "topics": ["cli"],
              "stargazers_count": 9999,
              "forks_count": 0,
              "created_at": "2024-01-01T00:00:00Z",
              "pushed_at": "2026-08-20T00:00:00Z",
              "archived": false,
              "fork": true
            }
          ]
        }
        """
        let now = Date(timeIntervalSince1970: 1_777_000_000)
        let snapshot = try DiscoveryService.decodeSnapshot(
            data: try XCTUnwrap(payload.data(using: .utf8)),
            entityTag: "\"demo\"",
            fetchedAt: now
        )

        XCTAssertTrue(snapshot.isIncomplete)
        XCTAssertEqual(snapshot.items.map(\.repositoryFullName), ["example/active-cli"])
        XCTAssertTrue(DiscoveryRanking.explanation(for: try XCTUnwrap(snapshot.items.first), language: .english, now: now).contains("CLI"))
        XCTAssertTrue(DiscoveryRanking.explanation(for: try XCTUnwrap(snapshot.items.first), language: .simplifiedChinese, now: now).contains("CLI/终端项目"))
    }

    func testDiscoveryCacheStaysInUserDefaultsAndCanBeCleared() throws {
        let suiteName = "TermiPadTests-DiscoveryCache-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let snapshot = DiscoveryCacheSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            query: DiscoveryService.query,
            entityTag: nil,
            isIncomplete: false,
            items: []
        )
        DiscoveryCacheStore.save(snapshot, defaults: defaults)
        XCTAssertEqual(DiscoveryCacheStore.load(defaults: defaults), snapshot)
        DiscoveryCacheStore.clear(defaults: defaults)
        XCTAssertNil(DiscoveryCacheStore.load(defaults: defaults))
    }

    func testDiscoveryCopyStatesExplicitlyForbidInstallation() {
        XCTAssertTrue(AppCopy.text("discoveryNoInstallHint", language: .english).contains("does not install software"))
        XCTAssertTrue(AppCopy.text("discoverySettingsHint", language: .simplifiedChinese).contains("不会自动联网"))
    }
}


extension ToolWorkflowTests {
    func testDiscoveryDiagnosticsUseFixedPrivacySafeCategories() throws {
        let suiteName = "TermiPadTests-DiscoveryDiagnostics-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = DiagnosticsStore(defaults: defaults, storageKey: "events", now: { Date(timeIntervalSince1970: 123) })

        store.record(.discoveryRefreshed, itemCount: 7)
        store.record(.discoveryCacheReused, itemCount: 7)
        store.record(.discoveryRefreshFailed)

        XCTAssertEqual(store.events.map(\.kind), [.discoveryRefreshed, .discoveryCacheReused, .discoveryRefreshFailed])
        XCTAssertEqual(store.events.first?.itemCount, 7)
        let report = try XCTUnwrap(String(data: try JSONEncoder().encode(store.makePrivacyReport()), encoding: .utf8))
        XCTAssertFalse(report.contains("repositoryFullName"))
        XCTAssertFalse(report.contains("commandTemplate"))
        XCTAssertFalse(report.contains("api.github.com"))
    }
}


extension ToolWorkflowTests {
    func testControlledInstallCatalogUsesReviewedFixedHomebrewPlansOnly() {
        let plan = ControlledInstallCatalog.plan(forRepositoryFullName: "cli/cli")
        XCTAssertEqual(plan?.formula, "gh")
        XCTAssertEqual(plan?.command, "brew install gh")
        XCTAssertEqual(plan?.channel, .homebrewCore)
        XCTAssertEqual(plan?.expectedExecutableNames, ["gh"])
        XCTAssertEqual(plan?.catalogRevision, "2026.08.25.1")
        XCTAssertEqual(plan?.auditedAt, "2026-08-25")
        XCTAssertTrue(ControlledInstallCatalog.isValidFormula("git-delta"))
        XCTAssertFalse(ControlledInstallCatalog.isValidFormula("gh --formula evil"))
        XCTAssertFalse(ControlledInstallCatalog.isValidFormula("gh\nevil"))
        XCTAssertFalse(ControlledInstallCatalog.isValidFormula("gh;evil"))
        XCTAssertNil(ControlledInstallCatalog.plan(forRepositoryFullName: "cli/cli-fork"))
        XCTAssertNil(ControlledInstallCatalog.plan(forFormula: "gh --formula evil"))
        XCTAssertTrue(ControlledInstallBoundary.doesNotRunInApp)
        XCTAssertTrue(ControlledInstallBoundary.doesNotAutoCollectResult)
        XCTAssertTrue(ControlledInstallBoundary.doesNotUseRemoteCommands)
        XCTAssertTrue(ControlledInstallBoundary.doesNotSupportThirdPartyTaps)
    }

    func testEnvironmentReportUsesOnlyResolvedFixedPathsAndVersionReader() {
        var inspectedPaths: [String] = []
        let report = EnvironmentReporter.inspect(
            now: Date(timeIntervalSince1970: 1_700_000_000),
            pathLookup: { component in
                component == .homebrew ? "/controlled/homebrew/bin/brew" : nil
            },
            versionReader: { path in
                inspectedPaths.append(path)
                return .available(version: "Homebrew 4.0.0")
            }
        )

        XCTAssertEqual(inspectedPaths, ["/controlled/homebrew/bin/brew"])
        XCTAssertEqual(report.availableCount, 1)
        XCTAssertEqual(report.entries.first?.component, .homebrew)
        XCTAssertEqual(report.entries.first?.status, .available(version: "Homebrew 4.0.0"))
        XCTAssertEqual(report.entries.dropFirst().map(\.status), Array(repeating: .unavailable, count: 5))
        XCTAssertTrue(EnvironmentReportBoundary.onlyRunsOnExplicitUserAction)
        XCTAssertTrue(EnvironmentReportBoundary.onlyUsesFixedAbsolutePaths)
        XCTAssertTrue(EnvironmentReportBoundary.onlyUsesVersionArgument)
        XCTAssertTrue(EnvironmentReportBoundary.doesNotUseShell)
        XCTAssertTrue(EnvironmentReportBoundary.doesNotInstallOrModify)
        XCTAssertTrue(EnvironmentReportBoundary.doesNotPersistPathsOrResults)
    }

    func testInstallAndEnvironmentDiagnosticsStayFixedAndPrivate() throws {
        let defaults = UserDefaults(suiteName: "TermiPadTests.install-environment-diagnostics")!
        defer { defaults.removePersistentDomain(forName: "TermiPadTests.install-environment-diagnostics") }
        let store = DiagnosticsStore(defaults: defaults, storageKey: "events", now: { Date(timeIntervalSince1970: 1_700_000_000) })
        store.record(.environmentReportRequested)
        store.record(.installPlanReviewed)
        store.record(.installPlanHandedOff, terminalTarget: .copyOnly)

        XCTAssertEqual(store.events.map(\.kind), [.environmentReportRequested, .installPlanReviewed, .installPlanHandedOff])
        let reportData = try JSONEncoder().encode(store.makePrivacyReport())
        let reportText = try XCTUnwrap(String(data: reportData, encoding: .utf8))
        XCTAssertFalse(reportText.contains("brew install"))
        XCTAssertFalse(reportText.contains("cli/cli"))
        XCTAssertFalse(reportText.contains("/controlled/"))
    }

    func testInstallAndEnvironmentSafetyCopyIsLocalized() {
        XCTAssertEqual(AppCopy.text("installAndEnvironment", language: .simplifiedChinese), "安装审查与环境报告")
        XCTAssertEqual(AppCopy.text("installAndEnvironment", language: .english), "Install Review & Environment")
        XCTAssertTrue(AppCopy.text("environmentReportHint", language: .simplifiedChinese).contains("不会使用 shell"))
        XCTAssertTrue(AppCopy.text("installReviewHint", language: .english).contains("cannot create or alter"))
        XCTAssertTrue(AppCopy.text("installRequiresHomebrewCheck", language: .simplifiedChinese).contains("Homebrew"))
    }
}
