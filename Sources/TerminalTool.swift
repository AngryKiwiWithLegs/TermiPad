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
}

/// 发现候选的处理状态。候选不再自动进入工具墙，用户必须明确收录。
enum CandidateStatus: String, Codable, CaseIterable {
    case pending
    case accepted
    case ignored
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
