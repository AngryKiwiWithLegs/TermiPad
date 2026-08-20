import Foundation

/// GitHub 服务类：负责搜索工具仓库并获取 README 内容
class GitHubService {
    private static let baseURL = "https://api.github.com"
    
    /// 根据工具名称搜索最相关的 GitHub 仓库
    static func findRepository(for toolName: String) async throws -> (repoFullName: String, readmeContent: String)? {
        // 1. 搜索仓库
        let query = "\(toolName) topic:cli"
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "\(baseURL)/search/repositories?q=\(encodedQuery)&sort=stars&order=desc") else {
            return nil
        }
        
        var request = URLRequest(url: searchURL)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        // 注意：在实际 macOS 应用中，建议引导用户输入 GitHub Token 以避免速率限制
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let searchResult = try JSONDecoder().decode(GitHubSearchResponse.self, from: data)
        
        guard let firstRepo = searchResult.items.first else {
            return nil
        }
        
        // 2. 获取该仓库的 README 内容
        let readmeURL = URL(string: "\(baseURL)/repos/\(firstRepo.full_name)/readme")!
        var readmeRequest = URLRequest(url: readmeURL)
        readmeRequest.setValue("application/vnd.github.v3.raw", forHTTPHeaderField: "Accept")
        
        let (readmeData, _) = try await URLSession.shared.data(for: readmeRequest)
        guard let readmeString = String(data: readmeData, encoding: .utf8) else {
            return nil
        }
        
        return (firstRepo.full_name, readmeString)
    }
}

// MARK: - API Response Models
struct GitHubSearchResponse: Codable {
    let items: [GitHubRepoItem]
}

struct GitHubRepoItem: Codable {
    let full_name: String
    let html_url: String
    let description: String?
    let stargazers_count: Int
}
