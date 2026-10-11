# TermiPad M0 / M1 mobile entry design

**Source:** Aligned with `docs/product-roadmap.md` §5 stage 4 "M0/M1 — native iPhone app product and same-network pairing" + row 1 of `docs/t0-development-preparation-checklist.md` §6, "native iPhone same-network pairing: a real iPhone, a real Mac, a LAN, the system local network permission".

**Status:** Stage 2 takeover commit 2.1 (2026-08-29, zcode). **Design document only** — no code changes and no runtime code modified.

**2026-09-06 update (zcode):** The user confirmed using a free Apple ID (personal team) to support M1 real-device development verification — the "development verification" premise of G4 is unlocked; "long-term install / TestFlight / external distribution" still needs a paid membership (see §3.1, §6). The M1 implementation branch `feature/m1-local-network-pairing` started the same day. §3.4 revised: the Mac's paired device records are now stored only in the Keychain (the original SwiftData plan is dropped); see that section for the reasons.

**Scope:** M0 = a local prototype inside TermiPad that adds 6 user-controlled fields (all off by default) to each tool. Only **after M0 is complete** can the M1 same-network pairing implementation be considered. **M0 needs no external conditions** (no iPhone, no Apple Developer account, no Bonjour); **starting M1 needs gate G4** (a real iPhone + a real Mac + a LAN + the system local network permission).

**Inherited red lines**: `product-roadmap.md` §7 "non-negotiable product red lines" — the Mac opens no public terminal, no arbitrary remote shell, commands cannot be rewritten by AI, minimal data return, every permission is revocable, local-first, not a replacement for professional remote terminals. **Nothing in this design crosses them.**

## 1. Where M0 / M1 / M2 / M3 sit in the product roadmap

`product-roadmap.md` §5 stages 4-7 give the full path. This document covers only M0 + M1:

| Stage | Name | Status | Start condition |
|---|---|---|---|
| Stages 0-3 | Mendocino core / P0 / P1 / P2 / T0 / T1 / T2 / icons | ✅ Done | — |
| **Stage 4: M0/M1** | Native iPhone app + same-network pairing | ❌ Not started | M0: none; M1: G4 (real device + LAN + Apple developer account) |
| Stage 5: M2 | Remote secure session | ❌ Not started | G5 (two devices + session service + attack surface audit) |
| Stage 6: M3 | Remote allow window | ❌ Not started | M2 stable + real usage feedback |
| Stage 7 | Release and ecosystem (Developer ID / notarization / Gatekeeper) | ❌ Not started | Apple developer account + real old-store upgrade |

**M0 counts as complete** = after stage 1 commit `414a417` on `feature/track-protocol-materials`, a **new** `feature/m0-implementation` branch (separate from `m0-m1-design`) exists with 3-5 commits implementing the M0 fields + guards + tests. M0 being complete is **not** the same as M1 being startable — see gate G4 in §6.

## 2. M0: local mobile entry prototype on the Mac

### 2.1 Goal

Add 6 user-controlled fields (all off by default) for **each tool** in TermiPad's tool edit panel. **After M0 is complete**: on the Mac the user can decide precisely "which tools may appear on the phone / whether the phone may request a launch / whether local confirmation is required". **Completing M0 needs no** external conditions (no iPhone, no Bot, no HTTPS domain, no Apple account).

**M0 is the shared foundation of every mobile entry** — whether the later choice is the iPhone main line, the Telegram backup line, or the PWA validation layer, the 6-field policy layer is reused. **After M0 is complete**, M1 (iPhone) or the Telegram-specific M1 (static HTTPS page) can start on top of this policy layer.

### 2.2 Data model: add 6 fields to `Sources/TerminalTool.swift`

Based on the `TerminalTool` field table in `docs/task-intent-data-dictionary.md` §6, **add 6 fields**:

| Field | Type | Default | Semantics |
|---|---|---|---|
| `mobileDisplayName` | `String?` | `nil` (use the local `name`) | Display name on the phone (short; may differ from the local `name`) |
| `mobileDescription` | `String` | `""` | Purpose description; **must never** contain commands/paths/variables; sanitized on the server side before the client shows it |
| `showInMobileEntry` | `Bool` | **`false`** | Whether it enters the minimal list of the phone catalog |
| `allowMobileLaunchRequest` | `Bool` | **`false`** | Allows the phone to request launches for **approved icons** |
| `mobileLocalConfirmPolicy` | `enum MobileLocalConfirmPolicy` | `.everyTime` | Local confirmation policy (see §2.3) |
| `revokeMobilePermissionAt` | `Date?` | `nil` | Immediate revocation timestamp, written when the "Revoke" button is clicked |

**Relationship to existing fields**: the 6 fields do **not** replace or modify `name` / `executablePath` / `commandTemplate` / `variableValuesJSON` / `workingDirectoryPath` / `customIconFilename` / `iconURLString` / `metadataProvenance*` or any other existing field. **M0 is an overlay.**

**Red-line constraints** (consistent with `docs/task-intent-data-dictionary.md` §6):
- The 6 fields **never** enter the JSON backup (same as `workingDirectoryPath` / `customIconFilename` — see §2.5)
- The 6 fields do **not** enter diagnostic events (apart from specially added audit events like `taskProposalExpiringSoon` — reads/writes of M0 fields are currently **not** recorded, because the fields themselves are UI settings, not task lifecycle)
- The 6 fields are **not** returned through T2 MCP (the 8-field allowlist of `LocalMCPTaskState` is fixed; no M0 fields are added)

### 2.3 Enum `MobileLocalConfirmPolicy`

```swift
enum MobileLocalConfirmPolicy: String, Codable, CaseIterable, Sendable {
    /// Every phone request requires the local Mac user to click confirm in the workbench
    case everyTime
    /// No repeated confirmation within the same session (≤5min); a new or timed-out session must be confirmed again
    case perSession
    /// Only sessions within 5min and only when the task risk is .low; everything else requires confirming again
    case lowRiskSessionOnly
}
```

**Why 3 cases**: the red line "every permission is revocable" in §1 of the original plan implies the confirmation policy cannot be "allow forever"; `perSession` and `lowRiskSessionOnly` both rely on session timeout = forced re-confirmation, and there is **no** never-expire option. `everyTime` is the strictest default.

### 2.4 Tool edit panel UI: new "Mobile Entry" section

Append a section to `ToolEditView` in `Sources/LaunchpadView.swift` (lines 875-1118):

```
Edit Tool
├── Basics (existing)
├── Launch command (existing)
├── Organize (existing)
├── Tool Status (existing)
├── Working Directory (existing)
├── Custom Icon (existing)
├── **Mobile Entry** (new in M0)
│   ├── Mobile Display Name (TextField)
│   ├── Mobile Description (TextField, vertical 2-4 line)
│   ├── Show in Mobile Entry (Toggle, default off)
│   ├── Allow Mobile Launch Requests (Toggle, default off, gated by the previous item)
│   ├── Local Confirmation Policy (Picker: everyTime / perSession / lowRiskSessionOnly)
│   └── [Revoke Mobile Permission] (Button, role: .destructive, sets revokeMobilePermissionAt = now)
├── Icon selection (existing)
└── Source & Trust (existing)
```

**accessibility identifiers**: `tool-mobile-entry-section` / `tool-mobile-show-in-entry` / `tool-mobile-allow-launch` / `tool-mobile-confirm-policy` / `tool-mobile-revoke`.

**Revoke button** (`revokeMobilePermissionAt`): **not a hidden field** — it is a destructive button that, **immediately on click**, writes `Date()` into `revokeMobilePermissionAt` and **clears** `allowMobileLaunchRequest` and `showInMobileEntry` (double protection: revocation timestamp + both fields off). After revoking, the user **can** check the options again (revocation is **not** a permanent blocklist; it is "withdraw the current session state immediately").

### 2.5 Backup and privacy (consistent with `docs/task-result-minimal-spec.md` §2)

The 6 fields **never leave in a JSON backup**. **The type signatures in `Sources/BackupService.swift` already guarantee this** — `TermiPadBackup.make(tools:candidates:...)` only accepts `[TerminalTool]`, and after commit 1.5 `TermiPadBackup.ToolRecord.init(tool:includeSavedVariableValues:)` does **not** copy the 6 fields.

**Verification** (the pattern established by `Tests/TermiPadTests/BackupServiceTaskExclusionTests.swift`): after M0 is implemented, add `BackupServiceMobileFieldExclusionTests.swift` asserting that the JSON does **not** contain the 6 field names.

**verify-macos.sh static guard** (the commit 1.5 pattern): after M0 is implemented, add a `mobile_entry_code` block requiring that `Sources/BackupService.swift` does **not** contain any of the field names `mobileDisplayName` / `mobileDescription` / `showInMobileEntry` / `allowMobileLaunchRequest` / `mobileLocalConfirmPolicy` / `revokeMobilePermissionAt`.

### 2.6 Diagnostic events (consistent with `docs/task-result-minimal-spec.md` §4)

M0 adds **no** `DiagnosticEventKind`. **Why**:
- The 6 fields are UI settings, not task lifecycle events
- The existing `taskExecutionResultRead` does not contain M0 fields either
- A click on the revoke button is UI behavior, not task behavior — recording it in diagnostics would pollute the audit semantics

**The only addition**: when the revoke button fires, **write 1 new `DiagnosticEventKind.mobilePermissionRevoked`** (can be added at the commit 2.x stage if M0 implementation begins). **The M0 design stage does not prejudge this** — it is left to the implementation commit.

### 2.7 M0 completion bar

| Verification item | Form |
|---|---|
| The 6 fields persist | `MobileEntryTests.swift`: SwiftData round-trip |
| The 6 fields default to false/nil/everyTime | `MobileEntryTests.swift` |
| The 6 fields stay out of the JSON backup | `BackupServiceMobileFieldExclusionTests.swift` |
| Static guard on `Sources/BackupService.swift` | `verify-macos.sh` `mobile_entry_code` block |
| UI section visible + revoke button | New scenario in `TermiPadUITests.swift` |
| Full `verify-macos.sh` green | baseline `.verification/<timestamp>/summary.md` |

## 3. M1: local network pairing

### 3.1 Start condition (gate G4)

Row 1 of `docs/t0-development-preparation-checklist.md` §6 + G4 in `docs/product-roadmap.md` §8: "native iPhone same-network pairing tested successfully on two real devices — not started; affected by Apple device/signing conditions."

| Gate | Meaning | Current status (2026-09-06) |
|---|---|---|
| Real-device install signing | A free Apple ID (personal team) is enough for Xcode real-device debugging: ≤3 apps per device, App ID / device registration expires after 7 days and needs re-signing, and the iPhone needs Developer Mode on; CloudKit / Developer ID / notarization / TestFlight remain paid-only | ✅ Unlocked (the user already has a free account; a paid membership is needed only for "long-term install / distribution / iCloud") |
| Real iPhone | A physical iPhone, iOS 16+, Developer Mode on | ⚠️ Provided by the user |
| Real Mac | The current development machine is enough | ✅ |
| LAN | Same Wi-Fi, discoverable via Bonjour | ⚠️ Provided by the user |

**M0 complete ≠ M1 startable**. M0 is local work on the Mac and does **not** depend on G4. **The M1 design can be written now** (commit 2.1). Since 2026-09-06 the development verification premise is in place — the M1 implementation branch `feature/m1-local-network-pairing` has started; **two-device real-device acceptance (G4 complete) still needs the user to provide a real iPhone + LAN**, and G4 must not be declared passed before it is actually tested.

### 3.2 Technology choice: Network framework + Bonjour + local TLS

**Why not** WebSocket / NFS / iCloud / third-party push:
- WebSocket: **needs a server** — TermiPad is a local app that opens nothing to the public internet
- NFS: a macOS file sharing protocol, **not meant for RPC**
- iCloud: depends on an Apple Developer account + real multiple devices — **blocked the same way as G4**
- Third-party push (APNs/FCM): **must go through Apple/Google servers** — violates the red lines

**Why** Network framework + Bonjour + local TLS:
- Network framework is the modern networking API on macOS 14+ (replacing BSD sockets)
- Bonjour (mDNS) is designed **exactly** for LAN device discovery — an iPhone and a Mac on the same Wi-Fi find each other without a server
- Local TLS 1.3 prevents sniffing on the same Wi-Fi; self-signed certificates are verified by both sides on first use (the Mac shows the fingerprint for the user to enter on the iPhone)

### 3.3 Pairing flow

```
iPhone App (future)               Mac (TermiPad)
       │                              │
       │ 1. Open the iPhone app, enter the Mac's LAN hostname (or scan a code)
       │ ─────────────────────────────────────────────►
       │                              │
       │                          2. Bonjour discovers the iPhone
       │                          3. The iPhone starts the TLS 1.3 handshake
       │ ◄─────────── TLS handshake + self-signed certificate ──────────
       │                              │
       │ 4. The iPhone shows the fingerprint provided by the Mac (e.g. "AB12:CD34:...")
       │    The user enters/confirms the fingerprint on the iPhone
       │ ──────── verified fingerprint (SHA-256) ──────►
       │                              │
       │                          5. Both sides exchange:
       │                          - Mac: pushes its public key + short-lived nonce
       │                          - iPhone: pushes its public key + short-lived nonce
       │                              │
       │ 6. Each side stores the other's public key + nonce + paired-device ID
       │    (Keychain on iPhone, SwiftData + Keychain on Mac)
       │                              │
       │ 7. Pairing complete; the iPhone can request "list tools" + "launch tool"
       │                              │
       ▼                              ▼
```

**Key points**:
- Pairing **happens only once** — later communication uses both public keys + short-lived session keys
- The **fingerprint must** be confirmed **by eye** by the user on the iPhone — this is the key to resisting man-in-the-middle attacks
- After pairing the iPhone is in the `PairedDevice` list — it can be **revoked in the Mac workbench** (there **must** be a revocation path, §7 red line "every permission is revocable")

### 3.3.1 Session resume protocol (added 2026-09-06, prerequisite for G4 #4-6)

The pairing code is one-off and the connection drops right after pairing — a reconnecting paired phone must be recognizable by the Mac without the user entering a code again.

**Persisted on the phone** (written to the iOS Keychain when pairing completes, reusing the same `KeychainStore` service domain):
- Its own X25519 private key (long-term identity, replacing the first version's "generated temporarily for each pairing")
- The Mac public key + Mac fingerprint (trust anchor = the string compared by eye at first pairing)
- `deviceID` (issued in the Mac's ack)

**Resume handshake** (unlike the §3.3 pairing handshake: the Mac still sends `MacHello` first, and the phone branches on whether it has local credentials):
1. After connecting, the phone sends `PhoneResumeHello { protocolVersion, deviceID, phonePublicKey, phoneNonce }` (no pairingCode field — the Mac tells the pairing/resume hellos apart by which fields exist)
2. The Mac verifies: pinned version; looks up the active device by `deviceID`; `SHA256(phonePublicKey) == record.publicKeyHash` — a changed public key is rejected
3. Each side derives the session key: ECDH + HKDF-SHA256 (salt = macNonce ‖ phoneNonce, info = `termipad-m1-resume-v1`, a different info domain from the pairing derivation)
4. The Mac replies with a **plaintext** `MacResumeHello { protocolVersion, macPublicKey, macNonce }` (public key and nonce are not secret); the phone accepts only after verifying `SHA256(macPublicKey) == the stored Mac fingerprint` — **both directions of the binding are required**
5. All later frames are AEAD-encrypted

**Request channel** (G4 #4-6): one request and one response per connection, disconnecting after the response (no long-lived connection, no server-side state):
- `listTools` → `[MobileToolSummary]` (only tools with `showInMobileEntry == true`; the 4-field allowlist is unchanged)
- `requestLaunch` → after local confirmation per `mobileLocalConfirmPolicy`, the Mac runs it through the existing terminal launch path
- Operations outside the allowlist are always rejected and disconnected

### 3.3.2 requestLaunch launch request (added 2026-09-07, G4 #5)

**Phone side**: tap a tool card → send `requestLaunch { toolID }` (encrypted resume channel, the same handshake as listTools) → receive one of three results: `accepted` (the Mac user confirmed and it was handed to the terminal) / `pendingLocalConfirm` (waiting for the Mac user to confirm on the Mac — the phone shows "please confirm on the Mac") / `rejected` (the tool does not have `allowMobileLaunchRequest` on, or the policy rejected it).

**Mac-side execution chain** (the order cannot be swapped):
1. **Eligibility pre-check** (the MainActor reads SwiftData): `showInMobileEntry == true` **and** `allowMobileLaunchRequest == true` **and** `revokeMobilePermissionAt == nil` — if any fails, `rejected`, with no confirmation prompt shown
2. **Local confirmation** (per `mobileLocalConfirmPolicy`):
   - `.everyTime` (default): prompt for confirmation every time
   - `.perSession` / `.lowRiskSessionOnly`: in the M1 stage **always downgraded to everyTime** — session caching is a later optimization; converge on the strictest first

**perSession/lowRisk enablement semantics (added 2026-09-08, M1.1 batch)**: after the full G4 #5 chain passed, the downgrade is lifted, and the real behavior is —
- **Session definition**: an allowlist record in the Mac main process's memory (`[toolID: Date]`), **never written to disk or backups**. It is written on every successful local confirmation; restarting the Mac / reopening the pairing listener clears it — the lifetime of the confirmation cache never exceeds the Mac process's lifetime.
- **`.perSession`**: allowlist hit and ≤5 minutes since the last confirmation → launch directly without confirmation; otherwise take the everyTime prompt, and refresh the timestamp after confirming.
- **`.lowRiskSessionOnly`**: adds a task risk gate on top of perSession — only tools that `TemplateRisk` judges low-risk (no template variables, no shell metacharacters — item 4 of the eligibility pre-check already guarantees no variables) can skip confirmation; everything else is everyTime.
- **Timeout revocation**: the allowlist entry expires if not refreshed for more than 5 minutes; revoking a tool's mobile permission on the Mac (`revokeMobilePermissionAt != nil`) removes it from the allowlist immediately.
- **Diagnostics**: a direct launch without confirmation records one fixed-enum audit event `mobileLaunchAutoConfirmed` (timestamp and terminal target only, **no** tool name / device name — the `DiagnosticEventKind` privacy discipline forbids storing tool names); reading it together with `launchSucceeded` shows "which launches skipped confirmation" (aligned by timestamp).
- **Red line unchanged**: no confirmation ≠ unattended and always on. The Mac must have the pairing listener on (off by default) and be within the 5-minute session window; the user can withdraw it at any time by switching the policy back to everyTime or turning the listener off.
3. **Confirmation UI**: a macOS alert (tool name + "launch request from paired device <device name>"); it continues only when the user clicks "Launch"; no response to the alert within 60 seconds counts as a denial (prevents requests from hanging on an unattended Mac)
4. **Execution**: after confirmation it is handed to the user's chosen terminal through the existing `TerminalLauncher` — **no** new execution path is added, and the command always comes from the `commandTemplate` saved on the Mac
5. **Response**: return `accepted` as soon as the launch handoff completes; return `rejected` if the user clicks deny or it times out

**Red line**: the phone never receives the command body / paths / variables / terminal output — only the three result enums. Nobody at the Mac (alert timeout) = denied, which is the direct expression of "the Mac is always the sole execution authority".

**Revocation semantics**: after the Mac revokes a device, its `PhoneResumeHello` is rejected at step 2 (a record with non-nil revokedAt is not in the active set) — revocation takes effect on resume immediately.

### 3.4 M1 data model (revised 2026-09-06)

`PairedDevice` is **no longer** a SwiftData entity — device records and the pairing identity are **stored only in the Keychain**. Reasons: (a) the Keychain naturally stays out of JSON backups, directly satisfying the §2.5 contract without adding a new backup exclusion guard; (b) public-key fingerprints and device identity belong to the credential domain, on the same level as the API key; (c) it is implemented as `Sources/PairedDeviceStore.swift` (`PairedDeviceRecord: Codable` + a Keychain index account), with an injectable storage backend, so tests use an in-memory implementation and never hit the real SecItem (consistent with the `KeychainStoreTests` discipline).

```swift
struct PairedDeviceRecord: Codable, Sendable, Equatable {
    let id: UUID
    let displayName: String           // entered on the iPhone at pairing
    let publicKeyHash: String         // SHA-256 fingerprint of the iPhone public key at pairing
    let pairedAt: Date
    var lastConnectedAt: Date?
    var revokedAt: Date?              // revocation timestamp
}

enum PairedDeviceOperation: String, Codable {
    case listTools                // list tools with showInMobileEntry=true
    case requestLaunch            // request a launch for allowMobileLaunchRequest=true
    case listScopes               // list task scopes (TaskProjectScope.displayName + availability)
    case listFixedTasks           // list FixedTaskCatalog.definitions
    case requestTaskProposal      // submit a task proposal (needs local confirmation)
    case getTaskStatus            // read task status
    case cancelTask               // cancel a task that has not started
    case heartbeat                // once every 30s
}
```

**The 8 cases are the operation allowlist introduced by M1 — every iPhone request must match this enum, otherwise it is rejected**. This is consistent with the restricted case design of `LocalMCPBridgeOperation` in `Sources/TaskMCPBridge.swift`.

### 3.5 Verifying M1

M1 verification **cannot** be completed on the Mac side alone — a real iPhone is required:

| Verification item | Form | Gate |
|---|---|---|
| Bonjour discovery | iPhone + Mac on the same LAN discover each other | G4 (real device) |
| TLS handshake | mutual fingerprint verification | G4 |
| Pairing succeeds | `PairedDevice` is persisted | G4 |
| Revocation path | The user revokes in the Mac workbench → the iPhone gets no response immediately | G4 |
| Launch request | Tap an icon on the iPhone → the Mac workbench prompts for confirmation → the user confirms → `TerminalLauncher.launch` | G4 + `mobileLocalConfirmPolicy` |

**M1 must be implemented only after gate G4 is in place** — `docs/post-takeover-plan.md` (commit 2.2) lists the G4 status explicitly. The steps and evidence requirements for two-device acceptance are in `docs/m1-g4-verification-guide.md`.

## 4. M0 vs M1 implementation paths

| Stage | Work | Branch | Expected commits | Blocker |
|---|---|---|---|---|
| M0 design | This document (commit 2.1) | `feature/m0-m1-design` | 1 | None |
| M0 implementation | Data model + enum + tool edit UI + backup guard + unit tests + UI tests | `feature/m0-mobile-entry-prototype` | 3-5 | None (**does not depend on G4**) |
| M1 design | Technology choice (Network/Bonjour/TLS) + pairing flow + data model + verification plan | `feature/m0-m1-design` (§3 of this document) | 1 | None |
| M1 implementation | Pairing core + listener + PairedDeviceStore + iPhone app | `feature/m1-local-network-pairing` (started 2026-09-06) | 5-10 | Development verification is unblocked (free personal team signing); two-device testing awaits an iPhone + LAN |
| M2 design + implementation | Outbound long-lived connection + session model | `feature/m2-remote-secure-session` | 10+ | **Gate G5** |

## 5. Relationship to the hardened materials of §4 in the original plan

Starting M0 depends on **all completed** stage 1 commits:

| Stage 1 commit | What M0 depends on |
|---|---|
| §4.1 data dictionary (`docs/task-intent-data-dictionary.md`) | The 6 fields extend the §6 "TerminalTool field table"; the document is updated in step |
| §4.4 minimal result spec (`docs/task-result-minimal-spec.md`) | The 6 M0 fields do not enter the T2 MCP return allowlist; a new guard ensures it |
| §4.5 migration and backup decision (commit `6b931c4`) | The 6 M0 fields do not enter the JSON backup — the baseline the new guard extends |

**The M0 implementation commits should**:
1. Add the 6 fields to `Sources/TerminalTool.swift`
2. Add 6 rows to the "TerminalTool field table" in `docs/task-intent-data-dictionary.md` §6
3. Add 1 row (the revoke button event) to the audit event table in `docs/task-result-minimal-spec.md` §4
4. Add the `mobile_entry_code` block to `scripts/verify-macos.sh`
5. Add `Tests/TermiPadTests/MobileEntryTests.swift` + `BackupServiceMobileFieldExclusionTests.swift`
6. Add 1 UI scenario (open the tool edit panel + see the Mobile Entry section)

## 6. Status of gate G4 (updated 2026-09-06)

**The development verification premise is in place; two-device testing has not started — G4 has still not passed.**

| G4 component | Status |
|---|---|
| Real-device install signing | ✅ Free Apple ID (personal team): Xcode real-device debugging works, with limits of 3 apps/device, App ID / device registration expiring after 7 days, 10 App IDs/week, and 3 devices; the iPhone needs Developer Mode on |
| Real iPhone | ⚠️ To be provided by the user |
| LAN | ⚠️ To be provided by the user |
| Two-device Bonjour/TLS/pairing/revocation testing | ❌ Not started — G4 must not be declared passed before it is done |

**Limits of the free account**: it only supports development verification. The phone app must be re-signed from the Mac every 7 days and cannot be used as a long-term tool; TestFlight, long-term install, Developer ID external distribution, and iCloud remain paid-membership-only.

**M1 start decision tree (executed)**:
- ✅ Development verification premise in place → the `feature/m1-local-network-pairing` branch has started, implementing §3.2–§3.4
- ⚠️ Two-device testing → wait for an iPhone + LAN and run §3.5; record the results in `docs/post-takeover-plan.md` and `product-roadmap.md` §8

## 7. Red lines confirmed again

Every M0/M1 implementation **must** satisfy `docs/product-roadmap.md` §7:

| Red line | How the M0/M1 implementation satisfies it |
|---|---|
| The Mac opens no public terminal | M1 uses Bonjour LAN discovery and does **not** listen on a public port |
| No arbitrary remote shell | The PairedDeviceOperation enum is a fixed allowlist of 5 cases |
| Commands cannot be rewritten by AI | The iPhone can only request launches of tools with `showInMobileEntry=true`, and the command is the `commandTemplate` saved on the Mac |
| Minimal data return | The `listTools` response the iPhone receives contains **no** commands/paths/variables — only `id` / `mobileDisplayName` / `mobileDescription` / an icon identifier |
| Every permission is revocable | Double revocation via `PairedDevice.revokedAt` + `TerminalTool.revokeMobilePermissionAt` |
| Local-first | All data is stored in the Mac's SwiftData; the 6 fields are never sent out |
| Not a replacement for professional remote terminals | The iPhone can only "launch" existing tools and **cannot** enter arbitrary commands |

## 8. Maintenance rules

- Any M0 implementation commit must **update in step** the 5 materials listed in §5
- Any commit starting M1 must first confirm the status of gate G4 in `docs/post-takeover-plan.md` (commit 2.2)
- Any later commit that finds gate G4 is not in place must update §6 of this document **first** and write code **afterwards**
