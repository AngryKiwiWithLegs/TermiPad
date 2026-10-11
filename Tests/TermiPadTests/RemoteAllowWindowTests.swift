import XCTest
@testable import TermiPad

/// M3 daily remote window contract tests (docs/m3-remote-allow-window-design.md):
/// lifecycle, calendar-day boundary, confirmation-free decision, invalidation on lock, rejection when unauthenticated.
@MainActor
final class RemoteAllowWindowTests: XCTestCase {

    func testOpenRequiresAuthentication() {
        let window = RemoteAllowWindow()
        window.open(authenticated: false)
        XCTAssertFalse(window.isOpen, "Opening the window without authentication must be rejected")
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
        XCTAssertTrue(window.isOpen, "The window can be reopened after closing")
    }

    func testWindowExpiresAcrossDayBoundary() {
        let window = RemoteAllowWindow()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        window.open(authenticated: true, now: yesterday)
        // Crossing a calendar day (even with the app running the whole time) — isOpen becomes false immediately.
        XCTAssertFalse(window.isOpen, "The window must become invalid across days")
        XCTAssertFalse(window.allowsSkipConfirmation())
    }

    func testAllowsSkipConfirmationOnlyWhenOpenSameDay() {
        let window = RemoteAllowWindow()
        XCTAssertFalse(window.allowsSkipConfirmation(), "No confirmation-free actions without an open window")
        window.open(authenticated: true)
        XCTAssertTrue(window.allowsSkipConfirmation())
        window.invalidateOnLock()
        XCTAssertFalse(window.allowsSkipConfirmation(), "No confirmation-free actions after the lock screen invalidates the window")
    }

    func testInvalidateOnLockClosesWindow() {
        let window = RemoteAllowWindow()
        window.open(authenticated: true)
        XCTAssertTrue(window.isOpen)
        window.invalidateOnLock()
        XCTAssertFalse(window.isOpen, "Locking the screen must close the window")
        // Repeated calls are harmless.
        window.invalidateOnLock()
        XCTAssertFalse(window.isOpen)
    }

    func testSecondsRemainingCountsToMidnight() {
        let window = RemoteAllowWindow()
        XCTAssertEqual(window.secondsRemaining, 0, "Remaining is 0 when closed")
        window.open(authenticated: true)
        let remaining = window.secondsRemaining
        XCTAssertGreaterThan(remaining, 0, "When open, the remaining time should run to 24:00 today")
        XCTAssertLessThanOrEqual(remaining, 24 * 3600)
    }
}
