import XCTest
@testable import TermiPad

/// MobileLaunchSession 会话白名单测试（§3.3.2 增补 2026-09-08，M1.1）。
/// 纯逻辑：注入时钟，不等待真实时间、不打 Keychain/网络。
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
        // 元字符第二道防线：带注入面的模板不视为低风险。
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
        // 窗口快到期时再次确认 → 从新时间戳起算。
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

/// 可手动推进的测试时钟——避免真实 sleep，也锁死"过期即失效"的时间语义。
final class MutableClock {
    private var current = Date()
    var now: () -> Date { { self.current } }

    func advance(by seconds: TimeInterval) {
        current = current.addingTimeInterval(seconds)
    }
}
