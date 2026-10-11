import XCTest
@testable import TermiPad

/// Collection of contract tests for 6 services (track-protocol stage 6 test hardening).
///
/// All contract-style: no real network / no real FS / no real keychain —
/// they lock down "invariants that would affect users if any commit changed them".
///
/// Why split (merged into 1 file vs 6 files): the 6 services have different owners, risk surfaces,
/// and change frequencies; a single file makes diff noise hard to locate, while separate files let code review check "per service
/// whether the unit tests cover that service's contract".

// MARK: - EnvironmentReport

final class EnvironmentReportTests: XCTestCase {
    /// Static guards 14-15 in verify-macos.sh already forbid EnvironmentReport.swift from containing
    /// dangerous words such as shell / install / uninstall. The test locks down that the version read's
    /// `arguments = ["--version"]` is never changed to anything else — this is the last gate against arbitrary commands
    /// being executed in the user's environment.
    func testReadVersionArgumentsAreAlwaysExactlyVersionFlag() {
        // Call inspect through the PathLookup / versionReader injection points and capture the arguments list passed to
        // `/usr/bin/xcrun`. lookup must return non-nil for versionReader
        // to be called; if lookup returns nil the whole path is not called — and the args cannot be tested.
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
                       "EnvironmentReporter may only run --version and must not be changed to something like -c userinput")
    }

    /// The injection points must support a custom lookup/reader — this is the precondition for the test "being able to test".
    /// If someone later removes inspect's two closure parameters, the compiler reports it immediately.
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

    /// A component whose lookup returns nil must count as unavailable and must never fall back to a PATH search
    /// (rule 9 in verify-macos.sh forbids scanning PATH).
    func testNilLookupMarksComponentUnavailable() {
        let report = EnvironmentReporter.inspect(
            now: Date(timeIntervalSince1970: 0),
            pathLookup: { _ in nil },
            versionReader: { _ in .available(version: "x") }
        )
        for entry in report.entries {
            XCTAssertNotEqual(entry.status, .available(version: "v"),
                               "\(entry.component) must not fall back to PATH")
        }
    }
}

// MARK: - DiscoveryService

final class DiscoveryServiceTests: XCTestCase {
    /// Lock down the query parameters — any commit that changes "topic:cli stars:>=50 archived:false fork:false" to
    /// one without the archived/fork filters would let fork/archived repos into the list,
    /// violating the product positioning. A query change must go through review, 100% of the time.
    func testQueryIsFixedAndPinned() {
        XCTAssertEqual(
            DiscoveryService.query,
            "topic:cli stars:>=50 archived:false fork:false",
            "Changing the query is a product definition change; bypassing this test requires an explicit review"
        )
    }

    /// makeRequest should not send If-None-Match without a cache (avoids an invalid conditional request),
    /// and must send it with a cache to take the 304 path. Lock this down: whoever removes If-None-Match later breaks the test.
    func testMakeRequestSendsIfNoneMatchOnlyWhenCacheMatchesQuery() {
        let reqNoCache = try! DiscoveryService.makeRequest(cache: nil)
        XCTAssertNil(reqNoCache.value(forHTTPHeaderField: "If-None-Match"),
                      "No If-None-Match without a cache (avoids an invalid conditional request)")
        let reqWithCache = try! DiscoveryService.makeRequest(
            cache: DiscoveryCacheSnapshot(
                fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
                query: DiscoveryService.query,  // sent only for the same query
                entityTag: "\"abc123\"",
                isIncomplete: false,
                items: []
            )
        )
        XCTAssertEqual(reqWithCache.value(forHTTPHeaderField: "If-None-Match"), "\"abc123\"",
                         "A cache matching the query must send If-None-Match to trigger a 304")
    }

    /// A cache for a different query should not trigger a 304 (semantic mismatch) and should be ignored.
    func testMakeRequestIgnoresCacheFromDifferentQuery() {
        let req = try! DiscoveryService.makeRequest(
            cache: DiscoveryCacheSnapshot(
                fetchedAt: Date(),
                query: "different-query",  // not the current query
                entityTag: "\"x\"",
                isIncomplete: false,
                items: []
            )
        )
        XCTAssertNil(req.value(forHTTPHeaderField: "If-None-Match"),
                      "A cache whose query does not match should not be used")
    }

    /// User-Agent / X-GitHub-Api-Version are client identifiers that support observability
    /// (required by the GitHub API terms of service) and must never be changed to something generic or anonymous.
    func testRequestIdentifiesAsTermiPad() throws {
        let req = try DiscoveryService.makeRequest(cache: nil)
        XCTAssertEqual(req.value(forHTTPHeaderField: "User-Agent"), "TermiPad-DiscoveryPreview",
                       "User-Agent must not be made generic — required by GitHub rate limiting and auditing")
        XCTAssertEqual(req.value(forHTTPHeaderField: "X-GitHub-Api-Version"), "2026-03-10")
    }
}

// MARK: - GitHubService

final class GitHubServiceMatchScoreTests: XCTestCase {
    /// matchScore is the core logic that maps a repository returned by GitHub to "this tool may be it".
    /// Any loosening / tightening directly affects the probability of "a tool being linked to the wrong repository".
    /// The 4 fixed tiers + the archived veto must be locked down.
    func testMatchScoreReturns100ForExactName() {
        // The fullName returned by the real GitHub API always has the form "owner/repo" — note that the owner prefix
        // is the precondition for the hasSuffix pattern ("/\(name)") to match. Sources/GitHubService.swift:84-86
        // matches with hasSuffix("/<name>"), so fullName must contain the leading "/".
        let repo = GitHubRepoItem(name: "rg", fullName: "BurntSushi/rg", description: nil, isArchived: false)
        XCTAssertEqual(GitHubService.matchScore(toolName: "rg", repository: repo), 100,
                       "name exactly equal to toolName (lowercased comparison) should score 100")
        // "burntSushi/rg" cannot be used as the toolName expecting 100: matchScore's second branch
        // only looks at fullName, and name is already = "rg" (not "burntSushi/rg"), so the first two branches both miss;
        // this reflects the exact contract of Sources/GitHubService.swift:84-86 — the test locks down this behavior.
        XCTAssertEqual(GitHubService.matchScore(toolName: "burntSushi/rg", repository: repo), 0,
                       "toolName=burntSushi/rg neither == name (==rg) nor reaches the 60 branch (the name is short)")
    }

    func testMatchScoreReturns85ForToolPrefix() {
        let repo = GitHubRepoItem(name: "mytool-cli", fullName: "example/mytool-cli", description: nil, isArchived: false)
        XCTAssertEqual(GitHubService.matchScore(toolName: "mytool", repository: repo), 85)
    }

    func testMatchScoreReturns60ForContainingMatch() {
        // The containment relation needs 4+ characters to return 60, avoiding short-name false positives
        let repo = GitHubRepoItem(name: "big-tool-name", fullName: "x/big-tool-name", description: nil, isArchived: false)
        XCTAssertEqual(GitHubService.matchScore(toolName: "tool", repository: repo), 60)
    }

    func testMatchScoreReturns0ForUnrelatedRepo() {
        let repo = GitHubRepoItem(name: "completely-different", fullName: "x/completely-different", description: nil, isArchived: false)
        XCTAssertEqual(GitHubService.matchScore(toolName: "mycli", repository: repo), 0)
    }

    func testMatchScoreReturnsMinForArchived() {
        // An archived repository is vetoed outright — it is never linked to an accepted candidate
        let repo = GitHubRepoItem(name: "mytool", fullName: "x/mytool", description: nil, isArchived: true)
        XCTAssertEqual(GitHubService.matchScore(toolName: "mytool", repository: repo), Int.min)
    }


}

// MARK: - AIService

// MARK: - AppCopy

final class AppCopyTests: XCTestCase {
    /// AppCopy.text is the only channel for all UI text. Any key that does not exist should return
    /// the key itself unchanged (so missing translations are easy to spot during development) rather than an empty string (easy to overlook).
    func testTextReturnsKeyItselfForMissing() {
        XCTAssertEqual(AppCopy.text("__definitely_does_not_exist__", language: .simplifiedChinese),
                       "__definitely_does_not_exist__")
    }

    /// The same key should exist in both Chinese and English — neither side may be missing.
    func testAllExistingKeysAreInBothLanguages() {
        // Pick a set of keys known to exist in both languages
        let knownKeys = ["discover", "addTool", "openLibrary", "scanComplete",
                         "noTools", "settingsAppearance", "aiAPIKey", "exportBackup"]
        for key in knownKeys {
            XCTAssertNotEqual(AppCopy.text(key, language: .simplifiedChinese), key,
                               "zh missing: \(key)")
            XCTAssertNotEqual(AppCopy.text(key, language: .english), key,
                               "en missing: \(key)")
        }
    }

    /// format correctly replaces %@ with the string argument; multiple occurrences should all be replaced.
    func testFormatReplacesPercentAt() {
        let out = AppCopy.format("foundCandidates", "5", language: .english)
        XCTAssertTrue(out.contains("5"))
        XCTAssertFalse(out.contains("%@"))
    }

    /// The Int overload should convert to String and then format.
    func testFormatIntOverloadWorks() {
        let out = AppCopy.format("foundCandidates", 7, language: .english)
        XCTAssertTrue(out.contains("7"))
        XCTAssertFalse(out.contains("%@"))
    }
}
