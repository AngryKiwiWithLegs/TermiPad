import Foundation
import SwiftData

/// 终端工具分类
enum ToolCategory: String, Codable, CaseIterable, Identifiable {
    case ai = "AI/智能体"
    case development = "开发工具"
    case efficiency = "效率工具"
    case media = "媒体处理"
    case system = "网络与系统"
    case other = "其他/未分类"
    
    var id: String { self.rawValue }
    
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

/// 终端工具数据模型
@Model
final class TerminalTool {
    var id: UUID
    var name: String                  // 工具名称，如 claude, gh, ffmpeg
    var executablePath: String        // 二进制绝对路径，如 /opt/homebrew/bin/claude
    var commandTemplate: String       // 启动命令模板，如 claude --model=sonnet {{prompt}}
    var toolDescription: String       // 工具描述（从 README 提取）
    var categoryRawValue: String      // 分类原始值
    var iconSymbol: String            // SwiftUI 图标名或自定义图标路径
    var isUserCustomized: bool        // 是否经过用户手动修改
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
        self.id = UUID()
        self.name = name
        self.executablePath = executablePath
        self.commandTemplate = commandTemplate.isEmpty ? "\(name)" : commandTemplate
        self.toolDescription = toolDescription
        self.categoryRawValue = category.rawValue
        self.iconSymbol = iconSymbol
        self.isUserCustomized = isUserCustomized
        self.createdAt = Date()
    }
}
