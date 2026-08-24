import Foundation

/// 负责调用兼容 OpenAI Chat Completions 的服务，并将 README 提炼为可启动的工具信息。
///
/// 配置方式：API Key 保存在 macOS Keychain；服务地址和模型名称属于普通偏好，保存在 UserDefaults。
/// - Keychain `ai-api-key`：服务 API Key
/// - `TermiPad.aiBaseURL`：可选，默认 `https://api.openai.com/v1`
/// - `TermiPad.aiModel`：可选，默认 `gpt-4o-mini`
enum AIService {
    /// AI 只能补充用途说明与分类；启动命令始终来自本地扫描或用户手动编辑。
    struct ToolIntelligence: Codable, Sendable {
        let description: String
        let suggestedCategory: String

        enum CodingKeys: String, CodingKey {
            case description
            case suggestedCategory = "category"
        }
    }

    static let baseURLDefaultsKey = "TermiPad.aiBaseURL"
    static let modelDefaultsKey = "TermiPad.aiModel"
    private static let legacyAPIKeyDefaultsKey = "TermiPad.aiAPIKey"
    private static let apiKeyAccount = "ai-api-key"

    static var hasStoredAPIKey: Bool {
        (try? storedAPIKey())?.isEmpty == false
    }

    static func saveAPIKey(_ value: String) throws {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            try clearAPIKey()
            return
        }
        try KeychainStore.save(trimmedValue, for: apiKeyAccount)
        UserDefaults.standard.removeObject(forKey: legacyAPIKeyDefaultsKey)
    }

    static func clearAPIKey() throws {
        try KeychainStore.remove(account: apiKeyAccount)
        UserDefaults.standard.removeObject(forKey: legacyAPIKeyDefaultsKey)
    }

    /// 解析 README：如已配置 API Key，则调用大语言模型；否则返回本地说明回退。解析结果从不直接改写启动命令。
    static func analyzeTool(name: String, readme: String) async throws -> ToolIntelligence {
        guard let apiKey = try storedAPIKey(), !apiKey.isEmpty else {
            return localFallback(name: name, readme: readme)
        }

        let baseURL = UserDefaults.standard.string(forKey: baseURLDefaultsKey) ?? "https://api.openai.com/v1"
        let model = UserDefaults.standard.string(forKey: modelDefaultsKey) ?? "gpt-4o-mini"
        let endpoint = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions"

        guard let url = URL(string: endpoint) else {
            throw AIServiceError.invalidEndpoint
        }

        let payload = ChatCompletionRequest(
            model: model,
            messages: [
                ChatMessage(role: "system", content: "你是严谨的终端工具文档解析助手。仅根据 README 输出 JSON，不要猜测未出现的命令。"),
                ChatMessage(role: "user", content: buildPrompt(name: name, readme: readme))
            ],
            temperature: 0.1,
            responseFormat: ResponseFormat(type: "json_object")
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw AIServiceError.httpStatus(httpResponse.statusCode)
        }

        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = completion.choices.first?.message.content else {
            throw AIServiceError.missingContent
        }

        return try decodeIntelligence(from: content, fallbackName: name)
    }

    private static func storedAPIKey() throws -> String? {
        if let keychainValue = try KeychainStore.string(for: apiKeyAccount), !keychainValue.isEmpty {
            return keychainValue
        }

        // 仅迁移旧版偏好中的密钥；迁移成功或失败后都不再继续以 UserDefaults 作为运行时凭据来源。
        guard let legacyValue = UserDefaults.standard.string(forKey: legacyAPIKeyDefaultsKey),
              !legacyValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        try KeychainStore.save(legacyValue, for: apiKeyAccount)
        UserDefaults.standard.removeObject(forKey: legacyAPIKeyDefaultsKey)
        return legacyValue
    }

    private static func buildPrompt(name: String, readme: String) -> String {
        let excerpt = String(readme.prefix(8_000))
        return """
        请阅读以下 CLI 工具 README，并只返回一个 JSON 对象；不要添加 Markdown 代码围栏或解释。

        工具名称：\(name)
        README：
        \(excerpt)

        JSON 必须严格符合：
        {
          "description": "不超过 60 个中文字符的用途说明。不得把命令、参数、密钥或代码写入此字段。",
          "category": "仅可取：AI/智能体、开发工具、效率工具、媒体处理、网络与系统、其他/未分类。"
        }
        """
    }

    private static func decodeIntelligence(from content: String, fallbackName: String) throws -> ToolIntelligence {
        let cleanedContent = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let decoded = try JSONDecoder().decode(ToolIntelligence.self, from: Data(cleanedContent.utf8))
        let safeDescription = decoded.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "已由 AI 解析，但 README 未提供简要描述。"
            : decoded.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeCategory = ToolCategory(rawValue: decoded.suggestedCategory)?.rawValue
            ?? ToolScanner.guessCategory(for: fallbackName).rawValue

        return ToolIntelligence(
            description: safeDescription,
            suggestedCategory: safeCategory
        )
    }

    private static func localFallback(name: String, readme: String) -> ToolIntelligence {
        let summary = firstReadableLine(in: readme) ?? "已发现本地工具；配置 AI 服务后可自动提炼命令说明。"
        return ToolIntelligence(
            description: summary,
            suggestedCategory: ToolScanner.guessCategory(for: name).rawValue
        )
    }

    private static func firstReadableLine(in readme: String) -> String? {
        for rawLine in readme.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.count >= 16,
                  !line.hasPrefix("#"),
                  !line.hasPrefix("!"),
                  !line.hasPrefix("["),
                  !line.hasPrefix("```"),
                  !line.contains("badge") else {
                continue
            }
            return String(line.prefix(120))
        }
        return nil
    }
}

private enum AIServiceError: LocalizedError {
    case invalidEndpoint
    case invalidResponse
    case httpStatus(Int)
    case missingContent

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "AI 服务地址无效。"
        case .invalidResponse:
            return "AI 服务返回了无效响应。"
        case .httpStatus(let status):
            return "AI 服务请求失败，HTTP 状态码：\(status)。"
        case .missingContent:
            return "AI 服务响应中没有可解析的内容。"
        }
    }
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let responseFormat: ResponseFormat

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case responseFormat = "response_format"
    }
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ResponseFormat: Encodable {
    let type: String
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: ChatMessage
    }
}
