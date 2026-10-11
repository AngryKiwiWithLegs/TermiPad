# Launchpad: plan for a standalone macOS app launcher project based on the TermiPad architecture

**Status:** Product incubation and architecture decision draft. This document does not change TermiPad, and does not create the Launchpad repository, copy user data, scan apps, or launch any app.

**Clarification:** Launchpad is a **new, standalone native macOS project**. It draws on and selectively reuses TermiPad's verified workspace, icons, local persistence, and automated verification methods; it does not modify macOS system features and is not a new page or feature switch in TermiPad.

---

## 1. Recommended conclusion

> **Do it this way.** Set Launchpad up as a sibling project of TermiPad rather than layering "graphical app launcher" business onto TermiPad. The two projects can share the native workspace experience and verification methods, but must have separate product names, bundle IDs, local data containers, diagnostic packages, test targets, and release cadences.

TermiPad's core is user-confirmed interactive CLI tools with their controlled launching, task review, and local MCP boundary. An app launcher's core is the graphical app catalog, icons, personal groups, search, favorites, and launch on user click. If the two are mixed in the same data model and navigation, TermiPad's "fixed command + terminal handoff" risk notes pollute the lightweight app launch experience; conversely, Launchpad's large icon catalog dilutes TermiPad's task review and security state. So **shared architecture, separate products** is the most robust design.

| Decision | Recommendation | Reason |
|---|---|---|
| Project relationship | Create a new standalone private repository instead of continuing to change TermiPad. | Data, tests, releases, the user's mental model, and the security surface can evolve independently. |
| Initial tech stack | macOS 14+, Swift 5.9, SwiftUI, SwiftData, AppKit, XcodeGen, XCTest/XCUITest. | Directly inherits the build and test methods already verified on a real Apple Silicon Mac. |
| Project name | The product is provisionally called **Launchpad**; for the code repository, start with a working name that is not confused with the system name, such as `LaunchDeck`. | "Launchpad" is very close to the name of Apple's historical feature; a name and trademark check should be done before a public release. This is a product risk note, not legal advice. |
| Initial scope | Local app catalog, launch on user click, icon grid, search, favorites, recents, manual grouping, Light/Dark/System appearance, Chinese/English. | Cover the most essential personal launch experience of the old Launchpad first. |
| Explicit non-goals | No whole-disk scan, no file browsing, no shell execution, no CLI commands, no MCP/phone/Telegram/network, no auto-launch. | Keeps a lightweight, explainable, revocable local launcher. |

---

## 2. Launchpad MVP: what to do and what not to do

### 2.1 L1 minimal product experience

On first run Launchpad should present a workspace that follows native macOS conventions: "All Apps, Favorites, Recent, Groups" on the left, search, display mode, and organizing entry at the top, and a responsive icon grid as the main content. It may visually recall the browsability of the traditional Launchpad, but it does not imitate an iPad body, the Dock, a status bar, or global gestures.

The sources of the app catalog should be clear and controllable. For the first version, start with two standard local directories: `/Applications` and the user's own Applications directory; the user can turn either off in Settings and can add a `.app` manually through the system file chooser. Refreshing must be an explicit user click, with no continuous background scanning. For each displayable item, read only the display name, bundle ID, local icon, app URL, and local existence state — never app file contents, user documents, window content, the keychain, command-line arguments, or usage records.

When the user clicks an icon, Launchpad opens the app through `NSWorkspace`'s official app launch API rather than a shell, AppleScript, or simulated keyboard input. `NSWorkspace` is the workspace interface provided by AppKit; it supports launching an app by URL and observing workspace state.[1] Every launch must be a direct user click; there is no batch launching, rule triggering, background queue, shortcut automation, or remote invocation entry.

| L1 capability | Behavior contract | User experience |
|---|---|---|
| Standard directory collection | Reads the `.app` entries in the controlled directories only when the user clicks "Refresh App Catalog". | Like the "all apps" entry of the traditional Launchpad, but without a hidden whole-disk scan. |
| Manual add | Only the user can pick a single `.app` through `NSOpenPanel`. | Supports personal apps kept in non-standard locations. |
| Local icons | Uses the local icon returned by the app bundle or `NSWorkspace`, and allows a local custom icon from the user. | Icons match the real apps and do not depend on online avatars or AI inference. |
| Favorites, recents, groups | Stores only the display order and minimal launch time on the user's Mac. | Brings back the everyday usability of the old Launchpad. |
| Search and keyboard navigation | Filters locally within the current catalog; supports Tab / arrow keys / Return. | No need to remember an app's full name or path. |
| Launch status | Shows only minimal results such as "launched / app does not exist / needs to be collected again". | Keeps feedback clear without peeking inside apps. |

### 2.2 Permanent boundaries

| Non-goal | Why not |
|---|---|
| Modifying the macOS Launchpad, Spotlight, the Dock, the system database, global hotkeys, or trackpad gestures. | The new project is a standalone app; it does not replace system components and does not depend on non-public system internals. |
| Recursively scanning Home, the Desktop, Documents, external disks, network volumes, or cloud drives. | This would extend the launcher into a file browser and markedly widen the privacy surface. |
| Showing or launching system commands, daemons, package managers, scripts, installers, or Terminal. | Launchpad's objects are graphical `.app`s; CLI business stays in TermiPad. |
| Auto-completing app information/icons with AI, remote metadata, or web pages. | The catalog and icons must come from the local bundles on the user's Mac or the user's explicit choice. |
| Launching apps through MCP, phone, web, Telegram, HTTP, WebSocket, notifications, or scheduled tasks. | Every launch stays an explicit click by the user in a window on this Mac. |
| Reading app content, process output, window titles, documents, browser history, or communication data. | Launchpad only manages "launchable app cards" and does not observe what the user does inside apps. |

---

## 3. What to reuse from TermiPad and what must be discarded

### 3.1 High-value reusable layers

TermiPad is not a template to "fork wholesale and rename"; it is a native engineering skeleton that has been verified on real macOS. Launchpad should start by **copying a vetted foundation layer** and rebuild the app launching business on a new data model.

| Asset group | Recommended handling | Reason and migration approach |
|---|---|---|
| `project.yml` | **Copy and rename.** | Keep macOS 14+, Swift, XcodeGen, the test targets, and local ad hoc test signing; replace all targets, the product name, and the bundle ID. |
| `AppPresentation.swift` | **Copy and generalize.** | Directly carries over Chinese/English, Light/Dark/System appearance, and centralized short copy; delete TermiPad-specific keys and security notices. |
| `SoftMacTheme.swift`, `TermiPadWorkspaceStyle.swift`, `WindowPlacementCoordinator.swift` | **Copy and rename.** | Reuse the native workspace spacing, panel layering, window sizes, and adaptation approach; do not copy "iPad device frame" style visuals. |
| The navigation shell, toolbar, search, grid, empty state, hover, and sheet patterns of `LaunchpadView.swift` | **Split up, then reuse.** | Extract generic `WorkspaceShell`, `IconGrid`, `EmptyState`, and `AppearanceControl`; do not bring in the CLI tool scanning/editing/launch code. |
| `ToolIconView.swift`, `ToolIconStore.swift` | **Reuse the mechanism, not the catalog.** | The controlled local PNG, manual override, stable fallback, and rendering layer are worth keeping; app cards should default to the real bundle icon and not use the CLI tools' semantic symbol table. |
| The `launchApp`, window restoration, and attachment export helper methods of `TermiPadUITests.swift` | **Copy and change the bundle ID / identifiers.** | This is the key asset for "sparing the user manual clicks": real launch, waiting, clicking, asserting, screenshots, and UI hierarchy diagnostics. |
| `verify-macos.sh` | **Copy as a Launchpad version and rewrite the guards.** | Keep the one-command loop; remove the T0/T1/T2/MCP-specific guards and add Launchpad guards such as "no shell / no network / no remote launching". |

### 3.2 Logic that must stay in TermiPad

The following files or responsibilities should not enter the new project as is, because they are bound to the CLI, the terminal, AI/network enrichment, restricted tasks, or the MCP design.

| TermiPad layer | How Launchpad handles it | Notes |
|---|---|---|
| `TerminalTool.swift`, `CandidateTool`, `ToolScanner.swift` | Create a new `LaunchAppEntry`; do not inherit. | The existing models contain the executable path, command template, variables, tool source, and CLI categories. |
| `TerminalLauncher.swift`, `CommandTemplate.swift`, `ToolLaunchContext.swift` | Not copied at all. | Launchpad only opens `.app` bundles; it builds no commands and does not call Terminal/iTerm/Warp. |
| `TaskIntent*`, `TaskExecutionService.swift`, `TaskMCP*`, `MCPStdIORuntime.swift` | Not copied at all. | These are TermiPad's own task and local MCP security chain. |
| `AIService.swift`, `GitHubService.swift`, `Discovery*`, `UpdateCheckService.swift` | Not copied in the initial version. | The Launchpad MVP needs no network, API key, remote discovery, or remote update feed. |
| `ControlledInstallPlan.swift`, `InstallEnvironmentView.swift` | Not copied at all. | A graphical app launcher takes on no installation, package management, or environment review duties. |
| TermiPad's backup JSON format and restore model | Not directly compatible; a Launchpad-specific local export can be designed separately. | CLI commands, tool variables, or any TermiPad data should not be migrated into the new project. |

### 3.3 Data models newly created for Launchpad

The new project should define `LaunchAppEntry`, `LaunchGroup`, and `LaunchSource` in its own SwiftData container. The minimal record stores only the fields needed for display and launching; the diagnostic export contains no raw paths.

| Model field | Purpose | Restriction |
|---|---|---|
| `id` | Local opaque identifier. | Not uploaded. |
| `displayName`, `bundleIdentifier` | Title, deduplication, and search. | A local alias from the user is allowed; not used for network lookups. |
| `appURL` or a security-scoped bookmark | Locates a `.app` the user collected. | The raw URL is not written to diagnostics or remote interfaces. |
| `source` | `systemApplications`, `userApplications`, `userSelected`. | Only explains the source; it is not a security certification. |
| `isFavorite`, `isHidden`, `groupID`, `sortIndex` | Personal local organization. | Not shared and not synced automatically. |
| `lastLaunchedAt` | Ordering by recent use. | No usage duration, window content, or behavior trail is recorded. |
| `iconFilename` (only for custom icons) | Controlled local icon override. | Defaults to the real bundle icon; no network assets are downloaded. |

---

## 4. New repository, naming, and verification strategy

### 4.1 How to create the repository

The recommendation is to create a new **private** GitHub repository rather than forking TermiPad. A fork would bring the full commit history and TermiPad's MCP/task/CLI code into the new project, raising audit cost and blurring the product boundary. The new repository should be set up from a clean XcodeGen project, then selectively receive reviewed foundation files. The top of the README should state "standalone local graphical app launcher; contains no CLI terminal, MCP, remote control, or network service".

The product display name may provisionally be "Launchpad" during the internal prototype stage, but before any planned public distribution, domain, store listing, or trademark use, check the risk of confusion with the name of Apple's historical product and with similar software. This is a general product risk reminder and not legal advice; at that point an intellectual property professional familiar with the target regions should review it.

| Project identity item | TermiPad | Suggestion for the new project |
|---|---|---|
| Repository | `AngryKiwiWithLegs/TermiPad` | A new private `AngryKiwiWithLegs/LaunchDeck` (working name, adjustable after confirmation). |
| Project name | `TermiPad` | `LaunchDeck`, or a separate name once the final naming is confirmed. |
| Bundle ID | `com.termipad.app` | A brand-new ID, for example `com.angrykiwi.launchdeck`; the final value should be decided consistently by the repository/release owner. |
| Local data | TermiPad's SwiftData container. | A new container and a separate Application Support directory; TermiPad data is neither read nor migrated. |
| Icon directory | TermiPad's controlled tool icon directory. | A separate icon directory that caches only override images for the app cards the user selected. |
| Diagnostic package | TermiPad's fixed privacy categories. | New Launchpad event categories; raw app paths and user data must not be output. |

### 4.2 How the single consolidated verification is carried over

Launchpad should have `scripts/verify-macos.sh` from day one, not added after the UI is done. It should check Xcode/XcodeGen, script syntax, Swift static boundaries, unit tests, project generation, the macOS build, and UI smoke tests, and save the logs, `summary.md`, and `.xcresult` attachments in one timestamped directory.

| Launchpad verification group | Assertions to cover |
|---|---|
| Static boundaries | Launchpad does not reference `Process`, `NSTask`, `NSAppleScript`, `URLSession`, MCP stdio, WebSocket, an HTTP listener, or shell strings. |
| Unit tests | Bundle deduplication, user groups, favorites/hiding, sorting, standard directory filtering, bookmark recovery for manual selections, missing-app hints. |
| UI smoke | First-run onboarding, all apps, search, favorites, empty state, groups, settings, Chinese/English, Light/Dark/System appearance, and the launch confirmation UI. |
| Launch isolation | Use a separate in-memory container or test directory; never read the user's real app catalog or rewrite the user's actual favorites. |
| Failure attachments | Automatically export screenshots, the Accessibility/UI hierarchy, and the `.xcresult`; the user only needs to send the summary at the end. |

---

## 5. Recommended order and items to confirm

For now the recommendation is to enter only **Launchpad L0: standalone project design freeze**, not to create the repository immediately. L0's goal is to trade a few product decisions for stable implementation and verification later.

| Question you need to confirm | Suggested default | Effect on what follows |
|---|---|---|
| Use a new standalone project? | Yes, a sibling project of TermiPad. | Decides creating a new private repository and a new bundle ID. |
| Product/repository working name | Use `LaunchDeck` for the repository first; UI copy may provisionally use "Launchpad". | Avoids locking the name too early across the project, bundle ID, and public brand. |
| How apps are collected | Default: manual refresh of the standard directories + manual add by the user. | Balances the coverage of the traditional Launchpad with local privacy. |
| Allow automatic discovery? | Not automatically in the background; only a refresh the user clicks on this Mac. | Decides whether standard directory access and a refresh explanation are needed. |
| Share a screen with TermiPad tools? | No; the two apps run separately. | Keeps the two products' data and security models clear. |
| Next development action | After completing the L0 design, create the private repository and implement the L1 MVP. | Does not trigger iPhone, MCP, network, shell, or changes to the existing TermiPad. |

---

## References

[1]: https://developer.apple.com/documentation/appkit/nsworkspace "Apple Developer: NSWorkspace"
[2]: https://developer.apple.com/design/human-interface-guidelines/toolbars "Apple Human Interface Guidelines: Toolbars"
[3]: https://developer.apple.com/design/human-interface-guidelines/layout "Apple Human Interface Guidelines: Layout"
[4]: https://developer.apple.com/documentation/xcuiautomation/xcuiapplication "Apple Developer: XCUIApplication"
[5]: https://developer.apple.com/documentation/xctest "Apple Developer: XCTest"
