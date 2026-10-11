# TermiPad private beta pre-release audit

**Audit scope:** Private development and controlled beta candidates; excludes the Mac App Store and external distribution.

**Currently verified feature baseline:** `b6b37e7` (`Stabilize task workbench UI assertion`), including T2 local restricted MCP collaboration `3a60ffb`, its Swift 6 / Core Foundation compatibility fixes, the OpenCode `2025-11-25` exact protocol negotiation fix `5c7d202`, the workbench auto-save status feedback and stable UI smoke fixes `38aae06`/`0cdbc90`, the T1 local restricted task executor `5edeb8f`, the T0 local restricted task policy core `8750200`, the earlier local icon system `0265caf`, and the Mendocino workspace visual baseline `70d9d40`.

**Audit date:** 2026-08-27.

> This document is a release gate, not release notes. It records the local engineering work that is finished, and the separate conditions that must still be met before any external tester receives an installer.

## 1. Baseline completed and verified on a real Mac

On the user's Apple Silicon Mac (Xcode 26.6, Swift 6.3.3, XcodeGen 2.46.0), the Mendocino workspace baseline `70d9d40`, the local icon system batch `0265caf`, the T0 local restricted task policy core `8750200` / fix `1cb82d3`, the T1 local restricted task executor `5edeb8f` / fix `274d6ea`, and T2 local restricted MCP collaboration `3a60ffb` / compatibility fixes `030b747`, `f5383d3`, `2564665`, `6569c3a`, `4fe6472`, `5c7d202`, `44b8ae1`, `38aae06`, `0cdbc90` have all passed the full consolidated verification of `./scripts/verify-macos.sh`. The result directory of the latest regression verification is `.verification/20260829-213928` (the accept-all fix), with output `TEST EXECUTE SUCCEEDED` and `[PASS] ui-smoke-test`. `5c7d202` accepts exactly `2025-03-26` and the `2025-11-25` initialization version confirmed with OpenCode 1.14.33, and echoes the accepted version; it does not widen MCP tools, request fields, or execution permissions. An isolated read-only walkthrough was then run in OpenCode 1.14.33 with NVIDIA NIM's DeepSeek V4 Flash: only `termipad-local` was enabled, `quick9-wormhole` was temporarily disabled, and only `list_task_scopes` and `list_fixed_tasks` were called; the scope list came back empty and the fixed catalog returned three predefined tasks, with no task created, approved, run, or cancelled, and no commands, paths, arguments, environment variables, file contents, or terminal output returned. After the walkthrough the user turned off TermiPad's local MCP switch and set `termipad-local` back to `disabled` in the temporary OpenCode configuration. `44b8ae1` only lets UI tests continue with the existing page assertions when an accessible main window is presented but XCTest has not reported `.runningForeground`; `38aae06` keeps immediate auto-save and adds user-visible status feedback, and `0cdbc90` only narrows the UI smoke assertions to workbench boundary and switch elements that are stable across macOS versions. The flow also covers toolchain and script syntax checks, Swift source regression guards, the Swift Package manifest check, XcodeGen project generation, the native macOS build, UI Runner signature verification, and unit tests. This batch uses the 11-inch iPad Pro portrait workspace as the visual baseline for the first window and adapts to the macOS visible area; it only strengthens the native workspace panel, tool card, and auxiliary page hierarchy, and neither imitates an iPad device body nor changes feature/security behavior. UI tests explicitly isolate an in-memory data container and create the main window when macOS restores only the menu bar and not the window; on failure they automatically export launch state, UI hierarchy, and screenshot attachments.

| Verified or implemented control | Current conclusion | Evidence or implementation location |
|---|---|---|
| A candidate enters the library only after the user confirms | Implemented | `CandidateTool` state and `LaunchpadView.accept` |
| AI cannot generate or overwrite the launch command | Implemented, with regression tests | `AIService.swift`, trust boundary tests |
| GitHub accepts only the official mapping or a high-confidence match | Implemented, with regression tests | `GitHubService.swift` |
| GitHub owner avatars are not used as tool icons | Implemented; old URLs are not rendered, exported, or restored | `ToolIconView.swift`, `BackupService.swift` |
| API keys stay out of backups | Implemented | Keychain storage and `BackupService.swift` |
| The command is copied when Terminal/iTerm Automation is denied | Implemented; the hint text has unit tests | `TerminalLauncher.swift` |
| The old store is not deleted when the default data container fails | Implemented | `TermiPadApp.swift`, `TermiPadDataStore.makeRecoveryContainer` |
| The user deliberately imports JSON into an isolated recovery library | Implemented, with a UI smoke test | `DataStoreRecoveryView.swift`, `testRecoveryLaunchOffersBackupImport` |
| Implicit iCloud enablement | Explicitly forbidden | All local containers explicitly set `cloudKitDatabase: .none` |
| Mendocino Project Discovery Preview | Implemented and verified on real macOS | Off by default; only a manual user refresh of the fixed public GitHub CLI query; ETag cache, non-fork / non-archived filtering, local explainable ranking from public fields, rate-limit hints, and privacy-preserving diagnostics are all covered. It does not install software, generate commands, write to the library, or connect automatically. |
| P2-B controlled install review | Implemented and verified on real macOS | Only the built-in statically reviewed Homebrew core formula catalog; exact repository mapping; shows the expected CLI, review revision, date, and fixed command; it can be handed to the chosen terminal or copied only after the box is explicitly checked and the user confirms Homebrew manually. It does not install in-app, read README commands, support taps/casks, or collect automatically. |
| P2-C read-only environment report | Implemented and verified on real macOS | Only after a user click does it check Homebrew, Cargo, npm, pnpm, Bun, and Python at fixed absolute paths with `--version`; no shell, no network, no saved paths/versions; it does not install, upgrade, uninstall, or arbitrate conflicts. |
| Mendocino workspace visual strengthening | Implemented and verified on real macOS | The 11-inch iPad Pro portrait workspace as the visual baseline for the first window; adaptation to the macOS visible area, a native sidebar, soft workspace panels, and one hierarchy for tool cards and auxiliary pages; no imitation of a device shell or touch system controls. |
| Phase-two local icon system | Implemented and verified on real macOS | Extended local SF Symbol catalog; persisted fallback styles for unknown tools with deterministic assignment and collision resolution; manual selection / restoring the automatic icon by the user; local PNG has the highest priority; backup and restore keep the style identifier; the verification script forbids network icon resources. |
| T0 local restricted task policy core | Implemented and verified on real macOS | Fixed task catalog, project scope, short local review window, risk level, nonce, expiry, cancellation, revocation, and fixed diagnostic events; task scopes and history stay out of JSON backups and privacy diagnostics. T0 only reviews policy; it runs no commands, creates no processes, and connects to no network, MCP, mobile entry, or PTY; the verification script forbids these capabilities. |
| T1 local restricted task executor | Implemented and verified on real macOS | Consumes only fixed tasks approved by T0; runs with the project scope as the current directory, a fixed executable and arguments, and empty stdin/stdout/stderr; supports stopping and a task-level timeout, and stores only state, time, and exit code. No shell, PATH search, network, MCP, mobile entry, PTY, terminal handoff, or full output retention. |
| T2 local restricted MCP collaboration | Implemented, verified on real macOS, and the isolated OpenCode read-only walkthrough is done | When the user explicitly turns it on on the Mac and the app is running, the separate `stdio` server can, only through the local CFMessagePort bridge, list project scopes / fixed tasks, propose tasks for local review, read minimal status, or cancel tasks that have not started. OpenCode 1.14.33's `2025-11-25` negotiation and the read-only `list_task_scopes`/`list_fixed_tasks` were exercised on the real machine, and the service was turned off again afterwards. The bridge provides no authentication, but it also opens no network, HTTP/WebSocket, arbitrary shell, paths, arguments, environment variables, file browsing, PTY, terminal handoff, or full output; the stdio layer does not access SwiftData directly. |

## 2. Current blockers: it cannot be published or distributed externally as is

The current `project.yml` explicitly uses ad hoc signing (`CODE_SIGN_IDENTITY: "-"`) and sets `ENABLE_HARDENED_RUNTIME` to `NO`. This suits builds and UI test Runner verification on a development machine, but it is **not a Developer ID distribution configuration**. So the current state can serve as a controlled development and self-test version and cannot be described as a release build ready for external download and install.

Apple's recommendation for distribution outside the Mac App Store is to sign with **Developer ID** and to test the end-user launch experience on a Mac with Gatekeeper enabled before distributing.[1] Apple's notarization requirements include: all distributed executables have valid signatures, a Developer ID type certificate is used, Hardened Runtime is enabled, a secure timestamp is used, and the release package does not keep a `com.apple.security.get-task-allow` entitlement with the value `true`.[2] Hardened Runtime exception entitlements should be configured on the principle of least necessity.[3]

| Release gate | Current status | Acceptable completion criterion |
|---|---|---|
| Developer ID Application certificate and team configuration | Not configured | Use the Developer ID Application identity only in the release configuration; ad hoc, development certificates, or Mac Distribution must not be substituted. |
| Hardened Runtime | Not configured | Enabled for the release app target; add minimal exception entitlements only when a feature truly needs them. |
| Apple Events permission | Usage text declared | Keep `NSAppleEventsUsageDescription`, and verify first-time authorization, denial, and copy fallback for Terminal/iTerm on a clean account. |
| Release package entitlements | Not audited | After export, confirm there is no `get-task-allow=true`, and save the output of `codesign -d --entitlements :-`. |
| Notarization and ticket | Not run | Upload with `notarytool`, wait for acceptance, staple the ticket, and keep the request ID and log. |
| Gatekeeper cold start | Not run | On a Gatekeeper-enabled Mac that took no part in the build, verify launching the final package downloaded with the quarantine attribute. |
| Version number and update strategy | Not fixed | Fix `CFBundleShortVersionString`/`CFBundleVersion`, and decide the private beta's rollback, expiry, and update notification mechanisms. |

## 3. iCloud sync: design gate complete, feature not implemented

iCloud is not a feature that can be faked with a local switch. It still needs a valid Apple Developer team, a CloudKit container and capability configuration, confirmed sync scope and conflict rules, a migration strategy, and real verification on at least two devices. The current version's explicit local configuration and design document only prevent a future entitlement or container configuration from turning sync on by accident; they do not mean iCloud is implemented.

| Item | Current conclusion |
|---|---|
| Local default behavior | Verified as `cloudKitDatabase: .none` |
| iCloud design and acceptance conditions | Recorded in `docs/icloud-sync-design-gate.md` |
| Apple Developer team and CloudKit container | External prerequisites, currently not available |
| Multi-device conflict, migration, and data boundary verification | Not started; local tests must not be used as a substitute |

## 4. Data recovery and upgrade verification

The backup schema version is `1` and uses optional fields to stay compatible with old JSON. Unit tests confirm that old schema 1 JSON decodes when the newer trust fields are missing, and that the source is derived safely from the local executable path. The old `iconURLString` is not rendered, exported, or restored; API keys never enter a JSON backup.

When the default SwiftData store cannot be created, the app no longer deletes or overwrites the original store; it opens an isolated recovery library and asks the user to choose a JSON backup to import deliberately. Automated tests already cover importing old schema 1 JSON into the recovery library, saving, and reopening, and the recovery page offering the import entry.

| Recovery scenario | Covered automatically | Still needs manual — but only one-time — verification on a real system before release |
|---|---|---|
| Schema 1 JSON missing the newer trust fields | Yes | No |
| Remote avatar URL in old JSON | Yes | No |
| API key excluded on export | Yes | No |
| Persisting after an import merge and reading after restart | Yes | No |
| Showing the safe recovery entry when the default store cannot be opened | Yes (controlled forced recovery) | No |
| Upgrading an existing SwiftData store to the new version | No | Yes |
| Data integrity and manual recovery with a really corrupted or unmigratable store | No | Yes |

## 5. Recommended controlled private beta release process

The release owner should first run `./scripts/verify-macos.sh` on a clean working tree and archive `.verification/<timestamp>/summary.md`, the full logs, the `.xcresult`, and the UI attachments. Then archive with the **Release** configuration, sign with the Developer ID Application certificate, and enable Hardened Runtime. The archived app must go through the signature and entitlement review before being packaged as one of DMG, PKG, or ZIP; once the packaging format is decided, it should be the fixed channel for later betas, for reproducibility and rollback.

```bash
codesign --verify --deep --strict --verbose=4 "TermiPad.app"
codesign -dvvv "TermiPad.app"
codesign -d --entitlements :- "TermiPad.app"
spctl -a -vvv --type execute "TermiPad.app"
```

Then go through the Developer ID distribution flow in Xcode Organizer, or upload for notarization with `xcrun notarytool`. Apple no longer accepts notarization uploads from `altool` or Xcode 13 and earlier; use `notarytool` or Xcode 14 and later.[2] After notarization succeeds, staple the ticket to the final artifact and test with the quarantine attribute present. Apple explains that the ticket tells Gatekeeper the software has been notarized; the notary service also reviews signing problems and returns a log.[2]

## 6. Private beta release conclusion

**P0 is complete in code and real macOS verification. The account-independent local capabilities of P1 are also complete. TermiPad Mendocino's P2-A project discovery, P2-B controlled install review, P2-C read-only environment report, and the T0/T1/T2 restricted tasks and local MCP collaboration have all completed real macOS verification.** This includes the safe review inbox, conservative discovery, manual management, command templates, terminal launch / copy fallback, trust sources, backup / isolated recovery, favorites / recents, diagnostics, off-by-default update checks, local icons, the tool health check, per-tool working directories, off-by-default public project discovery, statically reviewed Homebrew install plans, the manually triggered local version environment report, and a local stdio MCP server that can only propose tasks for review or read minimal status.

**External distribution is not cleared for now.** This is not because the engineering code is unfinished, but because Developer ID, Hardened Runtime, notarization, Gatekeeper cold start, and real old-store upgrade verification are not yet available or not yet run. iCloud sync likewise remains a real external gate of Apple Developer / CloudKit / two devices; it must not be described as implemented just because a design document or a local disabling configuration exists. What P2-B/P2-C have implemented is only controlled install review and the read-only environment report; automatic install, npm/pip/Cargo installs, third-party taps/casks, upgrade, uninstall, dependency solving, and conflict arbitration are all outside the current product commitment.

## References

[1]: https://help.apple.com/xcode/mac/current/en.lproj/dev033e997ca.html "Apple: Distribute outside the Mac App Store (macOS)"
[2]: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution "Apple: Notarizing macOS software before distribution"
[3]: https://developer.apple.com/documentation/security/hardened-runtime "Apple: Hardened Runtime"
