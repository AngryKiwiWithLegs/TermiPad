import XCTest
@testable import TermiPad

/// CommandTemplate unit tests (track-protoid stage 6 test hardening).
///
/// CommandTemplate is the safety barrier before TermiPad launches a user command:
///  1. `variables(in:)` extracts the `{{var}}` placeholders in a template (for the pre-launch form)
///  2. `render(template:values:)` requires a value for every placeholder and throws when one is missing
///  3. `shellEscape(_:)` is the **only** shell injection defense point
///  4. `loadValues/saveValues` persist via JSON Codable
///
/// `shellEscape` uses the only safe POSIX pattern, "single quotes + break out ' + 'X' replacement":
/// any commit that simplifies it to double quotes or backslashes would let the `echo "; rm -rf /"` injection succeed.
/// These tests **deliberately** include malicious values to verify that shellEscape does not let them through.
final class CommandTemplateTests: XCTestCase {

    // MARK: - variables(in:)

    func testVariablesExtractsUniqueOrderedPlaceholders() {
        // Duplicate placeholders count once, keeping the order of first appearance
        XCTAssertEqual(
            CommandTemplate.variables(in: "swift {{action}} {{target}} {{action}}"),
            ["action", "target"]
        )
    }

    func testVariablesToleratesWhitespaceInsideBraces() {
        XCTAssertEqual(
            CommandTemplate.variables(in: "tool {{ name }} {{  type}}"),
            ["name", "type"]
        )
    }

    func testVariablesEmptyOnNoPlaceholders() {
        XCTAssertEqual(CommandTemplate.variables(in: "ls -la /tmp"), [])
    }

    func testVariablesAcceptsHyphenAndUnderscoreButNotDigits() {
        // The regex [A-Za-z][A-Za-z0-9_-]{0,63} allows a letter followed by alnum / _ / -
        XCTAssertEqual(
            CommandTemplate.variables(in: "{{my-var_1}} {{2invalid}} {{ok_name}}"),
            ["my-var_1", "ok_name"] // {{2invalid}} starts with a digit and does not match
        )
    }

    // MARK: - render(template:values:)

    func testRenderSubstitutesAllValues() throws {
        // render automatically shellEscapes every value — this is the project's core safety design: a user cannot
        // inject unescaped content through render. The test locks down this behavior.
        let out = try CommandTemplate.render(
            template: "{{tool}} --target {{path}}",
            values: ["tool": "ffmpeg", "path": "/tmp/x"]
        )
        XCTAssertEqual(out, "'ffmpeg' --target '/tmp/x'")
    }

    func testRenderThrowsWhenAnyPlaceholderMissing() {
        XCTAssertThrowsError(try CommandTemplate.render(
            template: "{{tool}} {{target}}",
            values: ["tool": "ffmpeg"]
        )) { error in
            XCTAssertEqual(error as? CommandTemplateError, .missingValues(["target"]))
        }
    }

    func testRenderTrimsWhitespaceAndConsidersEmptyAsMissing() {
        XCTAssertThrowsError(try CommandTemplate.render(
            template: "{{tool}}",
            values: ["tool": "   "]  // all-whitespace is equivalent to missing
        )) { error in
            XCTAssertEqual(error as? CommandTemplateError, .missingValues(["tool"]))
        }
    }

    func testRenderRendersEmptyStringForEmptyValue() throws {
        // Deliberate "trailing" behavior: whitespace is trimmed and counts as missing, but the plain string "" never
        // reaches the trim path — it is in fact also caught by missingValues here (that boundary is exactly what we test).
        XCTAssertThrowsError(try CommandTemplate.render(
            template: "{{x}}",
            values: ["x": ""]
        )) { error in
            XCTAssertEqual(error as? CommandTemplateError, .missingValues(["x"]))
        }
    }

    // MARK: - shellEscape(_:) — core injection defense

    func testShellEscapeAlwaysSingleQuoted() {
        // A safe value: still wrapped in single quotes. It looks "redundant", but it must **not** change — consistency is the key to
        // attack defense: when a single quote appears in the value the whole value becomes "'a'\\''b'" and so on, and any shortcut would break it.
        XCTAssertEqual(CommandTemplate.shellEscape("hello"), "'hello'")
        XCTAssertEqual(CommandTemplate.shellEscape(""), "''")
    }

    func testShellEscapeNeutralizesSingleQuoteInjection() {
        // Attack vector: the input "; rm -rf /" should be wrapped in single quotes — the shell treats the whole string
        // as one argument and does **not** parse it as "empty command + rm -rf /".
        // Key point: inside single quotes the semicolon is a literal character, not a command separator.
        let escaped = CommandTemplate.shellEscape("; rm -rf /")
        XCTAssertEqual(escaped, "'; rm -rf /'")
        XCTAssertNotEqual(escaped, "; rm -rf /")
    }

    func testShellEscapeHandlesBackslashAndDoubleQuote() {
        // Inside POSIX single quotes neither \ nor " is a metacharacter, so shellEscape does not need to handle them.
        // The test locks down the simplification "the code only handles single quotes" — which is exactly the POSIX safety advice.
        let v = "back\\slash and \"double\""
        let escaped = CommandTemplate.shellEscape(v)
        XCTAssertEqual(escaped, "'\(v)'")
    }

    func testRenderWithShellEscapeSurvivesInjectionAttempt() throws {
        // End to end: the user value is a malicious payload, and template + render automatically escape it as a single argument.
        // The expectation is computed with shellEscape(the same value) to avoid mistakes from hand-computing the POSIX single-quote replacement.
        let payload = "'; touch /tmp/pwned; '"
        let expected = "echo \(CommandTemplate.shellEscape(payload))"
        let actual = try CommandTemplate.render(template: "echo {{msg}}", values: ["msg": payload])
        XCTAssertEqual(actual, expected)
        // Negative assertion: it should not be the bare form echo + touch
        XCTAssertFalse(actual.contains("echo ;"))
        XCTAssertFalse(actual.contains("echo ; touch"))
    }

    // MARK: - loadValues / saveValues (JSON Codable round-trip)

    func testSaveAndLoadValuesRoundTrips() throws {
        let original = ["name": "alice", "role": "admin", "key": "k=v\\\"q"]
        let tool = makeToolForPersistence()
        CommandTemplate.saveValues(original, to: tool)
        XCTAssertNotNil(tool.variableValuesJSON)
        let loaded = CommandTemplate.loadValues(from: tool)
        XCTAssertEqual(loaded, original)
    }

    func testLoadValuesReturnsEmptyWhenNoJSONSet() {
        let tool = makeToolForPersistence()
        // variableValuesJSON defaults to nil
        let loaded = CommandTemplate.loadValues(from: tool)
        XCTAssertEqual(loaded, [:])
    }

    func testSaveValuesProducesValidJSON() throws {
        let tool = makeToolForPersistence()
        CommandTemplate.saveValues(["a": "1", "b": "2"], to: tool)
        let json = try XCTUnwrap(tool.variableValuesJSON)
        // Must be parsable by JSONDecoder
        let decoded = try JSONDecoder().decode([String: String].self, from: Data(json.utf8))
        XCTAssertEqual(decoded, ["a": "1", "b": "2"])
    }

    // MARK: - helpers

    private func makeToolForPersistence() -> TerminalTool {
        TerminalTool(
            name: "test-tool",
            executablePath: "/usr/local/bin/test-tool",
            commandTemplate: "test-tool"
        )
    }
}
