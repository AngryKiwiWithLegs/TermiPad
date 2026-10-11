import XCTest
@testable import TermiPad

/// MobileLaunchSession session allowlist tests (§3.3.2, added 2026-09-08, M1.1).
/// Pure logic: the clock is injected, no waiting for real time, no Keychain/network.
@MainActor
final class MobileLaunchSessionTests: XCTestCase {
    private var clock: MutableClock!
    private var session: MobileLaunchSession!

    override func setUp() {
        super.setUp()
        clock = MutableClock()
        session = MobileLaunchSession(now: clock.now)
    }

    private let toolID = UUID()

    func testEveryTimeNeverSkipsEvenWithFreshConfirmation() {
        session.recordConfirmation(toolID: toolID)
        XCTAssertFalse(session.canSkipConfirmation(
            policy: .everyTime, toolID: toolID, commandTemplate: "/usr/bin/git status"))
    }

    func testPerSessionSkipsWithinWindow() {
        session.recordConfirmation(toolID: toolID)
        clock.advance(by: MobileLaunchSession.sessionWindow - 1)
        XCTAssertTrue(session.canSkipConfirmation(
            policy: .perSession, toolID: toolID, commandTemplate: "/usr/bin/git status"))
    }

    func testPerSessionExpiresAfterWindow() {
        session.recordConfirmation(toolID: toolID)
        clock.advance(by: MobileLaunchSession.sessionWindow + 1)
        XCTAssertFalse(session.canSkipConfirmation(
            policy: .perSession, toolID: toolID, commandTemplate: "/usr/bin/git status"))
    }

    func testLowRiskSkipsOnlyForMetacharacterFreeTemplates() {
        session.recordConfirmation(toolID: toolID)
        XCTAssertTrue(session.canSkipConfirmation(
            policy: .lowRiskSessionOnly, toolID: toolID, commandTemplate: "/usr/bin/git status"))
        // Metacharacter second line of defense: a template with an injection surface is not treated as low risk.
        XCTAssertFalse(session.canSkipConfirmation(
            policy: .lowRiskSessionOnly, toolID: toolID, commandTemplate: "/bin/sh -c; rm -rf x"))
        XCTAssertFalse(session.canSkipConfirmation(
            policy: .lowRiskSessionOnly, toolID: toolID, commandTemplate: "/usr/bin/git $HOME"))
    }

    func testUnconfirmedToolNeverSkipsAnyPolicy() {
        XCTAssertFalse(session.canSkipConfirmation(
            policy: .perSession, toolID: toolID, commandTemplate: "/usr/bin/git status"))
        XCTAssertFalse(session.canSkipConfirmation(
            policy: .lowRiskSessionOnly, toolID: toolID, commandTemplate: "/usr/bin/git status"))
    }

    func testInvalidateKillsSessionImmediately() {
        session.recordConfirmation(toolID: toolID)
        session.invalidate(toolID: toolID)
        XCTAssertFalse(session.canSkipConfirmation(
            policy: .perSession, toolID: toolID, commandTemplate: "/usr/bin/git status"))
    }

    func testInvalidateAllClearsEveryTool() {
        let otherID = UUID()
        session.recordConfirmation(toolID: toolID)
        session.recordConfirmation(toolID: otherID)
        session.invalidateAll()
        XCTAssertFalse(session.canSkipConfirmation(
            policy: .perSession, toolID: toolID, commandTemplate: "/usr/bin/git status"))
        XCTAssertFalse(session.canSkipConfirmation(
            policy: .perSession, toolID: otherID, commandTemplate: "/usr/bin/git status"))
    }

    func testReconfirmationRefreshesWindow() {
        session.recordConfirmation(toolID: toolID)
        clock.advance(by: MobileLaunchSession.sessionWindow - 10)
        // Confirm again when the window is about to expire → counted from the new timestamp.
        session.recordConfirmation(toolID: toolID)
        clock.advance(by: MobileLaunchSession.sessionWindow - 10)
        XCTAssertTrue(session.canSkipConfirmation(
            policy: .perSession, toolID: toolID, commandTemplate: "/usr/bin/git status"))
    }

    func testSessionsArePerTool() {
        let otherID = UUID()
        session.recordConfirmation(toolID: toolID)
        XCTAssertFalse(session.canSkipConfirmation(
            policy: .perSession, toolID: otherID, commandTemplate: "/usr/bin/git status"))
    }
}

/// A test clock that can be advanced manually — avoids real sleeps and also locks down the "expired means invalid" time semantics.
final class MutableClock {
    private var current = Date()
    var now: () -> Date { { self.current } }

    func advance(by seconds: TimeInterval) {
        current = current.addingTimeInterval(seconds)
    }
}
