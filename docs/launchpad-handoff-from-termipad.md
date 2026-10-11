# TermiPad → Launchpad: standalone project handoff package

**Status:** Ready; any later developer can use it to take over Launchpad's L0/L1. This document does not authorize copying TermiPad's CLI, task execution, MCP, or network features.

**Handoff goal:** Building on TermiPad Mendocino's verified native macOS engineering experience, incubate a new, standalone launcher for local graphical apps, **Launchpad**. Launchpad does not modify macOS and is not an add-on page of TermiPad; it has a new repository, bundle ID, SwiftData container, icon directory, test targets, verification script, and release cadence.

---

## 1. TermiPad frozen baseline

| Item | Current facts |
|---|---|
| Product | TermiPad Mendocino, a native macOS Swift/SwiftUI app. |
| Verified code baseline | `0cdbc90`; the later `d663b08`, `34fdb2f`, `49d7029`, and `8e2013b` are documentation/planning commits. |
| Latest real-Mac verification | 2026-08-27, result directory `20260827-115315`, `TEST EXECUTE SUCCEEDED` and `[PASS] ui-smoke-test`. |
| Real verification environment | Apple Silicon Mac; Xcode 26.6, Swift 6.3.3, XcodeGen 2.46.0. |
| Current T2 status | The isolated read-only walkthrough with OpenCode 1.14.33 is complete, and local MCP and the temporary service configuration are turned off. |
| External distribution | Not done. No Developer ID, notarization, Gatekeeper cold start, or real old-store upgrade verification; it must not be described as released. |
| Mobile | Not implemented. The native iPhone companion, PWA, Telegram, and network bridging must not be brought into the Launchpad MVP. |

TermiPad itself should keep its current working boundary: interactive CLI tools confirmed by the user; the T0/T1/T2 task capabilities stay local to the same Mac, off by default, and reviewed. **Do not turn TermiPad's stable baseline into a graphical app launcher for Launchpad's sake.**

---

## 2. Assets that may be reused selectively

| Asset | Recommended handoff | Reuse value | What to adjust in Launchpad |
|---|---|---|---|
| `project.yml` | Rewrite along the same structure after creating the new project. | macOS 14+, Swift 5.9, XcodeGen, test targets, and local ad hoc test signing are verified. | Replace the product name, target names, bundle ID, test host, and Info.plist text completely. |
| `AppPresentation.swift` | Copy the architecture, rewrite the Launchpad copy. | The centralized pattern for Chinese/English and System/Light/Dark appearance. | Remove all CLI, network, secret, and terminal copy. |
| `SoftMacTheme.swift`, `TermiPadWorkspaceStyle.swift`, `WindowPlacementCoordinator.swift` | Copy and rename. | Native workspace layering, soft macOS visuals, window/multi-display adaptation. | Adjust Launchpad's own initial window size and app grid density. |
| The shell of `LaunchpadView.swift` | Split it up, then reuse. | The `NavigationSplitView`, toolbar, search state, icon grid, empty state, sheet, menu, and first-run onboarding patterns. | The CLI scanning, candidate acceptance, AI/GitHub enrichment, terminal launch, and command editing parts must not be copied. |
| `ToolIconView.swift`, `ToolIconStore.swift` | Keep the local storage/rendering ideas, change to app icon types. | User local PNG override, controlled cache, display fallback, and the no-network-icons principle. | The default icon should come from the real `.app` bundle / `NSWorkspace`, not the CLI tool symbol catalog. |
| The factory pattern of `TermiPadDataStore.swift` | Copy the design, rebuild the schema. | Explicit local container, recovery container, and the CloudKit-disabled principle. | Use the new `LaunchAppEntry`/`LaunchGroup` models and a separate storage location. |
| Helper methods of `UITests/TermiPadUITests/TermiPadUITests.swift` | Copy the test foundation, rewrite every test case. | Real app launch, window restoration, waiting for accessible elements, failure screenshots, and text hierarchy attachments. | New bundle ID, accessibility identifiers, app collection data, and launch assertions. |
| `scripts/verify-macos.sh` | Copy the workflow, rewrite it line by line. | One consolidated verification, timestamped result directory, logs, summary, xcresult, and UI attachments. | Redo the static guards, explicitly forbidding shell/MCP/network/remote launching. |

---

## 3. Modules that must not be copied

| Module/type | Why it cannot be brought into Launchpad |
|---|---|
| `TerminalTool`, `CandidateTool`, `ToolScanner`, `CommandTemplate`, `ToolLaunchContext` | They belong to the CLI, PATH scanning, command template, and variable input model and have nothing to do with a `.app` launcher. |
| `TerminalLauncher`, `TermiPadCommands`, `AppActions` | They involve Terminal/iTerm/Warp, Apple Events, command copying, and terminal handoff; Launchpad must not use them. |
| `TaskIntent`, `TaskIntentPolicy`, `TaskExecutionService`, `TaskPolicyWorkbenchView` | They belong to the restricted local task execution chain; the Launchpad MVP creates no tasks and runs no processes. |
| `MCPStdIORuntime`, `TaskMCPBridge`, `TaskMCPSettings` | They belong to TermiPad's T2 local MCP; Launchpad opens no MCP, stdio, IPC, or external invocation. |
| `AIService`, `GitHubService`, `Discovery*`, `UpdateCheckService` | The Launchpad MVP has no network, uses no API key, and does no remote metadata enrichment or remote update checks. |
| `ControlledInstallPlan`, `InstallEnvironmentView`, Homebrew/Cargo/npm related logic | A graphical app launcher is not responsible for installing, package management, or environment reports. |
| TermiPad backups, user tools, icons, variables, diagnostic events, or any SwiftData store | Launchpad must have a brand-new local data container; importing, migrating, or reading TermiPad user data is strictly forbidden. |

---

## 4. Launchpad L0 product contract

What Launchpad's L0/L1 must solve is "browse local graphical apps in a native, personally organizable icon workspace, and open them by a user click". It is not a system replacement for the old macOS Launchpad, does not manage the system Dock/Spotlight/gestures, and is not a file browser or an automation tool.

| Allowed L1 capability | Behavioral constraint |
|---|---|
| Local `.app` catalog | Only a manual refresh by the user of the standard Applications directories, or the user manually picking a single `.app` through the system file chooser. No recursive whole-disk scan. |
| Local icon and display name | Get the real local icon and display name from the bundle / `NSWorkspace`; the user may override them locally; no network icons are downloaded. |
| Search, favorites, recents, grouping, hiding, sorting | Store only the user's minimal local display preferences and the last launch time. |
| Launch on user click | Use the official AppKit app launch API only after the user explicitly clicks a card; no shell, AppleScript, or automation scripts. |
| Minimal run feedback | Show only local results such as "launched, not found, needs to be collected again"; do not read window content, documents, process output, or usage history. |

| Permanently forbidden capability | Notes |
|---|---|
| Shell, `Process`, `NSTask`, Terminal, AppleScript | Launchpad runs no commands and does not imitate terminal operations. |
| HTTP, WebSocket, `URLSession`, network listeners, MCP, stdio, CFMessagePort | There is no network or remote control surface. |
| Phone, PWA, Telegram, notification triggers, scheduled tasks, batch/background auto-launch | Every launch stays a single click by the user on this Mac. |
| File browsing, whole-disk scanning, reading app content, collecting windows/documents/output | Only the `.app` cards the user selected are managed. |
| Any data exchange with TermiPad | The two projects run, persist, back up, and diagnose independently. |

---

## 5. Takeover rules: how to avoid repeated manual verification

Every meaningful change must first complete, in the repository, the static audit, minimal unit test updates, XcodeGen project generation, and commit and push, and then request **only one** consolidated verification on the user's Mac. The user's single standard command should be run from the new project's root:

```bash
cd ~/Launchpad && git pull --ff-only origin master && ./scripts/verify-macos.sh
```

Later developers must ask the user for the pass/fail summary at the end of `summary.md`, rather than having the user click through things one by one, paste full logs, or try unverified ad hoc commands. If the UI fails, first use the `.xcresult`, screenshots, and accessibility/UI tree attachments exported by the verification script to locate the shared root cause, then make the minimal fix. Do not guess the implementation state from one screenshot, and do not widen the product scope because of one test failure.

| Verification layer | Assertions Launchpad should have |
|---|---|
| Static guards | The source must not use a shell, processes, Terminal/AppleScript, MCP, network clients/listeners, or remote launching. |
| Unit tests | App entry deduplication, standard directory filtering, user groups, favorites/hiding, sorting, missing apps, and local bookmark recovery. |
| UI smoke | First-run onboarding, window restoration, empty catalog state, search, favorites, settings, Chinese/English, the three appearance options, and confirmation of launch on user click. |
| Failure attachments | Every failure automatically saves the summary, logs, xcresult, screenshots, and UI hierarchy, without relying on the user to describe visual details. |

---

## 6. Recommended order of the first Launchpad commits

1. Set up a brand-new private repository and an empty XcodeGen macOS project; create a new bundle ID, local container, and test targets.
2. Port and rename the presentation layer, window style, empty state / sidebar / toolbar frame, icon cache, and UI test helper methods.
3. Write `LaunchAppEntry`, `LaunchGroup`, `LaunchSource`, and an explicit local privacy contract first, without implementing directory scanning.
4. Write the forbidden items into the first version of `verify-macos.sh`, so TermiPad's CLI/MCP/network source files cannot be brought in by mistake later.
5. Only after the structure verification passes, implement a proof of concept that adds a `.app` manually; only then start the single consolidated verification on a real Mac.

This handoff is enough for a developer familiar with TermiPad to move continuously, and enough for a newcomer or a new collaboration session to take over without reading the user's private data. Any capability beyond L1 must update the product contract and static guards first, and only then write runtime code.
