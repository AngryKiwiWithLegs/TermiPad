import XCTest
@testable import TermiPad

/// M3 每日远程窗口契约测试（docs/m3-remote-allow-window-design.md）：
/// 生命周期、自然日界、免确认裁决、锁屏失效、未认证拒绝。
@MainActor
final class RemoteAllowWindowTests: XCTestCase {

    func testOpenRequiresAuthentication() {
        let window = RemoteAllowWindow()
        window.open(authenticated: false)
        XCTAssertFalse(window.isOpen, "未认证开窗必须被拒绝")
        window.open(authenticated: true)
        XCTAssertTrue(window.isOpen)
    }

    func testCloseClosesAndAllowsReopen() {
        let window = RemoteAllowWindow()
        window.open(authenticated: true)
        XCTAssertTrue(window.isOpen)
        window.close()
        XCTAssertFalse(window.isOpen)
        window.open(authenticated: true)
        XCTAssertTrue(window.isOpen, "关闭后可重新开窗")
    }

    func testWindowExpiresAcrossDayBoundary() {
        let window = RemoteAllowWindow()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        window.open(authenticated: true, now: yesterday)
        // 跨自然日（即使 app 一直运行）——isOpen 立即为 false。
        XCTAssertFalse(window.isOpen, "跨日窗口必须失效")
        XCTAssertFalse(window.allowsSkipConfirmation())
    }

    func testAllowsSkipConfirmationOnlyWhenOpenSameDay() {
        let window = RemoteAllowWindow()
        XCTAssertFalse(window.allowsSkipConfirmation(), "未开窗不得免确认")
        window.open(authenticated: true)
        XCTAssertTrue(window.allowsSkipConfirmation())
        window.invalidateOnLock()
        XCTAssertFalse(window.allowsSkipConfirmation(), "锁屏失效后不得免确认")
    }

    func testInvalidateOnLockClosesWindow() {
        let window = RemoteAllowWindow()
        window.open(authenticated: true)
        XCTAssertTrue(window.isOpen)
        window.invalidateOnLock()
        XCTAssertFalse(window.isOpen, "锁屏必须关窗")
        // 重复调用无害。
        window.invalidateOnLock()
        XCTAssertFalse(window.isOpen)
    }

    func testSecondsRemainingCountsToMidnight() {
        let window = RemoteAllowWindow()
        XCTAssertEqual(window.secondsRemaining, 0, "关闭态剩余为 0")
        window.open(authenticated: true)
        let remaining = window.secondsRemaining
        XCTAssertGreaterThan(remaining, 0, "开启态剩余应到当日 24:00")
        XCTAssertLessThanOrEqual(remaining, 24 * 3600)
    }
}
