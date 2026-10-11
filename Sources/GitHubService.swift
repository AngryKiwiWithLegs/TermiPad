import Foundation

/// GitHub service: adds repository and README information only for an official mapping or a high-confidence name match.
/// Low-confidence search results are never written to a tool automatically, so commands or branding from unrelated repositories cannot enter the local library.
enum GitHubService {
    private static let baseURL = "https://api.github.com"
    private static let minimumAutomaticMatchScore = 80

    /// Official repository mapping for common CLIs. Used only for tools whose names have well-known aliases; all other names still go through conservative matching.
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
        let repositoryDescription: String?
        let metadataProvenance: ToolMetadataProvenance
        let matchConfidence: Int
    }

    /// Locate the repository by tool name. The official mapping takes priority; general search only accepts non-archived repositories with a high enough name score.
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
            repositoryDescription: repository.description,
            metadataProvenance: .githubMatched,
            matchConfidence: match.1
        )
    }

    /// Conservative matching rule verified by unit tests. Automatic enrichment is allowed only when the repository name equals the tool name or clearly starts with it.
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
    let isArchived: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case fullName = "full_name"
        case description
        case isArchived = "archived"
    }
}

private struct GitHubSearchResponse: Decodable {
    let items: [GitHubRepoItem]
}
