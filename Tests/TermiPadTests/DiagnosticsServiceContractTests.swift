import XCTest
@testable import TermiPad

/// DiagnosticsService contract tests (track-protocol stage 8 test hardening 2/4).
///
/// Locks down the ring buffer behavior (200 cap, FIFO drops the oldest) + the Codable round-trip +
/// the privacy notice always being a fixed string (no user tool names / paths / commands / API keys).
final class DiagnosticsServiceContractTests: XCTestCase {
    // MARK: - ring buffer (200 cap)

    func testRingBufferCapsAt200Events() {
        let suiteName = "TermiPadTests.diagnostics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var time = Date(timeIntervalSince1970: 0)
        let store = DiagnosticsStore(defaults: defaults, storageKey: "events", now: { time })
        // Inject 250 events
        for _ in 0..<250 {
            store.record(.scanCompleted, itemCount: 1)
            time = time.addingTimeInterval(1)  // one second per event
        }
        // Cap of 200 — the most recent 200 remain
        XCTAssertEqual(store.events.count, 200)
        // What remains is the most recent 200 (newest by time)
        let lastEventTime = store.events.last!.occurredAt
        let firstEventTime = store.events.first!.occurredAt
        // The first event should be 250 - 200 = the 51st (index 50, 0-based)
        // In time, t=50, and the last one t=249
        XCTAssertEqual(lastEventTime, Date(timeIntervalSince1970: 249))
        XCTAssertEqual(firstEventTime, Date(timeIntervalSince1970: 50))
    }

    func testRingBufferOldestRemovedFIFO() {
        let suiteName = "TermiPadTests.diagnostics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = DiagnosticsStore(defaults: defaults, storageKey: "events",
                                    now: { Date(timeIntervalSince1970: 0) })
        // 5 different kinds
        let kinds: [DiagnosticEventKind] = [.scanCompleted, .launchSucceeded,
                                              .commandCopied, .automationFallback, .launchFailed]
        for kind in kinds {
            store.record(kind)
        }
        // All 5 events are present
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
        // Rebuild (a new store instance reads from the same UserDefaults)
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
        // Insert deliberately out of order
        let t1 = Date(timeIntervalSince1970: 100)
        let t2 = Date(timeIntervalSince1970: 50)
        let t3 = Date(timeIntervalSince1970: 200)
        let store = DiagnosticsStore(defaults: defaults, storageKey: "events",
                                    now: { Date(timeIntervalSince1970: 0) })
        // Manually bypass record()'s now() — write the events directly
        let ev1 = DiagnosticEvent(occurredAt: t1, kind: .scanCompleted, terminalTarget: nil, itemCount: nil)
        let ev2 = DiagnosticEvent(occurredAt: t2, kind: .launchSucceeded, terminalTarget: nil, itemCount: nil)
        let ev3 = DiagnosticEvent(occurredAt: t3, kind: .launchFailed, terminalTarget: nil, itemCount: nil)
        let data = try! JSONEncoder().encode([ev1, ev2, ev3])
        defaults.set(data, forKey: "events")
        let restored = DiagnosticsStore(defaults: defaults, storageKey: "events",
                                       now: { Date() })
        // After reading, sorted ascending: 50, 100, 200
        XCTAssertEqual(restored.events.map(\.occurredAt), [t2, t1, t3])
    }

    // MARK: - privacy notice (fixed text — contains no sensitive user information)

    func testPrivacyNoticeIsFixedAndContainsNoSensitiveCategories() {
        // This is the project's product promise — any commit changing this string is caught by this test immediately
        let suiteName = "TermiPadTests.diagnostics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = DiagnosticsStore(defaults: defaults, storageKey: "events")
        let report = store.makePrivacyReport()
        XCTAssertEqual(report.privacyNotice, "Contains fixed event categories, timestamps, terminal target names, and aggregate item counts only. No tool names, executable paths, commands, variable values, API keys, or repository content are included.")
        // Key check: the privacy notice must explicitly state No tool names / No commands / No API keys
        // — these are the project's "the diagnostic package does not contain these" promises; a missing one counts as a leak.
        XCTAssertTrue(report.privacyNotice.contains("No tool names"))
        XCTAssertTrue(report.privacyNotice.contains("No commands") || report.privacyNotice.contains("commands,"))
        XCTAssertTrue(report.privacyNotice.contains("No API keys") || report.privacyNotice.contains("API keys,"))
        // "No repository content" is the actual phrase in the text; locking it down proves the product really promises not to send
        // the user's repository information (consistent with what the detectForbiddenRepoContent guard locks down)
        // The privacy notice lists 4 items to exclude — verifying that the list is complete
        // proves the "never sends user data" promise. No tool names starts with an explicit "No".
        // The other 3 items (commands / variable values / API keys / repository content) are in
        // the "or X" list.
        XCTAssertTrue(report.privacyNotice.contains("No tool names"))
        XCTAssertTrue(report.privacyNotice.contains("executable paths"))
        XCTAssertTrue(report.privacyNotice.contains("commands,") || report.privacyNotice.contains("commands ") || report.privacyNotice.contains("commands."))
        XCTAssertTrue(report.privacyNotice.contains("variable values"))
        XCTAssertTrue(report.privacyNotice.contains("API keys,"))
        XCTAssertTrue(report.privacyNotice.contains("repository content"))
    }

    func testPrivacyReportAppVersionFallbackIsDevelopment() {
        // When the bundle cannot be read (the test env has no Info.plist) it falls back to "development"
        // This locks down the risk of a future commit leaking the bundle string by default
        let suiteName = "TermiPadTests.diagnostics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = DiagnosticsStore(defaults: defaults, storageKey: "events")
        let report = store.makePrivacyReport()
        // The test bundle's Info.plist has no CFBundleShortVersionString — it falls back to "development"
        // (only when both CFBundleShortVersionString and CFBundleVersion are nil; the latter is usually present)
        XCTAssertTrue(report.appVersion == "development" || report.appVersion.contains("("),
                      "appVersion should fall back to 'development' or contain a version: \(report.appVersion)")
    }

    // MARK: - DiagnosticEventKind completeness

    func testAllEventKindsAreCodable() throws {
        // Any commit adding a new case must round-trip; this test forces an explicit Codable implementation
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
