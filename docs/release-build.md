# TermiPad external distribution build (release build)

**Source:** Aligned with row 5 of `docs/t0-development-preparation-checklist.md` §6, "macOS external distribution: Developer ID, Hardened Runtime, notarization, Gatekeeper cold start test — still an external release gate" + stage 7 of `docs/product-roadmap.md` + `docs/private-beta-release-audit.md` §2 "current blockers".

**Status:** Stage 3 takeover commit 3.1 (2026-08-29, zcode). **Documentation + script skeleton** — `scripts/release-build.sh` is in place (placeholder signing / notarization / staple steps that degrade to printing without the external conditions); **the full flow cannot** run in the current environment (it depends on an Apple Developer Program account + certificate + notary profile).

**Scope:** The current `project.yml` explicitly uses ad hoc signing (`CODE_SIGN_IDENTITY: "-"`) and `ENABLE_HARDENED_RUNTIME: NO` (`project.yml:18-20`), which **suits local builds on a development machine and UI Runner verification**. It is **not** a Developer ID distribution configuration. This document + `scripts/release-build.sh` provide the full flow for **switching to Developer ID distribution**, but **actual signing/notarization** depends on the external conditions in §1 of this document.

## 1. External conditions (required to run the full flow)

| Condition | Purpose | Current status | Source |
|---|---|---|---|
| Apple Developer Program account ($99/year) | Registers the certificate identity + notarization identity | ❌ Not available | User decision |
| Developer ID Application certificate | Signing identity for macOS external distribution | ❌ Not available | From the Apple Developer Program account |
| Developer ID private key exported to the keychain | Lets xcodebuild / codesign use it | ❌ Not available | After the above is issued, export from Xcode → Accounts → Manage Certificates |
| App Store Connect API key (p8 file) | notarytool notarization | ❌ Not available | App Store Connect → Users → Keys → generate |
| Keychain profile holding the API key | `xcrun notarytool store-credentials` | ❌ Not available | After the API key above is generated |
| A real Mac (available) | Runs build / signing / notarization | ✅ The current development machine is enough | — |
| Full Xcode | Toolchain | ✅ | — |
| notarytool (an xcrun subcommand) | Notarization | ✅ | Ships with macOS 13+ |

**The full flow depends on** **all** of the first 5 items above being available. Currently (commit 3.1) = 0/5 available.

## 2. Full flow (Developer ID signing → notarization → Gatekeeper pass)

```
   ┌──────────────────────────────────────────────────────┐
   │ 1. Prepare: enroll in Apple Developer + export the Developer ID private key │
   │    to the login keychain.                               │
   └──────────────────────────────────────────────────────┘
                              ↓
   ┌──────────────────────────────────────────────────────┐
   │ 2. Prepare: store the API key with xcrun notarytool store-credentials  │
   │    in the keychain (e.g. profile name "notaryprofile"). │
   └──────────────────────────────────────────────────────┘
                              ↓
   ┌──────────────────────────────────────────────────────┐
   │ 3. Change project.yml: remove ad hoc signing and        │
   │    ENABLE_HARDENED_RUNTIME: NO; use the release configuration  │
   │    (to be done in phase 7; this skeleton does not change it directly) │
   └──────────────────────────────────────────────────────┘
                              ↓
   ┌──────────────────────────────────────────────────────┐
   │ 4. Run ./scripts/release-build.sh --dmg                │
   │    - archive with the Release configuration             │
   │    - codesign with Developer ID + entitlements         │
   │    - hdiutil builds the DMG                            │
   │    - notarytool submit + wait                          │
   │    - stapler staple                                    │
   │    - runs the verify-release-artifact.sh self-check automatically │
   └──────────────────────────────────────────────────────┘
                              ↓
   ┌──────────────────────────────────────────────────────┐
   │ 5. Test on a clean Mac (Gatekeeper enabled, isolated environment): │
   │    download the DMG → double-click → does Gatekeeper let it through │
   │    evidence goes to release-evidence/<timestamp>/       │
   └──────────────────────────────────────────────────────┘
                              ↓
   ┌──────────────────────────────────────────────────────┐
   │ 6. Test the old-store upgrade path on a clean Mac:      │
   │    a Mac with v0.x installs v0.x+1 → the upgrade path does not break │
   │    SwiftData migration is correct (Sources/TermiPadDataStore.swift   │
   │    already has the recovery container fallback; see       │
   │    private-beta-release-audit.md §4)                   │
   └──────────────────────────────────────────────────────┘
```

## 3. What the skeleton script does

`scripts/release-build.sh` scripts step 4 of the flow above. **It is executable now** (commit 3.1 already ran `chmod +x`), and **its full function depends on** the external conditions in §1.

### 3.1 Script arguments

```bash
./scripts/release-build.sh [--skip-notarization] [--skip-staple] \
                           [--output-dir <dir>] [--dmg]
```

| Argument | Meaning |
|---|---|
| `--skip-notarization` | Skip the notarization step (**not recommended** — an un-notarized .app is rejected on a Gatekeeper-enabled Mac) |
| `--skip-staple` | Skip attaching the staple ticket (not recommended) |
| `--output-dir <dir>` | Custom output directory (default `./release-build/<timestamp>/`) |
| `--dmg` | Create a .dmg image (by default only the .xcarchive + .app are produced) |
| `-h` / `--help` | Show help (head -30 inside the script) |

### 3.2 Environment variables

| Variable | Purpose | Behavior when unset |
|---|---|---|
| `DEVELOPER_ID_APPLICATION` | Full signing identity, e.g. `"Developer ID Application: Foo (TEAMID)"` | Degrades to ad hoc signing (`-`), **not distributable** |
| `NOTARYTOOL_KEYCHAIN_PROFILE` | notarytool keychain profile name (e.g. `"notaryprofile"`) | The notarization step degrades to printing "what would be executed" |
| `BUNDLE_ID` | TermiPad Bundle ID (default `com.termipad.app`, matching `project.yml:34`) | Uses the default |
| `APPLE_TEAM_ID` | 10-character Apple Team ID | Not required for now (the notarization profile contains the Team ID) |

### 3.3 Output directory structure

```
release-build/<timestamp>/
├── summary.md                          # summary of each step's output log
├── TermiPad.entitlements               # entitlements required by Hardened Runtime, written by the script
├── TermiPad.xcarchive/                 # output of xcodebuild archive
│   └── Products/Applications/TermiPad.app
├── TermiPad.dmg                        # (only with --dmg) output of hdiutil
└── (release-evidence/<timestamp>/ is also created when the self-test runs verify-release-artifact.sh)
```

### 3.4 The skeleton's current "degrade" behavior

When environment variables are missing the skeleton **does not exit with an error** — it explicitly prints "⚠️ XXX is not set — degrades to ad hoc" and carries on through the pipeline. **Why**:
- The one taking over (zcode) currently has no certificate and **must** be able to run the skeleton on their own Mac to validate the syntax
- The degrade behavior is **explicitly visible** — `summary.md` records the reason for each degraded step
- When the user gets a certificate later, the script does **not** need changing — just set the environment variables and run again

## 4. `verify-release-artifact.sh` is its partner

- `release-build.sh` = **does** the archive + signing + notarization + staple
- `verify-release-artifact.sh` = **audits** the integrity of the signed .app

Full pipeline = `release-build.sh` finishes → self-check with `verify-release-artifact.sh --require-notarization` right away → evidence is written to `release-evidence/<timestamp>/`.

`verify-release-artifact.sh` already existed `before commit 1.5` (pre-takeover code) and is **not** part of zcode's takeover commit 3.1. **But** the script of takeover commit 3.1 calls it **automatically** as a self-check.

## 5. Example of invoking the full pipeline (once the external conditions are met)

```bash
# One-time: export the Developer ID private key to the login keychain (Xcode flow)
# One-time: store the API key with xcrun notarytool store-credentials

# For every release
export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAM1234567)"
export NOTARYTOOL_KEYCHAIN_PROFILE="notaryprofile"

cd ~/TermiPad
./scripts/release-build.sh --dmg

# Check release-build/<timestamp>/summary.md + release-evidence/<timestamp>/summary.md
```

## 6. Gatekeeper cold start acceptance (**isolated test on a real, separate Mac**)

Apple's official requirement: a distributed .app **must** be verified on a clean Mac with Gatekeeper enabled. This is the real meaning of item 5 in §1.

| Step | How to verify |
|---|---|
| 1. Find a Mac that **took no part in the build** (at home, a friend's, a colleague's) | — |
| 2. System Settings → Privacy & Security → make sure Gatekeeper = "App Store and identified developers" | — |
| 3. Copy release-build/.../TermiPad.dmg to that Mac | Via AirDrop / USB drive / scp |
| 4. Double-click the .dmg → it mounts → drag to /Applications | — |
| 5. Double-click the .app → Gatekeeper should show "cannot be opened because it is from an unidentified developer" | **If it does not appear** = the signature is wrong |
| 6. System Settings → Privacy & Security → "Open Anyway" | It should launch normally |
| 7. Test every feature: scanning, inbox, tool launching, backup export/import, task workbench, MCP switch | — |
| 8. Write the evidence to release-evidence/<timestamp>/gatekeeper-cold-start.md | — |

**Only when this step passes** can "v0.x+1 is ready for external distribution" be said.

## 7. Relationship to the red lines in §1 of the original plan

The red lines of `docs/product-roadmap.md` §7 carry over to the release process:

| Red line | How release-build reflects it |
|---|---|
| The Mac opens no public terminal | release-build listens on **no** port; notarization is an outbound call to Apple's notary service (one-way) |
| No arbitrary remote shell | The release binary has the same source as the development build (only the signing configuration in `project.yml` changes) |
| Commands cannot be rewritten by AI | Hardened Runtime entitlements strictly follow `TermiPad.entitlements` (no `com.apple.security.cs.disable-library-validation`) |
| Minimal data return | The notarytool upload contains only the .app binary + DMG size metadata and **no** user library, commands, or API key |
| Local-first | The release build enables a Hardened Runtime sandbox subset (**not** everything — the Apple Events permission is kept to drive Terminal/iTerm/Warp) |

## 8. Maintenance rules

- Any change in the status of the §1 external conditions (the user enrolled in the Developer Program / got a certificate) → update the table in §1 of this document **first**, then run the new build. The "degrade reasons" recorded in `summary.md` are key evidence for later audits.
- Any change to release-build.sh → it must **still** run with item 5/5 of §1 unavailable (correct syntax, every degrade path triggered, and the final summary.md recorded in full).
- Any new signing / notarization step → a node must be added to the flow diagram in §2 of this document.
- Evidence inside any release-evidence/<timestamp>/ is **never** deleted — it is key to tracing future release incidents.
