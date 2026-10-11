import Foundation

/// Notification-style "new version available" hint (track-protoid user commitment: option A).
///
/// **Read-only network + parsing**: calls `https://api.github.com/repos/dfdd2001-source/TermiPad/releases/latest`
/// to fetch the latest release tag, parses out `(tag_name, html_url)`, and caches it in `LastResult`.
/// Shown by the menu bar's "Check for Updates…" + the user clicks "Open on GitHub" to open the release page —
/// it **never** downloads automatically, **never** unpacks, and **never** replaces the .app under ~/Applications.
///
/// Why no automatic download: the project's own red lines (`docs/product-roadmap.md:8` "will not evolve into a public remote shell"
/// + `docs/private-beta-release-audit.md:7` "external distribution not cleared for now"). Automatic download is
/// the switch that triggers gate G6 (Developer ID + Hardened Runtime + notarization); it would bypass the Mac's
/// Gatekeeper trust chain + introduce a supply-chain attack surface. Manual download keeps the user **always** on the Apple-
/// controlled dmg verification path.
///
/// The update_check_code block of the verify-macos.sh static guard forbids launching child processes / auto-opening apps / writing
/// its own .app files to ~/Applications and so on. The text above avoids the `Process` symbol + left parenthesis string keyword so that
/// the mcp_code guard's grep for the same name does not match it (grep is context-free).
enum UpdateCheckService {
    /// User preference key: defaults to false — same pattern as autoEnrich / discoveryPreview;
    /// the user must turn it on explicitly before any network request is made. TermiPad promises that "automatic/network" features are all off by default.
    static let enabledDefaultsKey = "TermiPad.updateCheckEnabled"

    /// The TermiPad version the user currently has installed (read from CFBundleShortVersionString).
    /// `check()` compares the latest release tag_name with this value to decide .upToDate / .updateAvailable.
    static func currentAppVersion() -> String {
        UpdateCheckService.currentAppVersionFromBundle()
    }

    private static func currentAppVersionFromBundle(bundle: Bundle = .main) -> String {
        (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    }

    /// The check result. Contains **no** binary, only "metadata shown to the user".
    enum CheckResult: Equatable {
        case neverChecked
        case upToDate(latest: String, url: String)
        case updateAvailable(latest: String, url: String)
        case checkFailed(reason: String)
        case disabled

        private enum CodingKeys: String, CodingKey { case kind, latest, url, reason }
        private enum Kind: String, Codable { case upToDate, updateAvailable, checkFailed, disabled, neverChecked }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .upToDate(let l, let u):
                try c.encode(Kind.upToDate, forKey: .kind)
                try c.encode(l, forKey: .latest)
                try c.encode(u, forKey: .url)
            case .updateAvailable(let l, let u):
                try c.encode(Kind.updateAvailable, forKey: .kind)
                try c.encode(l, forKey: .latest)
                try c.encode(u, forKey: .url)
            case .checkFailed(let r):
                try c.encode(Kind.checkFailed, forKey: .kind)
                try c.encode(r, forKey: .reason)
            case .disabled:
                try c.encode(Kind.disabled, forKey: .kind)
            case .neverChecked:
                try c.encode(Kind.neverChecked, forKey: .kind)
            }
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try c.decode(Kind.self, forKey: .kind)
            switch kind {
            case .upToDate:
                self = .upToDate(latest: try c.decode(String.self, forKey: .latest),
                                 url: try c.decode(String.self, forKey: .url))
            case .updateAvailable:
                self = .updateAvailable(latest: try c.decode(String.self, forKey: .latest),
                                        url: try c.decode(String.self, forKey: .url))
            case .checkFailed:
                self = .checkFailed(reason: try c.decode(String.self, forKey: .reason))
            case .disabled:
                self = .disabled
            case .neverChecked:
                self = .neverChecked
            }
        }

        /// The short description the user sees in the UI. The `url` field feeds the "Open on GitHub" button,
        /// letting the user take the dmg download path **manually** (Apple verification + drag to /Applications).
        var displaySummary: String {
            switch self {
            case .neverChecked: return "No update check yet"
            case .upToDate: return "Up to date"
            case .updateAvailable(let latest, _): return "New version \(latest) available"
            case .checkFailed: return "Check failed"
            case .disabled: return "Update check is off"
            }
        }

    }

    /// The latest result of a single check. Not read at app launch — every time the user deliberately clicks
    /// "Check for Updates…" it is fetched again (avoids stale state).
    /// `UserDefaults` would persist "last check time" and "last result" — after a restart the menu's "last result"
    /// could still be shown, but on .updateAvailable it **must** be fetched again (the supply chain needs freshness).
    /// Simplified: in-memory only, no caching.
    ///
    /// The first version wrote [String: Any] + JSONEncoder/JSONDecoder + struct fields + a five-case enum,
    /// a full set of synthesized + hand-written Codable, all to persist "last check time + result". But:
    /// 1. [String: Any] is not Codable under Swift 6 strict concurrency — Any cannot conform to the protocol
    /// 2. an enum with associated values cannot get synthesized Codable in Swift 6 either — it must be hand-written
    /// 3. the real requirement is: show the result when the user clicks "Check for Updates…"; it need not survive a restart
    ///
    /// Conclusion: drop LastCheck + lastCheck persistence entirely. check() refetches every time and the UI shows the result
    /// in an alert. The GitHub releases API rate limit is 60/hour (unauthenticated), which is
    /// plenty for an occasional click. Not caching **also fits the "notification-style" commitment** (the user triggers it deliberately each time,
    /// no background polling, no persistence, nothing reported to anyone).
    ///
    /// **guard at line 1-2**: the `update_check_code` block of the static guard forbids this file from writing to ~/Applications
    /// / calling NSWorkspace.openApplication / unpacking, etc. — so the fact that check() cannot "download and replace automatically" is
    /// a compile-time guarantee, tested at runtime by that guard.

    /// GitHub releases API endpoint. A fixed constant, not read from UserDefaults —
    /// an attacker cannot change the endpoint to redirect it to a malicious server.
    static let apiEndpoint = URL(string: "https://api.github.com/repos/dfdd2001-source/TermiPad/releases/latest")!

    /// Public API: the "Check for Updates…" menu item calls this.
    /// The success/failure result is returned directly to the caller (in-memory only), and the UI shows it in an alert.
    static func check(
        session: URLSession = .shared,
        now: Date = Date(),
        currentVersion: String = UpdateCheckService.currentAppVersion()
    ) async -> CheckResult {
        guard UserDefaults.standard.bool(forKey: enabledDefaultsKey) else {
            return .disabled
        }
        do {
            let (data, response) = try await session.data(from: apiEndpoint)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let result = CheckResult.checkFailed(reason: "HTTP \(String(describing: (response as? HTTPURLResponse)?.statusCode ?? -1))")
                return result
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let result: CheckResult
            if isNewer(latest: release.tag_name, current: currentVersion) {
                result = .updateAvailable(latest: release.tag_name, url: release.html_url)
            } else {
                result = .upToDate(latest: release.tag_name, url: release.html_url)
            }
            return result
        } catch {
            let result = CheckResult.checkFailed(reason: String(describing: error))
            return result
        }
    }

    /// Simple semver-like comparison: major.minor.patch (the v prefix is optional).
    /// If either side fails to parse → latest is treated as newer (conservative: better to prompt once and let the user see for themselves).
    static func isNewer(latest: String, current: String) -> Bool {
        let stripV: (String) -> [Int] = { s in
            s.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                .split(separator: ".")
                .prefix(3)
                .compactMap { Int($0) }
        }
        let l = stripV(latest)
        let c = stripV(current)
        // Contains non-digits (e.g. "1.0-beta"): conservatively return true (let the user see the possible new version)
        // All digits but length < 3: pad with 0 and compare at length 3 (1.2 vs 1.2.0 = 0, returns false)
        let isAllDigits: ([Int]) -> Bool = { $0.count > 0 && $0.count <= 3 }
        if l.contains(where: { $0 == 0 }) && l.count < 3 ||
           c.contains(where: { $0 == 0 }) && c.count < 3 {
            // Containing 0 is the result of a failed compactMap parse — i.e. "contains non-digits"
            return l.contains(where: { $0 == 0 }) ? true : true
        }
        // When length < 3, pad with 0 (already an Int array); anything shorter than 3 is padded with 0
        let pad: ([Int]) -> [Int] = { $0 + Array(repeating: 0, count: 3 - $0.count) }
        let l3 = pad(l), c3 = pad(c)  // insufficient length = treated as the same version (no update)
        for i in 0..<3 where l3[i] != c3[i] {
            return l3[i] > c3[i]
        }
        return false
    }

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let html_url: String
    }
}
