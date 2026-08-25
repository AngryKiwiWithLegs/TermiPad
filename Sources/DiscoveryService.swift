import Foundation

/// P2-A 发现服务。该服务只读取公开 GitHub 仓库元数据；它不会读取用户工具库、README、命令、路径或身份信息，也不会安装或执行任何软件。
enum DiscoveryService {
    static let query = "topic:cli stars:>=50 archived:false fork:false"
    private static let endpoint = URL(string: "https://api.github.com/search/repositories")!

    enum RefreshResult: Equatable {
        case refreshed(DiscoveryCacheSnapshot)
        case notModified(DiscoveryCacheSnapshot)
    }

    enum Error: LocalizedError, Equatable {
        case invalidURL
        case invalidResponse
        case notModifiedWithoutCache
        case rateLimited(retryAfter: Date?)
        case httpStatus(Int)
        case invalidPayload

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "The GitHub discovery request could not be created."
            case .invalidResponse:
                return "GitHub discovery returned an invalid response."
            case .notModifiedWithoutCache:
                return "GitHub reported unchanged results, but no local discovery cache is available."
            case .rateLimited:
                return "GitHub discovery is temporarily rate limited."
            case .httpStatus(let status):
                return "GitHub discovery failed with HTTP status \(status)."
            case .invalidPayload:
                return "GitHub discovery returned an unreadable payload."
            }
        }
    }

    /// 生成固定的公共发现请求。没有认证头、没有用户命令或路径参数，且仅当查询完全一致时才复用缓存 ETag。
    static func makeRequest(cache: DiscoveryCacheSnapshot?) throws -> URLRequest {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "sort", value: "stars"),
            URLQueryItem(name: "order", value: "desc"),
            URLQueryItem(name: "per_page", value: "20")
        ]
        guard let url = components?.url else { throw Error.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("TermiPad-DiscoveryPreview", forHTTPHeaderField: "User-Agent")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let cache, cache.query == query, let entityTag = cache.entityTag, !entityTag.isEmpty {
            request.setValue(entityTag, forHTTPHeaderField: "If-None-Match")
        }
        return request
    }

    /// 只供用户点击“刷新发现”时调用。没有轮询、没有后台任务、没有自动重试。
    static func refresh(
        cache: DiscoveryCacheSnapshot?,
        now: Date = Date(),
        session: URLSession = .shared
    ) async throws -> RefreshResult {
        let request = try makeRequest(cache: cache)
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw Error.invalidResponse
        }

        if response.statusCode == 304 {
            guard let cache else { throw Error.notModifiedWithoutCache }
            return .notModified(cache)
        }
        if response.statusCode == 403 || response.statusCode == 429 {
            throw Error.rateLimited(retryAfter: retryAfterDate(response: response, now: now))
        }
        guard (200...299).contains(response.statusCode) else {
            throw Error.httpStatus(response.statusCode)
        }

        let snapshot = try decodeSnapshot(
            data: data,
            entityTag: response.value(forHTTPHeaderField: "ETag"),
            fetchedAt: now
        )
        return .refreshed(snapshot)
    }

    /// 公开给单元测试的解码边界：仅接受 DiscoveryItem 所需字段，并立即应用非 fork/非 archived 可见性筛选。
    static func decodeSnapshot(data: Data, entityTag: String?, fetchedAt: Date) throws -> DiscoveryCacheSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let response = try? decoder.decode(Response.self, from: data) else {
            throw Error.invalidPayload
        }

        let decoded = response.items.compactMap { repository -> DiscoveryItem? in
            guard let url = URL(string: repository.htmlURL) else { return nil }
            return DiscoveryItem(
                repositoryID: repository.id,
                repositoryFullName: repository.fullName,
                name: repository.name,
                summary: repository.description,
                repositoryURL: url,
                licenseName: repository.license?.name,
                topics: repository.topics,
                starCount: repository.starCount,
                forkCount: repository.forkCount,
                createdAt: repository.createdAt,
                pushedAt: repository.pushedAt,
                isArchived: repository.isArchived,
                isFork: repository.isFork
            )
        }

        return DiscoveryCacheSnapshot(
            fetchedAt: fetchedAt,
            query: query,
            entityTag: entityTag,
            isIncomplete: response.incomplete,
            items: DiscoveryRanking.visibleItems(from: decoded, now: fetchedAt)
        )
    }

    private static func retryAfterDate(response: HTTPURLResponse, now: Date) -> Date? {
        if let secondsText = response.value(forHTTPHeaderField: "Retry-After"),
           let seconds = TimeInterval(secondsText), seconds >= 0 {
            return now.addingTimeInterval(seconds)
        }
        if let resetText = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
           let epoch = TimeInterval(resetText), epoch > 0 {
            return Date(timeIntervalSince1970: epoch)
        }
        return nil
    }
}

private struct Response: Decodable {
    let incomplete: Bool
    let items: [Repository]

    enum CodingKeys: String, CodingKey {
        case incomplete = "incomplete_results"
        case items
    }
}

private struct Repository: Decodable {
    struct License: Decodable {
        let name: String?
    }

    let id: Int
    let fullName: String
    let name: String
    let description: String?
    let htmlURL: String
    let license: License?
    let topics: [String]
    let starCount: Int
    let forkCount: Int
    let createdAt: Date
    let pushedAt: Date?
    let isArchived: Bool
    let isFork: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case name
        case description
        case htmlURL = "html_url"
        case license
        case topics
        case starCount = "stargazers_count"
        case forkCount = "forks_count"
        case createdAt = "created_at"
        case pushedAt = "pushed_at"
        case isArchived = "archived"
        case isFork = "fork"
    }
}
