import Foundation

/// P2-A 的远程发现条目。它只表示可浏览的公开 GitHub 元数据，绝不是本地工具、安装计划或可执行命令。
struct DiscoveryItem: Codable, Identifiable, Equatable, Sendable {
    let repositoryID: Int
    let repositoryFullName: String
    let name: String
    let summary: String?
    let repositoryURL: URL
    let licenseName: String?
    let topics: [String]
    let starCount: Int
    let forkCount: Int
    let createdAt: Date
    let pushedAt: Date?
    let isArchived: Bool
    let isFork: Bool

    var id: Int { repositoryID }
}

/// 网络刷新后的最小本地缓存。缓存只保存发现页展示字段、响应验证器和时间；不保存用户工具、命令、路径、变量值或 GitHub 身份。
struct DiscoveryCacheSnapshot: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let fetchedAt: Date
    let query: String
    let entityTag: String?
    let isIncomplete: Bool
    let items: [DiscoveryItem]

    init(
        fetchedAt: Date,
        query: String,
        entityTag: String?,
        isIncomplete: Bool,
        items: [DiscoveryItem]
    ) {
        schemaVersion = Self.schemaVersion
        self.fetchedAt = fetchedAt
        self.query = query
        self.entityTag = entityTag
        self.isIncomplete = isIncomplete
        self.items = items
    }
}

/// 发现预览的本地缓存，不使用 SwiftData，避免远程条目进入工具库备份或影响既有 store 迁移。
enum DiscoveryCacheStore {
    private static let storageKey = "TermiPad.discoveryPreview.cache.v1"

    static func load(defaults: UserDefaults = .standard) -> DiscoveryCacheSnapshot? {
        guard let data = defaults.data(forKey: storageKey),
              let snapshot = try? JSONDecoder.discoveryPreview.decode(DiscoveryCacheSnapshot.self, from: data),
              snapshot.schemaVersion == DiscoveryCacheSnapshot.schemaVersion else {
            return nil
        }
        return snapshot
    }

    static func save(_ snapshot: DiscoveryCacheSnapshot, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder.discoveryPreview.encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }
}

/// 仅使用公开仓库字段构成的本地排序规则。分数用于排序和解释，永远不是安全评级、官方排名或安装建议。
enum DiscoveryRanking {
    struct Evidence: Equatable, Sendable {
        let score: Int
        let hasLicense: Bool
        let hasCLITopic: Bool
        let isRecentlyActive: Bool
        let isPopular: Bool
    }

    static func visibleItems(from items: [DiscoveryItem], now: Date = Date()) -> [DiscoveryItem] {
        items
            .filter { !$0.isArchived && !$0.isFork && !$0.repositoryFullName.isEmpty && !$0.name.isEmpty }
            .sorted {
                let left = evidence(for: $0, now: now)
                let right = evidence(for: $1, now: now)
                if left.score == right.score {
                    return $0.repositoryFullName.localizedCaseInsensitiveCompare($1.repositoryFullName) == .orderedAscending
                }
                return left.score > right.score
            }
    }

    static func evidence(for item: DiscoveryItem, now: Date = Date()) -> Evidence {
        let hasLicense = item.licenseName?.isEmpty == false
        let hasCLITopic = item.topics.contains { topic in
            let normalized = topic.lowercased()
            return normalized == "cli" || normalized == "command-line" || normalized == "terminal"
        }
        let isRecentlyActive = item.pushedAt.map { now.timeIntervalSince($0) <= 90 * 24 * 60 * 60 } ?? false
        let isPopular = item.starCount >= 500

        var score = min(item.starCount / 100, 30)
        if isPopular { score += 10 }
        if isRecentlyActive { score += 20 }
        if hasLicense { score += 8 }
        if hasCLITopic { score += 12 }
        if item.summary?.isEmpty == false { score += 5 }
        score -= min(item.forkCount / 2_000, 5)

        return Evidence(
            score: max(score, 0),
            hasLicense: hasLicense,
            hasCLITopic: hasCLITopic,
            isRecentlyActive: isRecentlyActive,
            isPopular: isPopular
        )
    }

    static func explanation(for item: DiscoveryItem, language: AppLanguage, now: Date = Date()) -> String {
        let evidence = evidence(for: item, now: now)
        var parts: [String] = []
        switch language {
        case .simplifiedChinese:
            if evidence.isPopular { parts.append("公开 Star 较多") }
            if evidence.isRecentlyActive { parts.append("近 90 天有公开推送") }
            if evidence.hasCLITopic { parts.append("标记为 CLI/终端项目") }
            if evidence.hasLicense { parts.append("仓库提供许可信息") }
            return parts.isEmpty ? "仅按公开仓库字段展示；未作安全评级。" : parts.joined(separator: "；")
        case .english:
            if evidence.isPopular { parts.append("higher public star count") }
            if evidence.isRecentlyActive { parts.append("public activity within 90 days") }
            if evidence.hasCLITopic { parts.append("tagged as a CLI or terminal project") }
            if evidence.hasLicense { parts.append("license metadata is present") }
            return parts.isEmpty ? "Shown from public repository fields only; this is not a security rating." : parts.joined(separator: "; ")
        }
    }
}

private extension JSONEncoder {
    static var discoveryPreview: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var discoveryPreview: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
