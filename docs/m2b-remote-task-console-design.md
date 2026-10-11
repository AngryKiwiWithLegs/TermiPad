# M2b remote task session design — a zcode-standard experience on the phone + four defense lines against theft

**Status:** Design review draft (2026-09-09). Review first, then implement; this document claims no capability as implemented.

**Parent documents:** `docs/product-roadmap.md` §5 stage 5 (M2) and the mobile entry decision in §8; `docs/m2-secure-remote-session-design.md` (the M2a tunnel — reused unchanged as this batch's transport layer); `docs/m0-m1-mobile-entry-design.md` (pairing/encryption/revocation layer).

**User decision (2026-09-09):** the product experience aligns with the zcode standard — the phone must be able to see a task interaction UI and run tasks (a terminal emulation UI is not required); for security, a four-defense-line architecture is accepted so a phone thief cannot execute anything. The restricted task model (fixed task catalog + project scope + time limit + stoppable) is kept: what the phone submits is a "task proposal reference" (kind + scope), never a free-form command.

## 1. Goal and form of the experience

The full realization of the north-star scenario: the user is out, and on the phone there is a **task session** (task console):

```
┌─ Task session on the phone ──────────────────┐
│ Session entry feed (tool launches + fixed tasks, one timeline) │
│  ▶ swift test    succeeded  exit 0   12:31    │
│  ▶ Build tool    launched           12:29     │
│  [+ New task] → pick scope → pick fixed task → submit │
│  Running entry → [Stop] (only tasks submitted from the phone) │
└──────────────────────────────────────────────┘
```

- **See**: the session entry feed (title, 8 states, exit code, time) + output snippets according to the output visibility level
- **Run**: submit a fixed task proposal (pick kind + scope from the catalog sent by the Mac, two references) → Mac T0/T1 policy verification → execution
- **Stop**: cancel a running task you submitted yourself
- **Update mechanism**: the phone polls `getTaskStatus` (3-second interval, while the session is active). Tasks take minutes, so polling delay is not felt; streaming push frames are not in this batch (the protocol stays request-response, see §6)

The only deliberate difference from zcode: what runs is a **controlled task** (fixed catalog + project scope + timeout + stoppable), not an arbitrary shell. The most an attacker with a lost phone gets = tapping and submitting the 5 tasks in the fixed task catalog — and they still have to get through the four defense lines (§4).

## 2. Premises and reuse (all verified)

| Component | Status | How this batch uses it |
|---|---|---|
| M2a tunnel (Tailscale serve + loopback 57148) | G5 passed on real devices | Reused unchanged as the transport layer, zero changes |
| M1 pairing/encryption/fingerprint/revocation | G4 passed on real devices | Handshake chain reused unchanged |
| The five reserved `PairedDeviceOperation` cases | Reserved in the M2a protocol | Activated in this batch (§5.1) |
| T0 `TaskIntentPolicy` (makeIntent/review/approve/cancel) | Unit tests cover 9 rejection paths | The verification core for task submissions from the phone |
| T1 `TaskExecutionCoordinator` (8-state lifecycle/timeout/stop) | Unit tests + verified on a real machine | The execution core for phone tasks |
| M1.1 `MobileLaunchSession` (5-minute allowlist) | Passed on real devices | The confirmation tiers are extended to task submission (§5.3) |

## 3. Protocol increment (non-breaking, decodeIfPresent discipline)

### 3.1 Request payload extension

`MobilePairingRequest` gains three optional fields (old phones and Macs stay compatible both ways; custom `decodeIfPresent` decoding — locked by tests):

```swift
struct MobilePairingRequest: Codable {
    let operation: PairedDeviceOperation
    let requestID: UUID
    let toolID: UUID?
    var taskKind: String? = nil       // requestTaskProposal: allowlisted kind from FixedTaskCatalog
    var projectScopeID: UUID? = nil   // requestTaskProposal: id of a registered scope (a reference, not a path)
    var taskIntentID: UUID? = nil     // getTaskStatus / cancelTask
}
```

**Red line unchanged**: the phone still cannot send command/path/parameter/environment — the payload contains only UUIDs and allowlisted enum strings. The key set lock in `MobilePairingProtocolTests` is updated in step.

### 3.2 Return structures (Mac → phone, all through the existing AEAD envelope)

```swift
/// Project scope entry: the phone sees only id + display name; rootPath is never sent.
struct MobileScopeSummary: Codable {
    let id: UUID
    let displayName: String
}

/// Fixed task catalog entry: kind + bilingual purpose + fixed command preview (catalog literals, not user data).
struct MobileFixedTaskSummary: Codable {
    let kind: String
    let purpose: String
    let commandPreview: String
}

/// Session entry: one shape for tool launches and fixed tasks.
struct MobileSessionEntry: Codable {
    let id: UUID                  // tool launch event ID or TaskIntent ID
    let title: String             // tool display name / fixed task purpose
    let kind: String              // "toolLaunch" | "fixedTask"
    let executionState: String    // unified state enum (§3.3)
    let exitCode: Int?
    let startedAt: Date?
    let finishedAt: Date?
    var outputSnippet: String? = nil  // non-nil only when the output visibility is ≥ restricted and the task is run by T1
}

/// Receipt for requestTaskProposal: accept/reject + task reference (rejection copy is a fixed enum).
struct MobileTaskProposalResponse: Codable {
    enum Status: String { case accepted, rejected }
    let status: Status
    let reason: String?           // fixed enum copy, no paths and no commands
    let taskIntentID: UUID?       // on acceptance, used by the phone for later getTaskStatus/cancelTask
}
```

### 3.3 Unified state enum

T1's 8 `TaskExecutionState` states are sent as their raw strings (notStarted…startFailed). Tool launches (terminal handoff) have only two states, launched/launchFailed — the session entry's `kind` distinguishes them, and the phone renders the state set by kind. **No new state semantics are added** and no intermediate states are invented.

### 3.4 Frames and frequency

- All new messages use the existing 4-byte length-prefixed frames + the 64 KB limit; output snippets are truncated within the frame (§5.4)
- `getTaskStatus` polling is on the same allowlist level as the existing `heartbeat`; the Mac always rejects unpaired/revoked devices (unchanged)

## 4. Four defense lines against theft (the core reason for this batch)

User decision: the experience aligns with zcode while a phone thief cannot execute anything. The defense lines sit on the **post-theft path**; the normal usage path has only one point of friction, Face ID.

### Defense line 1 · Phone gate (iOS side)

| Measure | Design |
|---|---|
| App lock | Opening the companion app / returning to the foreground needs Face ID (LAContext, `deviceOwnerAuthentication`; falls back to the device passcode without biometrics). On by default; can be turned off in settings (at the user's own risk). |
| Credential protection | Pairing credentials use Keychain `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`: unreadable after locking, not migrated with iCloud backups, not carried to a new device. (If M1 landed with the default accessible value, this batch changes it and migrates: old credentials are read out and rewritten once) |
| Output not written to disk | Session entries on the phone are memory + `@Published` only; output snippets are not written to files or snapshots. After more than 5 minutes in the background the output snippets are cleared (the status summary is kept). |

### Defense line 2 · Short-lived credentials (Mac side)

- Pairing records carry `pairedAt`; on a resume handshake, age > 30 days → resume is rejected, with explicit copy on the phone "pairing expired, return to the same network and pair again" (diagnostic `mobilePairingExpired`, timestamp only)
- Effect: a key obtained by a phone thief lives at most 30 days; for a normal user any same-network connection within 30 days renews it (`pairedAt` is refreshed)

### Defense line 3 · Mac-side execution defenses (which a phone thief physically cannot get around)

| Measure | This batch | M3 |
|---|---|---|
| Reject new tasks while locked | ✅ The Mac detects that the login session is locked (`CGSSessionScreenIsLocked` from `CGSessionCopyCurrentDictionary`) → all remote task submissions and tool launches are rejected while locked (diagnostic `remoteTaskBlockedScreenLocked`) | Same |
| Rate limiting | ✅ ≤ 10 per device per minute (submissions + launches combined); over the limit the receipt's rejection copy is fixed | Adjustable |
| Confirmation tiers | ✅ Reuses and extends the three M1.1 tiers: task submission and tool launching share everyTime / perSession (5 minutes) / the lowRisk allowlist; lowRisk requires task risk == .low | Same |
| Daily local unlock | — | ✅ The first remote task of each day needs one tap on the Mac; after that it is instant for the day |
| panic code | — | ✅ Entering a preset emergency passphrase revokes all mobile pairings |

### Defense line 4 · Revocation channels (three layers, all effective immediately)

1. **Revoke on the Mac** (existing): revoke the device pairing in Settings — the tunnel and the same-network path are cut at once
2. **Turn off the tunnel switch** (existing): serve is withdrawn and the allowlist cleared at once
3. **Tailscale admin console** (ready-made, not self-built): the user signs in to their Tailscale account in any browser → Devices → removes the phone → the tunnel is cut at once. **No self-built "remote wipe" service** — a self-built remote control channel is itself a new attack surface; the Tailscale account system already has mature device revocation.

### Theft chain walkthrough (design self-check)

To run one task, a phone thief needs, in order: unlock the iPhone (Face ID) → open the companion app past the app lock (Face ID a second time) → the Mac is not locked → the task passes the confirmation tier (with everyTime, local confirmation on the Mac, unobtainable remotely) → the Mac pairing is within 30 days, not expired and not revoked. Failing any link ends it. **Output leak surface**: even if everything is breached, all that can be read are truncated output snippets of fixed tasks (redacted per §5.4) — tool launches (the terminal handoff path) never return output.

## 5. Mac-side design

### 5.1 New component `MobileTaskConsoleService` (@MainActor ObservableObject)

Responsibilities: aggregate the "session entry feed" + handle the five new operations + decide output visibility. **The only new file in Sources**; the pairing service (`MobilePairingService`) hands all new operations to it after receiving them, with zero changes to the handshake/encryption/revocation chain.

```
MobilePairingService (existing; encryption and revocation untouched)
   └─ operation dispatch → MobileTaskConsoleService (new)
        ├─ listScopes      → TaskProjectScope query (SwiftData) → [MobileScopeSummary]
        ├─ listFixedTasks  → FixedTaskCatalog → [MobileFixedTaskSummary]
        ├─ requestTaskProposal → §5.2 verification chain → TaskExecutionCoordinator
        ├─ getTaskStatus   → snapshot of the session entry feed (including the output snippet decision)
        └─ cancelTask      → only tasks submitted by the phone that are running → coordinator.stop
```

### 5.2 requestTaskProposal verification chain (the order is the attack-surface check order)

1. The device pairing is valid (including the 30-day lifetime) → otherwise reject with `pairingExpired`
2. Lock-screen check (defense line 3) → `screenLocked`
3. Rate limit → `rateLimited`
4. `taskKind` is in `FixedTaskCatalog` (the allowlist is the attack surface) → `unknownTaskKind`
5. `projectScopeID` is registered, not revoked, and its directory is available → `projectScopeUnavailable`
6. `TaskIntentPolicy.makeIntent` + `review` (full T0 policy: risk, window, nonce, expiry) → the rejection reason is mapped to the receipt as is
7. **Confirmation tier** (the same three tiers as M1.1; everyTime takes the 60-second local confirmation prompt, and a perSession/lowRisk allowlist hit passes automatically + diagnostic `mobileTaskAutoConfirmed`)
8. `approve` → `TaskExecutionCoordinator.start` (T1 execution: fixed executable, fixed arguments, timeout, stoppable, empty stdin)

Every rejection step writes a diagnostic (event enum + timestamp only, no task data). The rejection copy of the `MobileTaskProposalResponse` receipt is a fixed enum of strings.

### 5.3 Session entry feed

- An in-memory ring buffer of the latest 50 entries; tool launch events (already in the M1 requestLaunch chain) and T1 tasks are merged into it; after 10 minutes an entry keeps only its status summary (the output snippet is cleared)
- `getTaskStatus` returns the full snapshot (≤50 entries, within a 64 KB frame); the phone replaces the whole rendering

### 5.4 Output capture and visibility levels (T1 change, controlled relaxation)

T1 currently sends all stdout/stderr to nullDevice. This batch changes that: **when the level is ≥ restricted**, capture into an **in-memory only** ring buffer (capped at 32 KB / 400 lines, whichever comes first); at the minimal level, keep nullDevice.

| Level | What the phone can see | Buffer |
|---|---|---|
| `minimal` | Status + exit code (the current semantics) | Not captured |
| `restricted` (suggested default) | The last 32 lines + redaction (§5.5) | In memory, cleared 10 minutes after the task ends |
| `full` | The full buffer content (still subject to the 32 KB cap and redaction) | Same as above |

- Setting: `TermiPad.remoteOutputVisibility` (UserDefaults; the Mac is the authority; MacResumeHello does not carry this field, and the level's effect naturally shows in the returned content)
- **Tool launches (the terminal handoff path) never have output** — the output goes to a real terminal window and cannot be captured in the first place; this does not change
- Red lines continue: output snippets are not written to disk (on either the Mac or the phone), do not enter backups (excluded by BackupService), and do not enter diagnostics

### 5.5 Output redaction (shared by restricted/full)

Before sending, a fixed regex family is run over the snippet (hard-coded literals, not read from user configuration): common token/password/api-key/Bearer assignment patterns and AWS/GitHub key prefix forms → replaced with `••••`. **No home-made cryptography and no semantic understanding**, purely literal pattern matching; the risk of missed redaction is covered by the choice of level (use minimal for the most sensitive scenarios).

## 6. iOS-side design (CompanionApp)

- **Session page** (new tab / main view): renders the entry feed (status icon + title + exit code + time; running entries have a stop button) + pull to refresh + 3-second automatic polling (only while active in the foreground)
- **New task page**: listScopes → listFixedTasks → confirm and submit (shows purpose + commandPreview + scope name)
- **App lock**: `LocalAuthentication`, triggered on returning to the foreground; falls back to the device passcode after 5 failures
- **Credential migration**: on first launch, detect Keychain records with the old accessible attribute → read them → rewrite with `WhenUnlockedThisDeviceOnly` → delete the old records
- Output snippets are memory only; cleared after > 5 minutes in the background (the status summary is kept)

## 7. New guards (entering verify-macos.sh)

1. The `LocalAuthentication` import may only appear in CompanionApp/ (the Mac side takes no biometric dependency)
2. The test lock on the encoded key set of `MobilePairingRequest` is updated (3 new keys; command/path/parameter/environment are still forbidden)
3. `CGSessionCopyCurrentDictionary` is only allowed in `MobileTaskConsoleService.swift` (the single point of lock detection)
4. The output redaction function must have unit tests (one case per pattern) — a prerequisite for shipping the restricted level
5. All existing guards are unchanged (Process allowlist, funnel forbidden, tailscale in a single file, backup exclusion)

## 8. G6 acceptance checklist (real devices; M2b is declared complete only when all pass)

| # | Verification item | Pass criterion |
|---|---|---|
| 1 | Session visible | The phone sees the feed of tool launch and fixed task entries from the Mac; state changes arrive within ≤ 3 seconds of polling |
| 2 | Full task submission chain | Remotely (cellular), the phone submits swift test → (with everyTime, confirm on the Mac) → state running → succeeded + exit 0 |
| 3 | Output visibility | With the restricted default the phone sees the last 32 lines of redacted output; with minimal there is no output field; build a task output containing a fake token to verify redaction |
| 4 | Stop | The phone submits a long task (timeout 180) → tap stop on the phone → state stopped within ≤ 3 seconds |
| 5 | App lock | Killing and reopening the app needs Face ID; after locking, the phone's credentials are unreadable (being unable to connect proves it) |
| 6 | Rejection while locked | Lock the Mac → the phone submits a task → the receipt carries the screenLocked rejection copy |
| 7 | 30-day lifetime | Change the test pairing's pairedAt to 31 days ago → resume is rejected + explicit copy on the phone |
| 8 | Revocation unchanged | The Mac revokes the device / turns off the tunnel → all new operations are rejected at once (regression with the same semantics as G4 #6 / G5 #5) |
| 9 | Red-line review | The phone never sees command/path/variables/tool launch output; the backup JSON has no taskIntent/scope/output fields; diagnostics contain no task data |

## 9. Link to M3

M3 (remote allow window + daily unlock + panic code) is designed as its own project once M2b has been experienced on real devices: `MobileLaunchSession` is generalized into `RemoteAllowWindow` (tool + task set, user-set duration, immediate invalidation on lock/sleep/policy change, centralized rate limiting). This batch does not predefine its fields.
