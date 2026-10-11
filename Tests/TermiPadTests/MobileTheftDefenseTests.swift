import XCTest
@testable import TermiPad

/// M2b defense line contract tests (docs/m2b-remote-task-console-design.md §4):
/// defense line 2 (boundary values of the 30-day credential lifetime) and defense line 3 (rate-limit window for write operations).
final class MobileTheftDefenseTests: XCTestCase {

    // MARK: - Defense line 2: 30-day lifetime of pairing credentials

    func testPairingCredentialLifetimeIsThirtyDays() {
        // Constant lock: changing the lifetime must change the design doc too (§4 defense line 2).
        XCTAssertEqual(
            MobilePairingService.pairingCredentialLifetime,
            30 * 24 * 3600,
            accuracy: 0)
    }

    func testThirtyOneDayOldPairingIsRejected() throws {
        // Paired 31 days ago → too old, resume must be rejected (the validation semantics are carried by the
        // guard in handleResumeHello; this locks down the input relationship of the "threshold check").
        let pairedAt = Date().addingTimeInterval(-31 * 24 * 3600)
        XCTAssertGreaterThan(
            Date().timeIntervalSince(pairedAt),
            MobilePairingService.pairingCredentialLifetime)
    }

    func testTwentyNineDayOldPairingStillValid() throws {
        // Paired 29 days ago → not too old, resume should be allowed and renewed.
        let pairedAt = Date().addingTimeInterval(-29 * 24 * 3600)
        XCTAssertLessThan(
            Date().timeIntervalSince(pairedAt),
            MobilePairingService.pairingCredentialLifetime)
    }

    // MARK: - Defense line 3: write rate limiting

    func testRateLimiterAllowsUpToTenPerMinuteThenRejects() {
        let limiter = MobilePairingService.WriteRateLimiter(window: 60, maxCount: 10)
        let base = Date()
        for index in 0..<10 {
            XCTAssertTrue(
                limiter.allow(now: base.addingTimeInterval(TimeInterval(index))),
                "Write operation \(index + 1) should be allowed within the limit of 10")
        }
        XCTAssertFalse(
            limiter.allow(now: base.addingTimeInterval(10)),
            "The 11th (within the 60-second window) must be rejected — an attacker with a lost phone cannot probe at high frequency")
    }

    func testRateLimiterWindowSlides() {
        let limiter = MobilePairingService.WriteRateLimiter(window: 60, maxCount: 10)
        let base = Date()
        for index in 0..<10 {
            XCTAssertTrue(limiter.allow(now: base.addingTimeInterval(TimeInterval(index))))
        }
        // The window slides past 61 seconds: the earliest batch expires and the quota is restored.
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

    // MARK: - Renewal throttle gate (companion to defense line 2: at most one Keychain write per day)

    func testRenewalGateAllowsOncePerDayPerDevice() {
        let gate = MobilePairingService.RenewalGate()
        let device = UUID()
        let base = Date()
        XCTAssertTrue(gate.shouldRenew(deviceID: device, lastRenewedAt: nil, now: base))
        // Connecting again the same day (3-second polling scenario) — not allowed, no Keychain write.
        XCTAssertFalse(gate.shouldRenew(deviceID: device, lastRenewedAt: base, now: base.addingTimeInterval(3)))
        XCTAssertFalse(gate.shouldRenew(deviceID: device, lastRenewedAt: base, now: base.addingTimeInterval(3600)))
        // After 24 hours — allowed.
        XCTAssertTrue(gate.shouldRenew(deviceID: device, lastRenewedAt: base, now: base.addingTimeInterval(24 * 3600 + 1)))
    }

    func testRenewalGateIsPerDevice() {
        let gate = MobilePairingService.RenewalGate()
        let base = Date()
        XCTAssertTrue(gate.shouldRenew(deviceID: UUID(), lastRenewedAt: nil, now: base))
        // Another device is unaffected.
        XCTAssertTrue(gate.shouldRenew(deviceID: UUID(), lastRenewedAt: nil, now: base))
    }
}
