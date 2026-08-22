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
