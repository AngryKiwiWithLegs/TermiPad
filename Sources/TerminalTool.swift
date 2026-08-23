import Foundation
import SwiftData

/// 终端工具分类。
enum ToolCategory: String, Codable, CaseIterable, Identifiable {
    case ai = "AI/智能体"
    case development = "开发工具"
    case efficiency = "效率工具"
    case media = "媒体处理"
    case system = "网络与系统"
    case other = "其他/未分类"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .ai: return "sparkles"
        case .development: return "hammer"
        case .efficiency: return "bolt"
        case .media: return "film"
        case .system: return "network"
        case .other: return "square.grid.2x2"
        }
    }

    func displayName(_ language: AppLanguage) -> String {
        switch (self, language) {
        case (.ai, .simplifiedChinese): return "AI/智能体"
        case (.development, .simplifiedChinese): return "开发工具"
        case (.efficiency, .simplifiedChinese): return "效率工具"
        case (.media, .simplifiedChinese): return "媒体处理"
        case (.system, .simplifiedChinese): return "网络与系统"
        case (.other, .simplifiedChinese): return "其他/未分类"
        case (.ai, .english): return "AI & Agents"
        case (.development, .english): return "Development"
        case (.efficiency, .english): return "Productivity"
        case (.media, .english): return "Media"
        case (.system, .english): return "Network & System"
        case (.other, .english): return "Other"
        }
    }
}

/// 发现候选的处理状态。候选不再自动进入工具墙，用户必须明确收录。
enum CandidateStatus: String, Codable, CaseIterable {
    case pending
    case accepted
    case ignored
}

/// 在界面中展示工具用途时使用的安全回退策略。
///
/// AI 或 GitHub 补充是异步操作；其进度文本不应被写成用户看到的工具功能说明。
enum ToolDescriptionPresentation {
    private static let placeholderDescriptions: Set<String> = [
        "正在尝试 ai 增强",
        "正在通过 ai 深度解析中",
        "由本机扫描发现，等待补充说明",
        "本地发现的终端工具",
        "discovered locally; details are pending enrichment",
        "attempting ai enrichment",
        "ai enrichment in progress",
        "local terminal tool"
    ]

    static func displayDescription(for tool: TerminalTool, language: AppLanguage) -> String {
        let savedDescription = tool.toolDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !isPlaceholder(savedDescription) {
            return savedDescription
        }

        let categoryName = tool.category.displayName(language)
        switch language {
        case .simplifiedChinese:
            return "本机发现的\(categoryName)命令行工具。启动命令：\(tool.commandTemplate)"
        case .english:
            return "A locally discovered \(categoryName.lowercased()) command-line tool. Launch command: \(tool.commandTemplate)"
        }
    }

    static func isPlaceholder(_ description: String) -> Bool {
        let normalized = description
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return normalized.isEmpty || placeholderDescriptions.contains(normalized)
    }
}

/// 用户已收录的可交互终端工具。
@Model
final class TerminalTool {
    var id: UUID
    var name: String
    var executablePath: String
    var commandTemplate: String
    var toolDescription: String
    var categoryRawValue: String
    var iconSymbol: String
    var iconURLString: String?
    var repositoryFullName: String?
    var isUserCustomized: Bool
    var isHidden: Bool = false
    var variableValuesJSON: String?
    var lastLaunchedAt: Date?
    var createdAt: Date

    var category: ToolCategory {
        get { ToolCategory(rawValue: categoryRawValue) ?? .other }
        set { categoryRawValue = newValue.rawValue }
    }

    init(
        name: String,
        executablePath: String,
        commandTemplate: String,
        toolDescription: String = "",
        category: ToolCategory = .other,
        iconSymbol: String = "terminal",
        isUserCustomized: Bool = false
    ) {
        id = UUID()
        self.name = name
        self.executablePath = executablePath
        self.commandTemplate = commandTemplate.isEmpty ? name : commandTemplate
        self.toolDescription = toolDescription
        categoryRawValue = category.rawValue
        self.iconSymbol = iconSymbol
        iconURLString = nil
        repositoryFullName = nil
        self.isUserCustomized = isUserCustomized
        isHidden = false
        variableValuesJSON = nil
        lastLaunchedAt = nil
        createdAt = Date()
    }
}

/// 扫描到但尚未由用户确认收录的命令。
@Model
final class CandidateTool {
    var id: UUID
    var name: String
    var executablePath: String
    var categoryRawValue: String
    var statusRawValue: String
    var discoveredAt: Date

    var category: ToolCategory {
        get { ToolCategory(rawValue: categoryRawValue) ?? .other }
        set { categoryRawValue = newValue.rawValue }
    }

    var status: CandidateStatus {
        get { CandidateStatus(rawValue: statusRawValue) ?? .pending }
        set { statusRawValue = newValue.rawValue }
    }

    init(
        name: String,
        executablePath: String,
        category: ToolCategory,
        status: CandidateStatus = .pending
    ) {
        id = UUID()
        self.name = name
        self.executablePath = executablePath
        categoryRawValue = category.rawValue
        statusRawValue = status.rawValue
        discoveredAt = Date()
    }
}
