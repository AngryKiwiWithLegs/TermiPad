import Foundation

/// GitHub 服务：定位工具仓库、读取 README，并提供仓库组织的品牌头像作为图标候选。
enum GitHubService {
    private static let baseURL = "https://api.github.com"

    struct RepositoryInfo: Sendable {
        let repoFullName: String
        let readmeContent: String
        let ownerAvatarURLString: String?
        let repositoryDescription: String?
    }

    /// 根据工具名称搜索最相关的 GitHub 仓库。
    /// README 获取失败时仍会返回仓库和组织头像信息，使图标识别不依赖 README 可访问性。
    static func findRepository(for toolName: String) async throws -> RepositoryInfo? {
        let query = "\(toolName) topic:cli"
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "\(baseURL)/search/repositories?q=\(encodedQuery)&sort=stars&order=desc") else {
            return nil
        }

        var searchRequest = URLRequest(url: searchURL)
        searchRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        searchRequest.setValue("TermiPad", forHTTPHeaderField: "User-Agent")

        let (searchData, searchResponse) = try await URLSession.shared.data(for: searchRequest)
        guard let searchHTTPResponse = searchResponse as? HTTPURLResponse,
              (200...299).contains(searchHTTPResponse.statusCode) else {
            return nil
        }

        let searchResult = try JSONDecoder().decode(GitHubSearchResponse.self, from: searchData)
        guard let repository = searchResult.items.first else { return nil }

        let readmeContent = await fetchReadme(for: repository.fullName)
        return RepositoryInfo(
            repoFullName: repository.fullName,
            readmeContent: readmeContent ?? repository.description ?? "",
            ownerAvatarURLString: repository.owner?.avatarURLString,
            repositoryDescription: repository.description
        )
    }

    private static func fetchReadme(for repositoryFullName: String) async -> String? {
        guard let url = URL(string: "\(baseURL)/repos/\(repositoryFullName)/readme") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.raw+json", forHTTPHeaderField: "Accept")
        request.setValue("TermiPad", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }
}

private struct GitHubSearchResponse: Decodable {
    let items: [GitHubRepoItem]
}

private struct GitHubRepoItem: Decodable {
    let fullName: String
    let description: String?
    let owner: GitHubRepositoryOwner?

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case description
        case owner
    }
}

private struct GitHubRepositoryOwner: Decodable {
    let avatarURLString: String?

    enum CodingKeys: String, CodingKey {
        case avatarURLString = "avatar_url"
    }
}
