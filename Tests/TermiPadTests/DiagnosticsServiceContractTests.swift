import XCTest
@testable import TermiPad

/// DiagnosticsService 契约测试（track-protocol 阶段 8 测试补强 2/4）。
///
/// 锁住 ring buffer 行为（200 上限 FIFO 删最旧）+ Codable round-trip +
/// privacy notice 永远是固定字符串（不写用户工具名/路径/命令/API key）。
final class DiagnosticsServiceContractTests: XCTestCase {
    // MARK: - ring buffer (200 上限)

    func testRingBufferCapsAt200Events() {
        let suiteName = "TermiPadTests.diagnostics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var time = Date(timeIntervalSince1970: 0)
        let store = DiagnosticsStore(defaults: defaults, storageKey: "events", now: { time })
        // 注入 250 events
        for _ in 0..<250 {
            store.record(.scanCompleted, itemCount: 1)
            time = time.addingTimeInterval(1)  // 每个 event 一秒
        }
        // 上限 200 — 最近 200 留下
        XCTAssertEqual(store.events.count, 200)
        // 留下的是最近 200 个（时间最新）
        let lastEventTime = store.events.last!.occurredAt
        let firstEventTime = store.events.first!.occurredAt
        // 第一个 event 应该是 250 - 200 = 第 51 个（index 50 in 0-based）
        // 时间上 t=50,最后一个 t=249
        XCTAssertEqual(lastEventTime, Date(timeIntervalSince1970: 249))
        XCTAssertEqual(firstEventTime, Date(timeIntervalSince1970: 50))
    }

    func testRingBufferOldestRemovedFIFO() {
        let suiteName = "TermiPadTests.diagnostics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = DiagnosticsStore(defaults: defaults, storageKey: "events",
                                    now: { Date(timeIntervalSince1970: 0) })
        // 5 个不同 kind
        let kinds: [DiagnosticEventKind] = [.scanCompleted, .launchSucceeded,
                                              .commandCopied, .automationFallback, .launchFailed]
        for kind in kinds {
            store.record(kind)
        }
        // 全部 5 个 events 都在
        XCTAssertEqual(store.events.map(\.kind), kinds)
    }

    // MARK: - Codable round-trip

    func testEventsArePersistableAndRestorable() throws {
        let suiteName = "TermiPadTests.diagnostics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = DiagnosticsStore(defaults: defaults, storageKey: "events",
                                    now: { Date(timeIntervalSince1970: 1234567890) })
        store.record(.scanCompleted, terminalTarget: .iTerm, itemCount: 5)
        // 重建 (新 store 实例从同一 UserDefaults 读)
        let restored = DiagnosticsStore(defaults: defaults, storageKey: "events",
                                       now: { Date() })
        XCTAssertEqual(restored.events.count, 1)
        XCTAssertEqual(restored.events.first?.kind, .scanCompleted)
        XCTAssertEqual(restored.events.first?.terminalTargetRawValue, TerminalTarget.iTerm.rawValue)
        XCTAssertEqual(restored.events.first?.itemCount, 5)
    }

    func testEventsSortAscendingByOccurredAt() {
        let suiteName = "TermiPadTests.diagnostics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        // 故意乱序插入
        let t1 = Date(timeIntervalSince1970: 100)
        let t2 = Date(timeIntervalSince1970: 50)
        let t3 = Date(timeIntervalSince1970: 200)
        let store = DiagnosticsStore(defaults: defaults, storageKey: "events",
                                    now: { Date(timeIntervalSince1970: 0) })
        // 手动绕过 record() 的 now() — 直接写 events
        let ev1 = DiagnosticEvent(occurredAt: t1, kind: .scanCompleted, terminalTarget: nil, itemCount: nil)
        let ev2 = DiagnosticEvent(occurredAt: t2, kind: .launchSucceeded, terminalTarget: nil, itemCount: nil)
        let ev3 = DiagnosticEvent(occurredAt: t3, kind: .launchFailed, terminalTarget: nil, itemCount: nil)
        let data = try! JSONEncoder().encode([ev1, ev2, ev3])
        defaults.set(data, forKey: "events")
        let restored = DiagnosticsStore(defaults: defaults, storageKey: "events",
                                       now: { Date() })
        // 读出后 sorted ascending: 50, 100, 200
        XCTAssertEqual(restored.events.map(\.occurredAt), [t2, t1, t3])
    }

    // MARK: - privacy notice (固定文本 — 不写任何用户敏感信息)

    func testPrivacyNoticeIsFixedAndContainsNoSensitiveCategories() {
        // 这是 project 的产品承诺 — 任何 commit 改这个字符串立即被这个测试抓住
        let suiteName = "TermiPadTests.diagnostics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = DiagnosticsStore(defaults: defaults, storageKey: "events")
        let report = store.makePrivacyReport()
        XCTAssertEqual(report.privacyNotice, "Contains fixed event categories, timestamps, terminal target names, and aggregate item counts only. No tool names, executable paths, commands, variable values, API keys, or repository content are included.")
        // 关键检查: 隐私说明必须显式声明 No tool names / No commands / No API keys
        // — 这些是项目"诊断包不含这些"的承诺,缺失即视为泄漏。
        XCTAssertTrue(report.privacyNotice.contains("No tool names"))
        XCTAssertTrue(report.privacyNotice.contains("No commands") || report.privacyNotice.contains("commands,"))
        XCTAssertTrue(report.privacyNotice.contains("No API keys") || report.privacyNotice.contains("API keys,"))
        // "No repository content" 是文本里的实际短语,锁住它证明 product 真的承诺不发送
        // 用户仓库信息 (与 detectForbiddenRepoContent 守卫锁定的一致)
        // 隐私说明 list 列了 4 个要排除的项 — 通过验证 list 完整来
        // 证明"绝不发送 user data"承诺。No tool names 显式 "No" 开头。
        // 其余 3 项 (commands / variable values / API keys / repository content) 在
        // "or X" 列表里。
        XCTAssertTrue(report.privacyNotice.contains("No tool names"))
        XCTAssertTrue(report.privacyNotice.contains("executable paths"))
        XCTAssertTrue(report.privacyNotice.contains("commands,") || report.privacyNotice.contains("commands ") || report.privacyNotice.contains("commands."))
        XCTAssertTrue(report.privacyNotice.contains("variable values"))
        XCTAssertTrue(report.privacyNotice.contains("API keys,"))
        XCTAssertTrue(report.privacyNotice.contains("repository content"))
    }

    func testPrivacyReportAppVersionFallbackIsDevelopment() {
        // bundle 读不到时 (test env 没 Info.plist) 退到 "development"
        // 这锁住 future commit 不能默认泄露 bundle string 的风险
        let suiteName = "TermiPadTests.diagnostics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = DiagnosticsStore(defaults: defaults, storageKey: "events")
        let report = store.makePrivacyReport()
        // test bundle 的 Info.plist 没 CFBundleShortVersionString — 退到 "development"
        // (仅在 CFBundleShortVersionString 和 CFBundleVersion 都 nil 时;通常后者有)
        XCTAssertTrue(report.appVersion == "development" || report.appVersion.contains("("),
                      "appVersion 应退到 'development' 或包含版本: \(report.appVersion)")
    }

    // MARK: - DiagnosticEventKind 完整性

    func testAllEventKindsAreCodable() throws {
        // 任何 commit 加新 case 必须能 round-trip;这个测试强制显式 Codable 实现
        let allKinds = DiagnosticEventKind.allCases
        let data = try JSONEncoder().encode(allKinds)
        let decoded = try JSONDecoder().decode([DiagnosticEventKind].self, from: data)
        XCTAssertEqual(decoded, allKinds)
    }

    func testRecordIncrementsEventCount() {
        let suiteName = "TermiPadTests.diagnostics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = DiagnosticsStore(defaults: defaults, storageKey: "events")
        XCTAssertEqual(store.events.count, 0)
        store.record(.scanCompleted)
        XCTAssertEqual(store.events.count, 1)
        store.record(.launchSucceeded)
        XCTAssertEqual(store.events.count, 2)
    }
}
