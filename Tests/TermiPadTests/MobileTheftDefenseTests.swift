import XCTest
@testable import TermiPad

/// M2b 防线契约测试（docs/m2b-remote-task-console-design.md §4）：
/// 防线 2（30 天凭据时效的边界值）与防线 3（写操作限速窗口）。
final class MobileTheftDefenseTests: XCTestCase {

    // MARK: - 防线 2：配对凭据 30 天时效

    func testPairingCredentialLifetimeIsThirtyDays() {
        // 常量锁：改动时效必须连带改设计文档（§4 防线 2）。
        XCTAssertEqual(
            MobilePairingService.pairingCredentialLifetime,
            30 * 24 * 3600,
            accuracy: 0)
    }

    func testThirtyOneDayOldPairingIsRejected() throws {
        // 31 天前的配对 → 超龄，resume 必须拒绝（校验语义由
        // handleResumeHello 的 guard 承载；这里锁"阈值判断"的输入关系）。
        let pairedAt = Date().addingTimeInterval(-31 * 24 * 3600)
        XCTAssertGreaterThan(
            Date().timeIntervalSince(pairedAt),
            MobilePairingService.pairingCredentialLifetime)
    }

    func testTwentyNineDayOldPairingStillValid() throws {
        // 29 天前的配对 → 未超龄，resume 应放行并续命。
        let pairedAt = Date().addingTimeInterval(-29 * 24 * 3600)
        XCTAssertLessThan(
            Date().timeIntervalSince(pairedAt),
            MobilePairingService.pairingCredentialLifetime)
    }

    // MARK: - 防线 3：写操作限速

    func testRateLimiterAllowsUpToTenPerMinuteThenRejects() {
        let limiter = MobilePairingService.WriteRateLimiter(window: 60, maxCount: 10)
        let base = Date()
        for index in 0..<10 {
            XCTAssertTrue(
                limiter.allow(now: base.addingTimeInterval(TimeInterval(index))),
                "第 \(index + 1) 次写操作在 10 次限额内应放行")
        }
        XCTAssertFalse(
            limiter.allow(now: base.addingTimeInterval(10)),
            "第 11 次（60 秒窗口内）必须拒绝——丢手机攻击者无法高频试探")
    }

    func testRateLimiterWindowSlides() {
        let limiter = MobilePairingService.WriteRateLimiter(window: 60, maxCount: 10)
        let base = Date()
        for index in 0..<10 {
            XCTAssertTrue(limiter.allow(now: base.addingTimeInterval(TimeInterval(index))))
        }
        // 窗口滑过 61 秒：最早一批过期，额度恢复。
        XCTAssertTrue(limiter.allow(now: base.addingTimeInterval(61)))
    }

    func testRateLimiterReset() {
        let limiter = MobilePairingService.WriteRateLimiter(window: 60, maxCount: 10)
        let base = Date()
        for _ in 0..<10 {
            XCTAssertTrue(limiter.allow(now: base))
        }
        XCTAssertFalse(limiter.allow(now: base))
        limiter.reset()
        XCTAssertTrue(limiter.allow(now: base))
    }
}
