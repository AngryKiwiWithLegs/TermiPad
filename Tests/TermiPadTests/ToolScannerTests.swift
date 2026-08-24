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
            owner: nil,
            isArchived: archived
        )
    }
}
