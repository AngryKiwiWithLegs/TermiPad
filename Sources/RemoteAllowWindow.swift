// M3 daily remote allow window (docs/m3-remote-allow-window-design.md).
// Before leaving in the morning the user opens "Today's Remote Window" once with Touch ID on the Mac, and that day's phone actions
// need no local confirmation — resolving the deadlock of "confirm every action while away from the Mac" (predicted in M2a §1).
// Red line: the window state is **pure process memory** and never written to disk (a long-lived confirmation-free credential never exists on disk);
// a new calendar day requires unlocking again; locking the Mac closes the window; the Mac is the sole authority (zero protocol changes,
// the phone is unaware — after the window closes requests are simply rejected, with explicit receipt copy).
import Foundation

@MainActor
final class RemoteAllowWindow: ObservableObject {
    static let shared = RemoteAllowWindow()

    /// When the window was opened; nil = closed. Process memory, never written to disk.
    @Published private(set) var openedAt: Date?

    /// Maximum span of the window: until 24:00 of the same day (calendar-day boundary).
    static let dayBoundary: Calendar = .current

    var isOpen: Bool {
        guard let openedAt else { return false }
        // Invalid as soon as the calendar day changes (even if the app keeps running across midnight).
        return Self.dayBoundary.isDate(openedAt, inSameDayAs: Date())
    }

    /// Seconds remaining until 24:00 today (the UI shows "X hours remaining"); 0 when closed.
    var secondsRemaining: TimeInterval {
        guard isOpen, let openedAt else { return 0 }
        let endOf = Self.dayBoundary.startOfDay(for: openedAt)
            .addingTimeInterval(24 * 3600)
        return max(0, endOf.timeIntervalSince(Date()))
    }

    /// Open the window. authenticated=false is rejected outright — the caller is responsible for local authentication,
    /// this method does not authenticate (single responsibility: authentication is in the UI layer, the window only manages state).
    func open(authenticated: Bool, now: Date = Date()) {
        guard authenticated else { return }
        openedAt = now
        DiagnosticsStore.shared.record(.remoteAllowWindowOpened)
    }

    /// Close the window (user action / device revocation / pairing turned off).
    func close() {
        guard openedAt != nil else { return }
        openedAt = nil
        DiagnosticsStore.shared.record(.remoteAllowWindowClosed)
    }

    /// Lock-screen hook: locking closes the window (prevents "whoever steals the Mac cannot be locked out of your window").
    /// Diagnosed separately from the window-open event; repeated calls are harmless.
    func invalidateOnLock() {
        guard openedAt != nil else { return }
        openedAt = nil
        DiagnosticsStore.shared.record(.remoteAllowWindowLocked)
    }

    /// Confirmation-free decision: called by the execution chain. Window open + same day = no local confirmation.
    /// T0 policy verification / lock-screen rejection / rate limiting / lifetime are **not part of this decision** — the caller's
    /// order is: lock-screen check → rate limit → T0 verification → confirmation tier (here).
    func allowsSkipConfirmation(now: Date = Date()) -> Bool {
        guard let openedAt else { return false }
        return Self.dayBoundary.isDate(openedAt, inSameDayAs: now)
    }
}
