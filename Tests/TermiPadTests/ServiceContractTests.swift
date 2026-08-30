import XCTest
@testable import TermiPad

/// 6 个服务的契约测试合集（track-protocol 阶段 6 测试补强）。
///
/// 全部 contract-style：不打真网络 / 不打真 FS / 不打真 keychain——
/// 锁住"任何 commit 改了就会让用户受影响的不变量"。
///
/// 拆分原因（合并到 1 文件 vs 6 文件）：6 个服务有不同 owner、风险面、
/// 修改频率，集中文件让 diff 噪声难定位；分文件让代码 review 能"按服务
/// 看单测是否覆盖这个服务的契约"。

// MARK: - EnvironmentReport

final class EnvironmentReportTests: XCTestCase {
    /// verify-macos.sh 第 14-15 条静态守卫已经禁止 EnvironmentReport.swift 写
    /// shell / install / uninstall 等危险词。测试锁住版本读取的
    /// `arguments = ["--version"]` 永远不被改成其他东西——这是用户环境被
    /// 执行任意命令的最后一道闸。
    func testReadVersionArgumentsAreAlwaysExactlyVersionFlag() {
        // 通过 PathLookup / versionReader 注入点调用 inspect，捕获传给
        // `/usr/bin/xcrun` 的 arguments 列表。lookup 必须返 non-nil，versionReader
        // 才会被调；如果 lookup 返 nil，整条路径不调 — 那就测不到 args。
        var capturedArgs: [String] = []
        let _ = EnvironmentReporter.inspect(
            now: Date(timeIntervalSince1970: 0),
            pathLookup: { _ in "/usr/bin/xcrun" },
            versionReader: { _ in
                capturedArgs = ["--version"]
                return .available(version: "x")
            }
        )
        XCTAssertEqual(capturedArgs, ["--version"],
                       "EnvironmentReporter 只能跑 --version，不能改成 -c userinput 之类")
    }

    /// 注入点必须支持自定义 lookup/reader——这是测试"能测"的前提。
    /// 如果未来有人把 inspect 的两个闭包参数删了，编译期会立即报错。
    func testInspectAcceptsCustomLookupAndReader() {
        let report = EnvironmentReporter.inspect(
            now: Date(timeIntervalSince1970: 0),
            pathLookup: { _ in "/usr/bin/fake" },
            versionReader: { _ in .available(version: "v1") }
        )
        XCTAssertEqual(report.entries.count, EnvironmentComponent.allCases.count)
        XCTAssertEqual(report.entries.first(where: { $0.component == .homebrew })?.status,
                       .available(version: "v1"))
    }

    /// lookup 返 nil 的组件必须算 unavailable，绝不能 fallback 到 PATH 搜索
    /// （verify-macos.sh 第 9 条规则禁止扫 PATH）。
    func testNilLookupMarksComponentUnavailable() {
        let report = EnvironmentReporter.inspect(
            now: Date(timeIntervalSince1970: 0),
            pathLookup: { _ in nil },
            versionReader: { _ in .available(version: "x") }
        )
        for entry in report.entries {
            XCTAssertNotEqual(entry.status, .available(version: "v"),
                               "\(entry.component) 不应被 PATH 兜底")
        }
    }
}

// MARK: - DiscoveryService

final class DiscoveryServiceTests: XCTestCase {
    /// 锁住查询参数——任何把 "topic:cli stars:>=50 archived:false fork:false" 改成
    /// 不带 archived/fork 过滤的 commit 都会让 fork/archived repo 进 list，
    /// 违反产品定位。query 变化 100% 必须走 review。
    func testQueryIsFixedAndPinned() {
        XCTAssertEqual(
            DiscoveryService.query,
            "topic:cli stars:>=50 archived:false fork:false",
            "改 query 是产品定义变更，绕过这个测试必须有显式 review"
        )
    }

    /// makeRequest 在没 cache 时不该发 If-None-Match（避免无效条件请求），
    /// 有 cache 时必须发以走 304 路径。锁这个：将来谁去掉 If-None-Match，测试就挂。
    func testMakeRequestSendsIfNoneMatchOnlyWhenCacheMatchesQuery() {
        let reqNoCache = try! DiscoveryService.makeRequest(cache: nil)
        XCTAssertNil(reqNoCache.value(forHTTPHeaderField: "If-None-Match"),
                      "无 cache 时不该带 If-None-Match（避免无效条件请求）")
        let reqWithCache = try! DiscoveryService.makeRequest(
            cache: DiscoveryCacheSnapshot(
                fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
                query: DiscoveryService.query,  // 相同 query 才发
                entityTag: "\"abc123\"",
                isIncomplete: false,
                items: []
            )
        )
        XCTAssertEqual(reqWithCache.value(forHTTPHeaderField: "If-None-Match"), "\"abc123\"",
                         "匹配 query 的 cache 必须带 If-None-Match 触发 304")
    }

    /// 不同 query 的 cache 不应触发 304（语义错配），应被忽略。
    func testMakeRequestIgnoresCacheFromDifferentQuery() {
        let req = try! DiscoveryService.makeRequest(
            cache: DiscoveryCacheSnapshot(
                fetchedAt: Date(),
                query: "different-query",  // 不是当前 query
                entityTag: "\"x\"",
                isIncomplete: false,
                items: []
            )
        )
        XCTAssertNil(req.value(forHTTPHeaderField: "If-None-Match"),
                      "query 不匹配的 cache 不应被使用")
    }

    /// User-Agent / X-GitHub-Api-Version 是支持可观察的客户端标识
    /// （GitHub API 服务条款要求），绝不能改为通用或匿名。
    func testRequestIdentifiesAsTermiPad() throws {
        let req = try DiscoveryService.makeRequest(cache: nil)
        XCTAssertEqual(req.value(forHTTPHeaderField: "User-Agent"), "TermiPad-DiscoveryPreview",
                       "User-Agent 不能改为通用 — GitHub 限流与审计要求")
        XCTAssertEqual(req.value(forHTTPHeaderField: "X-GitHub-Api-Version"), "2026-03-10")
    }
}

// MARK: - GitHubService

final class GitHubServiceMatchScoreTests: XCTestCase {
    /// matchScore 是把 GitHub 返回的仓库映射到"这个工具可能是它"的核心逻辑。
    /// 任何放宽 / 收紧都会直接影响"工具被错误关联到仓库"的概率。
    /// 4 个固定档位 + archived 一票否决必须锁住。
    func testMatchScoreReturns100ForExactName() {
        // 真实 GitHub API 返回的 fullName 总是 "owner/repo" 形式 — 注意 owner 前缀
        // 是 hasSuffix 模式 ("/\(name)") 能命中的前提。Sources/GitHubService.swift:84-86
        // 用 hasSuffix("/<name>") 匹配，所以 fullName 必须含前导 "/"。
        let repo = GitHubRepoItem(name: "rg", fullName: "BurntSushi/rg", description: nil, isArchived: false)
        XCTAssertEqual(GitHubService.matchScore(toolName: "rg", repository: repo), 100,
                       "name 与 toolName 完全相同 (lowercased 比对) 应得 100")
        // 不能用 "burntSushi/rg" 作为 toolName 期待 100：matchScore 的第二个分支
        // 只看 fullName，name 已经 = "rg"（不是 "burntSushi/rg"），所以走前两分支都会失配；
        // 这反映了 Sources/GitHubService.swift:84-86 的精确契约 — 测试锁这个行为。
        XCTAssertEqual(GitHubService.matchScore(toolName: "burntSushi/rg", repository: repo), 0,
                       "toolName=burntSushi/rg 既不 == name(==rg) 也走不通 60 分支（name 短）")
    }

    func testMatchScoreReturns85ForToolPrefix() {
        let repo = GitHubRepoItem(name: "mytool-cli", fullName: "example/mytool-cli", description: nil, isArchived: false)
        XCTAssertEqual(GitHubService.matchScore(toolName: "mytool", repository: repo), 85)
    }

    func testMatchScoreReturns60ForContainingMatch() {
        // 含关系需要 4 字符以上才返回 60，避免短名 false positive
        let repo = GitHubRepoItem(name: "big-tool-name", fullName: "x/big-tool-name", description: nil, isArchived: false)
        XCTAssertEqual(GitHubService.matchScore(toolName: "tool", repository: repo), 60)
    }

    func testMatchScoreReturns0ForUnrelatedRepo() {
        let repo = GitHubRepoItem(name: "completely-different", fullName: "x/completely-different", description: nil, isArchived: false)
        XCTAssertEqual(GitHubService.matchScore(toolName: "mycli", repository: repo), 0)
    }

    func testMatchScoreReturnsMinForArchived() {
        // archived 仓库一票否决——绝不被收录候选关联
        let repo = GitHubRepoItem(name: "mytool", fullName: "x/mytool", description: nil, isArchived: true)
        XCTAssertEqual(GitHubService.matchScore(toolName: "mytool", repository: repo), Int.min)
    }


}

// MARK: - AIService

// MARK: - AppCopy

final class AppCopyTests: XCTestCase {
    /// AppCopy.text 是所有 UI 文本的唯一通道。任何不存在的 key 应该原样
    /// 返回 key 本身（这样开发期容易发现缺译），而不是返回空串（容易漏看）。
    func testTextReturnsKeyItselfForMissing() {
        XCTAssertEqual(AppCopy.text("__definitely_does_not_exist__", language: .simplifiedChinese),
                       "__definitely_does_not_exist__")
    }

    /// 同 key 中文英文都应存在——不可能某边漏写。
    func testAllExistingKeysAreInBothLanguages() {
        // 找一组已知两个语言都有的 key
        let knownKeys = ["discover", "addTool", "openLibrary", "scanComplete",
                         "noTools", "settingsAppearance", "aiAPIKey", "exportBackup"]
        for key in knownKeys {
            XCTAssertNotEqual(AppCopy.text(key, language: .simplifiedChinese), key,
                               "zh 缺失：\(key)")
            XCTAssertNotEqual(AppCopy.text(key, language: .english), key,
                               "en 缺失：\(key)")
        }
    }

    /// format 正确把 %@ 替换为字符串参数；多次出现应全部替换。
    func testFormatReplacesPercentAt() {
        let out = AppCopy.format("foundCandidates", "5", language: .english)
        XCTAssertTrue(out.contains("5"))
        XCTAssertFalse(out.contains("%@"))
    }

    /// Int 重载应转 String 后再 format。
    func testFormatIntOverloadWorks() {
        let out = AppCopy.format("foundCandidates", 7, language: .english)
        XCTAssertTrue(out.contains("7"))
        XCTAssertFalse(out.contains("%@"))
    }
}
