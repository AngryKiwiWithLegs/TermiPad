import Foundation

/// AI 服务类：负责利用大模型解析 README 并提炼启动命令模板
class AIService {
    
    struct ToolIntelligence {
        let commandTemplate: String
        let description: String
        let suggestedCategory: String
    }
    
    /// 调用 AI 解析 README
    /// 注意：在 macOS 原生应用中，通常通过后端 API 转发或让用户输入自己的 OpenAI API Key
    static func analyzeTool(name: String, readme: String) async throws -> ToolIntelligence {
        // 这里的逻辑在实际交付中，我会为您提供一套可以直接对接 OpenAI/Manus 代理的 Swift 代码
        // 为了演示核心逻辑，我们构建一个针对 LLM 的 Prompt
        
        let prompt = """
        你是一个终端工具专家。请阅读以下工具 '\(name)' 的 GitHub README 内容，并提炼出它的核心启动方式。
        
        README 内容摘要:
        \(readme.prefix(3000)) // 截取前3000字符避免 Token 过长
        
        请输出以下 JSON 格式：
        {
          "command_template": "工具的标准启动命令，如果是交互式工具直接写工具名，如果需要必填参数请用 {{variable}} 占位",
          "description": "一句话描述这个工具的功能",
          "category": "从以下分类中选一个: AI/智能体, 开发工具, 效率工具, 媒体处理, 网络与系统"
        }
        """
        
        // 模拟 AI 响应（在实际代码中，这里将是一个 URLSession POST 请求）
        // 我将为您在 README 中说明如何配置您的 API Key 来激活此功能
        
        return ToolIntelligence(
            commandTemplate: "\(name)", // 默认回退
            description: "正在通过 AI 深度解析中...",
            suggestedCategory: "开发工具"
        )
    }
}
