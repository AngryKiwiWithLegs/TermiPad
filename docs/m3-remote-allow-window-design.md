# M3 remote allow window design — daily unlock + confirmation-free trust window

**Status:** Design review draft (2026-09-14). Review first, then implement; this document claims no capability as implemented.

**Parent documents:** `docs/product-roadmap.md` §5 stage 6 (M3); `docs/m2b-remote-task-console-design.md` §4 defense line 3 (this design lands its "daily local unlock" item) and the preview in §9.

**The problem to solve:** real-device use of M2b confirmed that the north-star scenario holds, but every remote action needs confirmation on the Mac — when nobody is at the Mac, that defense line becomes a deadlock instead (exactly the "deadlock problem" predicted in §1 of the M2a design doc). M3 gives **the alert user who is at the Mac** a one-off way to authorize: tap once before leaving today, and phone actions need no confirmation for the rest of the day.

## 1. Core semantics: Daily Unlock

```
The user at the Mac (before leaving in the morning):
  Settings → Mobile Companion → "Open Today's Remote Window" → confirm with Touch ID / password → the window opens
  ├─ Valid until: 24:00 of the same day (calendar-day boundary) or until the user closes it manually, whichever comes first
  ├─ Inside the window: the phone's requestLaunch / requestTaskProposal run directly **without confirmation on the Mac**
  │   (still subject to: rejection while locked, the 30-day lifetime, rate limiting, the allowlist, and full T0 policy verification)
  └─ Immediate invalidation conditions (any one closes the window at once):
     Mac locked / asleep / app quit / user clicks close / device revoked
```

**Relationship to M1.1 perSession**: `MobileLaunchSession` (the 5-minute allowlist) is kept and upgraded into its internal implementation — the daily unlock replaces "5 minutes" with "until 24:00 today", with isomorphic semantics (process memory, never written to disk, voidable at any time). M3 generalizes `MobileLaunchSession` rather than replacing it.

## 2. Explicit non-goals (red lines)

- **Never written to disk**: the window state lives only in process memory (same as M1.1). An app restart closes it — "open the window again after a restart" is acceptable friction, in exchange for "a long-lived confirmation-free credential never exists on disk"
- **Not sent along with the tailnet endpoint**: the phone does not know the window state and the Mac is the sole authority — once the window is closed the phone's next request is simply rejected (with the explicit copy "Today's remote window is not open")
- **No "permanent confirmation-free"**: the window lasts at most until 24:00 today, and a new day requires unlocking again
- **The lowRisk allowlist is unaffected**: M1.1's 5-minute lowRiskSessionOnly window coexists with the daily window, and the union applies

## 3. Mac-side design

### 3.1 `RemoteAllowWindow` (new file Sources/RemoteAllowWindow.swift)

```swift
@MainActor
final class RemoteAllowWindow: ObservableObject {
    static let shared = RemoteAllowWindow()
    /// When the window was opened; nil = closed. Process memory, never written to disk.
    @Published private(set) var openedAt: Date?
    /// Unlock time (recorded separately — locking invalidates it, and the door must be reopened after unlocking, see §3.2)
    private var unlockedAt: Date?

    var isOpen: Bool          // openedAt != nil and still the same calendar day
    func open(authenticated: Bool)   // authenticated=false is rejected outright — the caller is responsible for LAContext
    func close()                     // called on manual close / lock / revocation
    func invalidateOnLock()          // lock-screen hook
}
```

### 3.2 Lifecycle hooks

| Event | Action |
|---|---|
| The user clicks "Open Today's Remote Window" | LAContext `.deviceOwnerAuthentication` (Touch ID / password) succeeds → `open()`; diagnostic `remoteAllowWindowOpened` |
| The user clicks "Close" | `close()`; diagnostic `remoteAllowWindowClosed` |
| Mac locked (change in `CGSessionCopyCurrentDictionary`, polled every 5s) | `invalidateOnLock()` — **locking closes the window** (whoever steals the Mac cannot be locked out of your window) |
| App launch | Not restored (the in-memory state is naturally lost) |
| Device revoked / pairing turned off | `close()` (hooked into the existing revocation chain) |

### 3.3 Hooking into the execution chain (+3 lines in each of two places)

The confirmation step of `handleLaunchRequest` and `handleTaskProposal` becomes:

```
Confirmation tier decision → M1.1 allowlist hit? → no confirmation (unchanged)
            → RemoteAllowWindow.isOpen? → no confirmation (new, diagnostic remoteAllowWindowUsed)
            → else show the 60s confirmation (unchanged)
```

**The lock-screen check stays first**: window open but Mac locked → still rejected (the defense line is not downgraded by the window).

### 3.4 UI (Mobile Companion section of PreferencesView)

```
[Today's Remote Window: closed / 6h12m remaining]
[Open Today's Remote Window] (Touch ID)   [Close]
hint: Once opened, phone actions need no local confirmation for the rest of today. It closes automatically when the Mac is locked or restarted.
       The first unlock still needs Touch ID — the window only removes "confirm every action".
```

## 4. Protocol and phone side

**Zero protocol changes**: the window state is not sent and does not enter MacResumeHello. The only change on the phone is one new **rejection copy**: "Today's remote window is not open. Open it on the Mac and try again." (reusing the existing reason field, fixed copy). The phone UI needs no changes at all — the behavior is transparent.

## 5. Security analysis (exposure surface while the window is open)

| Defense line | Still effective while the window is open? |
|---|---|
| Face ID app lock (phone) | ✅ Unchanged |
| 30-day credential lifetime | ✅ Unchanged |
| Rejection while locked | ✅ **Strengthened**: locking closes the window |
| Rate limiting (10 per minute) | ✅ Unchanged |
| Full T0 policy verification (scope/risk/window/timeout) | ✅ Unchanged (only the "local confirmation" step is skipped) |
| Allowlist / confirmation tiers | Union semantics with lowRisk |
| Revocation | ✅ Closes the window + revokes |
| Output visibility / redaction | ✅ Unchanged |

**Residual risk (accepted knowingly by the user)**: while the window is open, someone holding the unlocked phone, with the Mac unlocked, can run tasks from the fixed catalog without confirmation. Mitigations: the calendar-day boundary + locking closes the window + immediate revocation. This is exactly the product semantics of "daily unlock".

## 6. Acceptance checklist (G7, real devices)

| # | Verification item | Pass criterion |
|---|---|---|
| 1 | Open the window | After Touch ID the window shows the remaining time; the diagnostic event is recorded |
| 2 | No confirmation | Inside the window, the phone submits a task / taps a tool → it runs directly (no confirmation prompt) |
| 3 | Defense lines still apply | Inside the window, lock the Mac → the action is rejected and the window closes; after unlocking, the window stays closed (it must be reopened) |
| 4 | Close the window | After closing manually, phone actions go back to confirmation per action |
| 5 | Crossing midnight | The window stays open across 24:00 → the next day's request is rejected (copy "Today's remote window is not open") |
| 6 | Invalid after restart | Restart the Mac app → the window is closed (in-memory state lost) |
| 7 | Revocation linkage | Revoke the device → the window closes |
| 8 | Red-line review | The window state is not written to disk, backups, or diagnostic content; the protocol has no new fields |
