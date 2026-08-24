import Foundation

/// GitHub 服务：仅在官方映射或高置信名称匹配时补充仓库、README 与头像。
/// 低置信搜索结果不会自动写入工具，避免把无关仓库的命令或品牌信息带入本地工具库。
enum GitHubService {
    private static let baseURL = "https://api.github.com"
    private static let minimumAutomaticMatchScore = 80

    /// 常见 CLI 的官方仓库映射。仅用于名称本身存在公认别名的工具；其余名称仍走保守匹配。
    private static let officialRepositoryByToolName: [String: String] = [
        "aider": "Aider-AI/aider",
        "bat": "sharkdp/bat",
        "btop": "aristocratos/btop",
        "codex": "openai/codex",
        "eza": "eza-community/eza",
        "ffmpeg": "FFmpeg/FFmpeg",
        "fzf": "junegunn/fzf",
        "gemini": "google-gemini/gemini-cli",
        "gh": "cli/cli",
        "gitui": "gitui-org/gitui",
        "htop": "htop-dev/htop",
        "lazygit": "jesseduffield/lazygit",
        "netlify": "netlify/cli",
        "ollama": "ollama/ollama",
        "ripgrep": "BurntSushi/ripgrep",
        "rg": "BurntSushi/ripgrep",
        "vercel": "vercel/vercel",
        "yt-dlp": "yt-dlp/yt-dlp"
    ]

    struct RepositoryInfo: Sendable {
        let repoFullName: String
        let readmeContent: String
        let ownerAvatarURLString: String?
        let repositoryDescription: String?
        let metadataProvenance: ToolMetadataProvenance
        let matchConfidence: Int
    }

    /// 根据工具名称定位仓库。优先使用官方映射；通用搜索仅接受名称分数足够高的非归档仓库。
    static func findRepository(for toolName: String) async throws -> RepositoryInfo? {
        let normalizedToolName = normalizeToolName(toolName)
        guard !normalizedToolName.isEmpty else { return nil }

        if let officialRepository = officialRepositoryByToolName[normalizedToolName] {
            return await fetchRepository(
                fullName: officialRepository,
                metadataProvenance: .githubOfficial,
                matchConfidence: 100
            )
        }

        let query = "\(toolName) topic:cli"
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "\(baseURL)/search/repositories?q=\(encodedQuery)&sort=stars&order=desc&per_page=10") else {
            return nil
        }

        guard let searchData = await fetchData(from: searchURL, accept: "application/vnd.github+json"),
              let searchResult = try? JSONDecoder().decode(GitHubSearchResponse.self, from: searchData) else {
            return nil
        }

        guard let match = searchResult.items
            .map({ ($0, matchScore(toolName: normalizedToolName, repository: $0)) })
            .filter({ $0.1 >= minimumAutomaticMatchScore })
            .max(by: { $0.1 < $1.1 }) else {
            return nil
        }

        let repository = match.0
        let readmeContent = await fetchReadme(for: repository.fullName)
        return RepositoryInfo(
            repoFullName: repository.fullName,
            readmeContent: readmeContent ?? repository.description ?? "",
            ownerAvatarURLString: repository.owner?.avatarURLString,
            repositoryDescription: repository.description,
            metadataProvenance: .githubMatched,
            matchConfidence: match.1
        )
    }

    /// 供单元测试验证的保守匹配规则。只有仓库名直接等于工具名或明显以工具名为前缀时才允许自动补充。
    static func matchScore(toolName: String, repository: GitHubRepoItem) -> Int {
        guard !repository.isArchived else { return Int.min }
        let normalizedToolName = normalizeToolName(toolName)
        let repositoryName = normalizeToolName(repository.name)
        let fullName = repository.fullName.lowercased()

        if repositoryName == normalizedToolName || fullName.hasSuffix("/\(normalizedToolName)") {
            return 100
        }
        if repositoryName.hasPrefix(normalizedToolName + "-") || repositoryName.hasPrefix(normalizedToolName + "_") {
            return 85
        }
        if normalizedToolName.count >= 4 && repositoryName.contains(normalizedToolName) {
            return 60
        }
        return 0
    }

    private static func fetchRepository(
        fullName: String,
        metadataProvenance: ToolMetadataProvenance,
        matchConfidence: Int
    ) async -> RepositoryInfo? {
        guard let url = URL(string: "\(baseURL)/repos/\(fullName)") else { return nil }
        guard let data = await fetchData(from: url, accept: "application/vnd.github+json"),
              let repository = try? JSONDecoder().decode(GitHubRepoItem.self, from: data),
              !repository.isArchived else {
            return nil
        }

        let readmeContent = await fetchReadme(for: repository.fullName)
        return RepositoryInfo(
            repoFullName: repository.fullName,
            readmeContent: readmeContent ?? repository.description ?? "",
            ownerAvatarURLString: repository.owner?.avatarURLString,
            repositoryDescription: repository.description,
            metadataProvenance: metadataProvenance,
            matchConfidence: matchConfidence
        )
    }

    private static func fetchReadme(for repositoryFullName: String) async -> String? {
        guard let url = URL(string: "\(baseURL)/repos/\(repositoryFullName)/readme"),
              let data = await fetchData(from: url, accept: "application/vnd.github.raw+json") else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func fetchData(from url: URL, accept: String) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("TermiPad", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            return nil
        }
        return data
    }

    private static func normalizeToolName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
    }
}

struct GitHubRepoItem: Decodable {
    let name: String
    let fullName: String
    let description: String?
    let owner: GitHubRepositoryOwner?
    let isArchived: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case fullName = "full_name"
        case description
        case owner
        case isArchived = "archived"
    }
}

private struct GitHubSearchResponse: Decodable {
    let items: [GitHubRepoItem]
}

struct GitHubRepositoryOwner: Decodable {
    let avatarURLString: String?

    enum CodingKeys: String, CodingKey {
        case avatarURLString = "avatar_url"
    }
}
