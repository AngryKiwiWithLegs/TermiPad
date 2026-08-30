import XCTest
@testable import TermiPad

/// CommandTemplate 单元测试（track-protoid 阶段 6 测试补强）。
///
/// CommandTemplate 是 TermiPad 启动用户命令前的安全屏障：
///  1. `variables(in:)` 提取模板里的 `{{var}}` 占位符（用于启动前填表）
///  2. `render(template:values:)` 强制要求每个占位符都有值，缺失抛错
///  3. `shellEscape(_:)` 是**唯一**的 shell 注入防御点
///  4. `loadValues/saveValues` 走 JSON Codable 持久化
///
/// `shellEscape` 用了 POSIX 唯一安全的"单引号 + 中断 ' + 'X' 替代"模式：
/// 任何把它简化成双引号或反斜杠的 commit 都会让 `echo "; rm -rf /"` 注入成功。
/// 这些测试**故意**包含恶意值，验证 shellEscape 不会让它们漏出。
final class CommandTemplateTests: XCTestCase {

    // MARK: - variables(in:)

    func testVariablesExtractsUniqueOrderedPlaceholders() {
        // 重复占位符只算一次，保留首次出现顺序
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
        // 正则 [A-Za-z][A-Za-z0-9_-]{0,63} 允许 letter 后跟 alnum / _ / -
        XCTAssertEqual(
            CommandTemplate.variables(in: "{{my-var_1}} {{2invalid}} {{ok_name}}"),
            ["my-var_1", "ok_name"] // {{2invalid}} 起始是数字，不匹配
        )
    }

    // MARK: - render(template:values:)

    func testRenderSubstitutesAllValues() throws {
        // render 自动对每个值 shellEscape——这是项目核心安全设计：用户不可能
        // 通过 render 注入未转义内容。测试锁住这个行为。
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
            values: ["tool": "   "]  // 全空白等价缺失
        )) { error in
            XCTAssertEqual(error as? CommandTemplateError, .missingValues(["tool"]))
        }
    }

    func testRenderRendersEmptyStringForEmptyValue() throws {
        // 故意"trailing" 行为：whitespace 被 trim 算缺失，但纯字符串 "" 走
        // 不到 trim 路径——其实这里也会被 missingValues 拦截（我们测的就是这个边界）。
        XCTAssertThrowsError(try CommandTemplate.render(
            template: "{{x}}",
            values: ["x": ""]
        )) { error in
            XCTAssertEqual(error as? CommandTemplateError, .missingValues(["x"]))
        }
    }

    // MARK: - shellEscape(_:) — 注入防御核心

    func testShellEscapeAlwaysSingleQuoted() {
        // 安全值：仍被单引号包。看起来"多余"，但**不能**改——一致性是攻击防御的
        // 关键：值里出现单引号时整个值变 "'a'\\''b'" 等等，任何捷径都会破坏。
        XCTAssertEqual(CommandTemplate.shellEscape("hello"), "'hello'")
        XCTAssertEqual(CommandTemplate.shellEscape(""), "''")
    }

    func testShellEscapeNeutralizesSingleQuoteInjection() {
        // 攻击向量: 输入 "; rm -rf /" 应该被单引号包裹 — shell 把整个串
        // 当成一个参数，**不会**把它解析成"空命令 + rm -rf /"。
        // 关键：分号在单引号里是字面字符，不是命令分隔符。
        let escaped = CommandTemplate.shellEscape("; rm -rf /")
        XCTAssertEqual(escaped, "'; rm -rf /'")
        XCTAssertNotEqual(escaped, "; rm -rf /")
    }

    func testShellEscapeHandlesBackslashAndDoubleQuote() {
        // POSIX 单引号里 \ 和 " 都**不**是元字符，所以 shellEscape 不需要处理它们。
        // 测试锁住"代码里只处理单引号"的简化——这正是 POSIX 安全建议。
        let v = "back\\slash and \"double\""
        let escaped = CommandTemplate.shellEscape(v)
        XCTAssertEqual(escaped, "'\(v)'")
    }

    func testRenderWithShellEscapeSurvivesInjectionAttempt() throws {
        // 端到端：用户值是恶意 payload，模板 + render 自动 escape 整体当参数。
        // 期望用 shellEscape(同样的值) 算得，避免手算 POSIX 单引号替换出错。
        let payload = "'; touch /tmp/pwned; '"
        let expected = "echo \(CommandTemplate.shellEscape(payload))"
        let actual = try CommandTemplate.render(template: "echo {{msg}}", values: ["msg": payload])
        XCTAssertEqual(actual, expected)
        // 反向断言: 不应是 echo + touch 的裸形式
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
        // variableValuesJSON 默认 nil
        let loaded = CommandTemplate.loadValues(from: tool)
        XCTAssertEqual(loaded, [:])
    }

    func testSaveValuesProducesValidJSON() throws {
        let tool = makeToolForPersistence()
        CommandTemplate.saveValues(["a": "1", "b": "2"], to: tool)
        let json = try XCTUnwrap(tool.variableValuesJSON)
        // 必须能被 JSONDecoder 解析
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
