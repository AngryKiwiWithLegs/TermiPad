import Foundation

/// Calls an OpenAI Chat Completions-compatible service and distills a README into launchable tool information.
///
/// Configuration: the API key is stored in the macOS Keychain; the service URL and model name are ordinary preferences stored in UserDefaults.
/// - Keychain `ai-api-key`: the service API key
/// - `TermiPad.aiBaseURL`: optional, defaults to `https://api.openai.com/v1`
/// - `TermiPad.aiModel`: optional, defaults to `gpt-4o-mini`
enum AIService {
    /// AI may only add a purpose description and a category; the launch command always comes from the local scan or the user's manual edits.
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

    /// Analyze a README: if an API key is configured, call the LLM; otherwise return the local description fallback. The result never rewrites the launch command directly.
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
                ChatMessage(role: "system", content: "You are a rigorous assistant that parses terminal tool documentation. Output JSON based only on the README, and do not guess commands that do not appear in it."),
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

        // Only migrate the key from legacy preferences; whether the migration succeeds or fails, UserDefaults is no longer used as a runtime credential source.
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
        // The description is stored and shown as-is, so ask for it in the language the app is currently using.
        let language = AppLanguage.current
        let descriptionLanguage = language == .simplifiedChinese ? "Simplified Chinese" : "English"
        let descriptionLimit = language == .simplifiedChinese ? "60 Chinese characters" : "120 characters"
        // Category names are the persisted ToolCategory raw values; decodeIntelligence matches them exactly.
        let categoryList = ToolCategory.allCases.map(\.rawValue).joined(separator: ", ")
        return """
        Read the following CLI tool README and return exactly one JSON object; do not add Markdown code fences or explanations.

        Tool name: \(name)
        README:
        \(excerpt)

        The JSON must strictly match:
        {
          "description": "A purpose summary of at most \(descriptionLimit), written in \(descriptionLanguage). Never put commands, arguments, secrets, or code in this field.",
          "category": "Must be exactly one of: \(categoryList)."
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
            ? "Parsed by AI, but the README provides no short description."
            : decoded.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeCategory = ToolCategory(rawValue: decoded.suggestedCategory)?.rawValue
            ?? ToolScanner.guessCategory(for: fallbackName).rawValue

        return ToolIntelligence(
            description: safeDescription,
            suggestedCategory: safeCategory
        )
    }

    private static func localFallback(name: String, readme: String) -> ToolIntelligence {
        let summary = firstReadableLine(in: readme) ?? "Local tool discovered; configure the AI service to extract command descriptions automatically."
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
            return "The AI service URL is invalid."
        case .invalidResponse:
            return "The AI service returned an invalid response."
        case .httpStatus(let status):
            return "The AI service request failed with HTTP status \(status)."
        case .missingContent:
            return "The AI service response contained no parsable content."
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
