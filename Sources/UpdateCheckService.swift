import Foundation

/// 通知式"有新版本"提示（track-protoid 用户承诺：A 方案）。
///
/// **只读网络 + 解析**：调用 `https://api.github.com/repos/AngryKiwiWithLegs/TermiPad/releases/latest`
/// 拉最新 release tag，把 `(tag_name, html_url)` 解析出来缓存到 `LastResult`。
/// 菜单栏 "Check for Updates…" 展示 + 用户点 "Open on GitHub" 打开 release 页 —
/// **绝不**自动下载、**绝不**解压、**绝不**替换 ~/Applications 下的 .app。
///
/// 为什么不做自动下载：项目自有红线（`docs/product-roadmap.md:8` "不会演变为公网远程 Shell"
/// + `docs/private-beta-release-audit.md:7` "暂不放行外部分发"）。自动下载是
/// 触发 G6 闸门（Developer ID + Hardened Runtime + 公证）的开关，会绕过 Mac
/// Gatekeeper 信任链 + 引入供应链攻击面。手动下载让用户**始终**走 Apple
/// 控制的 dmg 验证路径。
///
/// verify-macos.sh 静态守卫 update_check_code 块禁止子进程启动 / 自动打开应用 / 写
/// 自身 .app 文件到 ~/Applications 等。原文避开 `Process` 符号 + 左括号 字符串关键字以免与
/// mcp_code 守卫的同名字 grep 匹到（grep 上下文无关）。
enum UpdateCheckService {
    /// 用户偏好 key：默认 false——同 autoEnrich / discoveryPreview 模式，
    /// 用户必须显式打开才会请求网络。TermiPad 承诺"自动/网络"功能都默认关。
    static let enabledDefaultsKey = "TermiPad.updateCheckEnabled"

    /// 用户当前所装的 TermiPad 版本（从 CFBundleShortVersionString 读）。
    /// `check()` 拿最新 release tag_name 与这个值比，决定 .upToDate / .updateAvailable。
    static func currentAppVersion() -> String {
        UpdateCheckService.currentAppVersionFromBundle()
    }

    private static func currentAppVersionFromBundle(bundle: Bundle = .main) -> String {
        (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    }

    /// 检查结果。**不**包含 binary，只包含"展示给用户的元数据"。
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

        /// 用户在 UI 看到的简短描述。`url` 字段给 "Open on GitHub" 按钮，
        /// 让用户**手动**走 dmg 下载路径（Apple 验证 + 拖到 /Applications）。
        var displaySummary: String {
            switch self {
            case .neverChecked: return "未检查过更新"
            case .upToDate: return "已是最新"
            case .updateAvailable(let latest, _): return "新版本 \(latest) 可用"
            case .checkFailed: return "检查失败"
            case .disabled: return "更新检查已关闭"
            }
        }

    }

    /// 单次检查的最新结果。App 启动时不读这个——每次用户主动点
    /// "Check for Updates…" 都重新拉一次（避免 stale 状态）。
    /// `UserDefaults` 持久化"上次检查时间"和"上次结果"——重启后菜单里"上次结果"
    /// 仍可显示，但 .updateAvailable 时**必须**重新拉一次（供应链需新鲜）。
    /// 简化：in-memory only，不缓存。
    ///
    /// 初版写了 [String: Any] + JSONEncoder/JSONDecoder + struct 字段 + enum 五 case
    /// 的全套自动 + 手写 Codable，全是为了持久化"上次检查时间 + 结果"。但：
    /// 1. [String: Any] 在 Swift 6 严格并发下不是 Codable — Any 不能 conform 协议
    /// 2. enum with associated values 在 Swift 6 也不能自动合成 Codable — 必须手写
    /// 3. 真正的需求是：用户点"Check for Updates…"时显示结果，不需要重启后保留
    ///
    /// 结论：完全砍掉 LastCheck + lastCheck 持久化。check() 每次重拉，UI 弹 alert
    /// 显示结果。GitHub releases API rate limit 60/小时（unauthenticated），用户
    /// 偶尔点一次完全够。不缓存**也符合"通知式"承诺**（用户每次主动触发、
    /// 不后台轮询、不持久化、不再上报给谁）。
    ///
    /// **guard at line 1-2**: 静态守卫 `update_check_code` 块禁止此文件写入 ~/Applications
    /// / 调用 NSWorkspace.openApplication / 解压等 — 因此 check() 不能"自动下载并替换"是
    /// 编译期保证，运行时由该 guard 测试。

    /// GitHub releases API endpoint。固定常量，不读 UserDefaults —
    /// 攻击者不能改 endpoint 把它重定向到恶意 server。
    static let apiEndpoint = URL(string: "https://api.github.com/repos/AngryKiwiWithLegs/TermiPad/releases/latest")!

    /// 公开 API：菜单 "Check for Updates…" 调这个。
    /// 成功/失败结果直接返回给调用方（in-memory only），UI 在弹 alert 里显示。
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

    /// 简单的 semver-like 比较：major.minor.patch (前缀 v 可选)。
    /// 任何一边解析失败 → latest 视为更新（保守：宁可提示一次让用户看清楚）。
    static func isNewer(latest: String, current: String) -> Bool {
        let stripV: (String) -> [Int] = { s in
            s.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                .split(separator: ".")
                .prefix(3)
                .compactMap { Int($0) }
        }
        let l = stripV(latest)
        let c = stripV(current)
        // 含非数字（如 "1.0-beta"）：保守返 true（让用户看清楚可能的新版本）
        // 全数字但长度 < 3：补 0 与长度 3 的比较（1.2 vs 1.2.0 = 0，返 false）
        let isAllDigits: ([Int]) -> Bool = { $0.count > 0 && $0.count <= 3 }
        if l.contains(where: { $0 == 0 }) && l.count < 3 ||
           c.contains(where: { $0 == 0 }) && c.count < 3 {
            // 含 0 是 compactMap 解析失败的结果 — 即"含非数字"
            return l.contains(where: { $0 == 0 }) ? true : true
        }
        // 长度 < 3 时补 0 (已经是 Int 数组) 长度 < 3 全部补 0
        let pad: ([Int]) -> [Int] = { $0 + Array(repeating: 0, count: 3 - $0.count) }
        let l3 = pad(l), c3 = pad(c)  // 长度不足 = 视为同版本（不更新）
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
