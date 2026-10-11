# TermiPad post-takeover plan

**Source:** Aligned with all 5 rows of the table in `docs/t0-development-preparation-checklist.md` §6 "external conditions needed only in later phases" + `docs/product-roadmap.md` §5 stages 4-7.

**Status:** Stage 2 takeover commit 2.2 (2026-08-29, zcode). **A pure cross-reference document** — it draws the 5 rows of §6 of the original plan × current status × takeover progress as one table.

**Scope:** Let anyone taking over, or the user, see at a glance "what is left of the original plan, who is blocking, and how far I have got".

## 1. Takeover point

- **The commit where the previous AI (Manus AI) stopped**: `8e73e76` "Document Launchpad handoff" (2026-08-28)
- **The first commit** of the one taking over (zcode): `1189a30` "Mark TaskMCPBridge.serviceName as nonisolated" (2026-08-29, Swift 6 warning fix + todo facts filled in)
- **Post-takeover stage 1 complete** (6 commits, branch feature/track-protocol-materials): all 6 rows of materials in §4 of the original plan, "materials and evidence that must be maintained", are hardened
- **Post-takeover stage 2 in progress** (2 commits, branch feature/m0-m1-design): the M0/M1 mobile entry design document
- **Current document**: this one

## 2. Cross-reference of the whole §6 table of the original plan (status of the "5 phases waiting to start")

The 5 rows of the table in `docs/t0-development-preparation-checklist.md` §6 × current status × who is blocking:

| Row of §6 in the original plan | Matching `product-roadmap.md` stage | What I can do (no external conditions) | Blocked on you (external conditions) | Next branch name |
|---|---|---|---|---|
| 1. Native iPhone same-network pairing | Stage 4: M0/M1 | ✅ **M0 is implemented and merged into master**. **M1 Mac side + iPhone companion are implemented** (`feature/m1-local-network-pairing`, 8 commits) | ⚠️ **G4 testing in progress (3/7 passed, 2026-09-06)**: Bonjour discovery ✅ fingerprint comparison ✅ pairing persisted ✅; testing of session encryption / launch requests / revocation awaits the request channel implementation; 7-day re-signing to be observed. Long-term install / TestFlight are still ❌ paid membership | Next batch: session resume protocol + listTools channel |
| 2. Native iPhone long-term install / distribution | Stage 7 | ❌ (meaningful only after M1 is complete) | ❌ Apple Developer Program account + App Store / TestFlight eligibility | A separate project after M1 is complete |
| 3. Remote session / PWA | Stage 5: M2 | ❌ (meaningful only after M1 is complete) | ❌ **Gate G5**: HTTPS origin + device identity + session service + revocation model | After M1 is complete: `feature/m2-remote-secure-session` |
| 4. Telegram Mini App | Backup line for stages 4/5 (mutually exclusive with 1) | ❌ | ❌ A private Bot + Keychain storage of the Bot token + a fixed HTTPS origin + server-side `initData` validation | After the M0 implementation is complete, compare with the iPhone main line and let the user decide the entry route |
| 5. macOS external distribution (Developer ID / Hardened Runtime / notarization / Gatekeeper cold start) | Stage 7 | ✅ The script skeleton and documentation are in place (`scripts/release-build.sh` + `docs/release-build.md`) | ❌ A paid Apple Developer certificate + real old-store upgrade verification — actual signing/notarization has not been run | Skeleton done; execution waits for the paid certificate |

**Conclusion (updated 2026-09-06)**: M0 is implemented and merged into master; M1 development verification is unlocked (free personal team signing), and the implementation branch `feature/m1-local-network-pairing` is in progress. The remaining blockers have narrowed to: a real iPhone + LAN (G4 two-device testing) and a paid Apple Developer membership (long-term distribution / TestFlight / iCloud / G6).

## 3. Work completed in stage 1 (commit `414a417` in `feature/track-protocol-materials`)

zcode's hardening for each of the 6 rows of materials in §4 of the original plan:

| Row of §4 in the original plan | Document / guard / test commit | What changed |
|---|---|---|
| 1. TaskIntent data dictionary | `46fb263` `docs/task-intent-data-dictionary.md` | A 158-line document: 5 entities × 6 enums × the three axes "cross-entry / backup / diagnostics" per field |
| 2. Policy rejection matrix | `47f2721` changes `TaskIntentPolicyTests.swift` | 78 → 88 unit tests: keeps 5 integration tests + adds 10 independently named tests (9 rejection paths + 1 scope ID mismatch) |
| 3. Process tree and cancellation evidence | `f166db3` adds `TaskExecutionServiceTests.swift` | 88 → 93 unit tests: 5 real-process integration tests (exit 0 / exit 7 / stop / already started / unapproved) |
| 4. Minimal result spec | `05ca7e4` `docs/task-result-minimal-spec.md` + 2 new `DiagnosticEventKind`s + 1 line of two-layer bridge audit | A 115-line document: 4 state enums × field allowlist × red-line table × mapping of 19 diagnostic events |
| 5. Migration and backup decision | `6b931c4` adds `BackupServiceTaskExclusionTests.swift` + a new `backup_code` guard in `scripts/verify-macos.sh` | 93 → 96 unit tests + 23 → 24 static guards |
| 6. Harmless test task set | `414a417` changes `Sources/TaskIntent.swift` | FixedTaskCatalog 3 → 5 (adds `swiftBuild` + `swiftPackageCheck`) |
| 7. Verification artifacts | Unchanged | Every commit runs `./scripts/verify-macos.sh`, archived to `.verification/<timestamp>/` |

## 4. Stage 2 progress (branch `feature/m0-m1-design`)

| commit | Content | Status |
|---|---|---|
| `f3d5196` `docs/m0-m1-mobile-entry-design.md` | M0 data model + semantics of the 6 fields + UI section design + backup privacy contract; M1 Network/Bonjour/TLS choice + the 7-step pairing flow + notes on gate G4 | ✅ pushed |

`post-takeover-plan.md` (**this document**) cross-references the whole §6 table (commit 2.2)

## 5. Summary diagram of takeover progress

```
8e73e76 (where Manus AI stopped)
    │
    ├── 1189a30 (Swift 6 warning + todo facts filled in) ←—— zcode's first commit
    │
    ├── feature/track-protocol-materials (stage 1, 6 commits)
    │     ├── 46fb263 §4.1 data dictionary
    │     ├── 47f2721 §4.2 policy rejection matrix
    │     ├── f166db3 §4.3 process tree evidence
    │     ├── 05ca7e4 §4.4 minimal result spec
    │     ├── 6b931c4 §4.5 migration and backup decision
    │     └── 414a417 §4.6 harmless test task set
    │
    └── feature/m0-m1-design (stage 2, 2 commits)
          ├── f3d5196 M0/M1 design document
          └── (this document) 2.2 post-takeover plan ←—— you are reading this
```

## 6. Decision tree for next steps

The 5 phases of the original plan, from "what I can do now" to "blocked on you":

```
                                ┌── (a) What I can do: stage 3 release-build script skeleton (1 commit) ──┐
                                │                                                                │
                                │   ┌── (b) M0 implementation (3-5 commits, no external blocker) ──┐     │
                                │   │                                          │                │
5 rows of §6 in the original plan ──  │   │                                          │                │
   1. iPhone same-network pairing ───────►   ─┤   │                                          │                │
   2. iPhone long-term distribution ──────►   blocked on Apple Developer                      │                │
   3. Remote session / PWA ────────►   blocked on G5 (HTTPS origin + device identity)          │                │
   4. Telegram Mini App ────►   blocked on Bot + HTTPS + Apple Developer             │                │
   5. macOS external distribution ────────►   ─┘   ───────────────────────────────────┘                │
                                                                                          │
                                                                          ⬇︎                ⬇︎
                                                                feature/m0-mobile-entry-prototype
                                                                                          feature/release-build-skeleton
```

**Of the 5 phases of the original plan, stage 1 has completed 1/5 (the §4 maintained materials with no external blocker)**. **Stage 2 has started the design (commits 2.1/2.2)**. **The actual M0 implementation (commit 3.x) is the next thing I can push forward immediately** — not blocked by G4.

## 7. Maintenance rules

- **Any commit starting M0/M1/M2/M3**: must update the tables in §2 / §6 **first** and write code **afterwards**. The tables are the source of truth for gate status.
- **Any newly found change in the status of gates G4/G5**: say **explicitly** in the commit message "G4 status: ✅ / ❌ / ⚠️".
- **Any outdated field in post-takeover-plan**: the next takeover commit must update this document + reference it in the commit message.
- **This document should not delete any historical branch reference** — the full takeover path is kept as audit evidence.
