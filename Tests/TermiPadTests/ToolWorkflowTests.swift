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
}
