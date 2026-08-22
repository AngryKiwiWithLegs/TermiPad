import Foundation

/// `{{variable_name}}` 命令模板的解析与渲染。
enum CommandTemplate {
    private static let tokenExpression = try! NSRegularExpression(pattern: #"\{\{\s*([A-Za-z][A-Za-z0-9_-]{0,63})\s*\}\}"#)

    static func variables(in template: String) -> [String] {
        let range = NSRange(template.startIndex..., in: template)
        let matches = tokenExpression.matches(in: template, range: range)
        var seen = Set<String>()

        return matches.compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: template) else {
                return nil
            }
            let variable = String(template[range])
            return seen.insert(variable).inserted ? variable : nil
        }
    }

    static func render(template: String, values: [String: String]) throws -> String {
        let required = variables(in: template)
        let missing = required.filter { (values[$0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard missing.isEmpty else {
            throw CommandTemplateError.missingValues(missing)
        }

        var rendered = template
        let sourceRange = NSRange(template.startIndex..., in: template)
        let matches = tokenExpression.matches(in: template, range: sourceRange)
        for match in matches.reversed() {
            guard let wholeRange = Range(match.range, in: rendered),
                  let variableRange = Range(match.range(at: 1), in: template) else {
                continue
            }
            let variable = String(template[variableRange])
            rendered.replaceSubrange(wholeRange, with: shellEscape(values[variable] ?? ""))
        }
        return rendered
    }

    static func loadValues(from tool: TerminalTool) -> [String: String] {
        guard let json = tool.variableValuesJSON,
              let data = json.data(using: .utf8),
              let values = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return values
    }

    static func saveValues(_ values: [String: String], to tool: TerminalTool) {
        guard let data = try? JSONEncoder().encode(values),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        tool.variableValuesJSON = json
    }

    /// 以 POSIX 单引号转义用户变量，避免未确认的空格、引号或 shell 元字符改变命令结构。
    static func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\u{22}'\u{22}'") + "'"
    }
}

enum CommandTemplateError: LocalizedError, Equatable {
    case missingValues([String])

    var errorDescription: String? {
        switch self {
        case .missingValues(let variables):
            return "请先填写：\(variables.joined(separator: "、"))。"
        }
    }
}
