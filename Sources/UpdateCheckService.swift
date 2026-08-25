import Foundation

struct UpdateManifest: Codable, Equatable {
    let version: String
    let releaseNotesURL: URL?
}

enum UpdateCheckError: LocalizedError, Equatable {
    case invalidFeedURL
    case insecureFeedURL
    case invalidReleaseNotesURL
    case unsupportedVersion
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalidFeedURL: return "更新源地址无效。"
        case .insecureFeedURL: return "更新源必须使用 HTTPS。"
        case .invalidReleaseNotesURL: return "更新说明地址必须使用 HTTPS。"
        case .unsupportedVersion: return "更新源中的版本格式不受支持。"
        case .unavailable: return "暂时无法检查更新。"
        }
    }
}

/// 私有 beta 的保守更新检查：只读取用户明确配置的 HTTPS JSON，不下载、不安装、不执行任何文件。
enum UpdateCheckService {
    static func validatedFeedURL(_ rawValue: String) throws -> URL {
        guard let url = URL(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host,
              !host.isEmpty else {
            throw UpdateCheckError.invalidFeedURL
        }
        guard url.scheme?.lowercased() == "https" else {
            throw UpdateCheckError.insecureFeedURL
        }
        return url
    }

    static func check(feedURL rawValue: String, currentVersion: String) async throws -> UpdateManifest? {
        let feedURL = try validatedFeedURL(rawValue)
        var request = URLRequest(url: feedURL)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw UpdateCheckError.unavailable
            }
            let manifest = try JSONDecoder().decode(UpdateManifest.self, from: data)
            if let releaseNotesURL = manifest.releaseNotesURL,
               releaseNotesURL.scheme?.lowercased() != "https" {
                throw UpdateCheckError.invalidReleaseNotesURL
            }
            guard let comparison = compare(manifest.version, to: currentVersion) else {
                throw UpdateCheckError.unsupportedVersion
            }
            return comparison == .orderedDescending ? manifest : nil
        } catch let error as UpdateCheckError {
            throw error
        } catch {
            throw UpdateCheckError.unavailable
        }
    }

    static func compare(_ candidate: String, to current: String) -> ComparisonResult? {
        guard let candidateParts = numericVersionParts(candidate),
              let currentParts = numericVersionParts(current) else {
            return nil
        }
        for (left, right) in zip(candidateParts, currentParts) {
            if left < right { return .orderedAscending }
            if left > right { return .orderedDescending }
        }
        return .orderedSame
    }

    static func currentAppVersion(bundle: Bundle = .main) -> String {
        (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    }

    private static func numericVersionParts(_ value: String) -> [Int]? {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !components.isEmpty, components.count <= 3 else { return nil }
        var values: [Int] = []
        for component in components {
            guard let integer = Int(component), integer >= 0 else { return nil }
            values.append(integer)
        }
        return values + Array(repeating: 0, count: 3 - values.count)
    }
}
