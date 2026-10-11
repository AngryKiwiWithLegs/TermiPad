# TermiPad launcher extension, native UI system, and automated verification: topic plan

**Status:** Research and product decision draft; the Launchpad extension is not implemented, and the existing T0/T1/T2 security boundaries are unchanged.

**Baseline:** TermiPad Mendocino; T2 has passed consolidated verification and the isolated OpenCode read-only walkthrough on the user's Apple Silicon Mac. This document does not reopen local MCP and introduces no mobile app, Telegram, PWA, network listening, or remote execution.

---

## 1. Summary of conclusions

> **It can be done, but there should be no attempt to "restore or tamper with the original macOS Launchpad".** The right product direction: beyond the existing "launcher for directly interactive CLI tools the user confirmed", TermiPad offers a separately enabled, separately named **Launch Deck**. In its own window it provides what the traditional Launchpad was good at — visual icon browsing, search, favorites, recents, and manual grouping — and calls macOS's official app launch API after the user clicks.

The official path in macOS Tahoe 26 is still Spotlight: users can start Spotlight with `Command-Space`, the menu bar icon, or a function key, then search for and open apps, files, and actions.[1] A third-party app cannot restore the old Launchpad's system database, Dock behavior, system gestures, or Apple's Spotlight app browsing UI; those experiences are owned by the operating system. What TermiPad can do is offer a standalone native app window that **does not replace the system but can become a personal preferred launch entry**.

This extension has real value, but it should be defined as the **L-series launcher workflow** and not mixed into TermiPad's core security responsibilities. It can serve the need "I want to launch my frequently used apps and reviewed CLI tools quickly from one comfortable icon space"; it must not turn into a whole-disk file browser, an automation platform, a system command center, or a remote control surface.

| Question | Topic conclusion |
|---|---|
| Can Apple's old Launchpad be restored? | **No, and it should not be attempted.** The system Launchpad, built-in Dock items, system database, gestures, and Spotlight cannot be changed. |
| Can a better icon launcher be built? | **Yes.** Build TermiPad's own native Launch Deck, using `NSWorkspace` app launching initiated by a user click. |
| Does the UI quality come from one "mystery module"? | **No.** It comes from the combination of auditable design constraints, native component choices, centralized copy, icon rules, accessibility identifiers, and repeated verification. |
| Can it be handed to others for reuse? | **Yes, but not by copying a single View.** Hand over the design rules, the related component group, the data model, the UI tests, and the verification script. |
| Why does it need so little manual clicking? | Because the project writes "what can be verified automatically" into repeatable scripts, and uses UI automation to actually launch the app, click controls, wait for state, assert results, and export screenshots and diagnostics. |

---

## 2. L series: product definition of TermiPad Launch Deck

### 2.1 Product positioning

**Launch Deck is TermiPad's optional local app launch layer; it is neither a stand-in for the system Launchpad nor a terminal.** In the same native macOS workspace it offers two explicit, visually distinguishable kinds of objects: reviewed CLI tool cards and graphical app cards the user chose to include. The former continue the existing TermiPad library boundary; the latter only launch app bundles and never generate, rewrite, or execute commands.

The recommendation is to make it a new top-level sidebar entry, for example "Launch Deck". Overriding the current "Library" home is not recommended, nor is using "Launchpad" as the product name, to avoid implying a replacement relationship with Apple's system feature.

### 2.2 What can be implemented

Apple's `NSWorkspace` is the official macOS workspace interface: it can launch an app by its URL and obtain running app state, app icons, and some workspace notifications.[2] Launch Deck can therefore offer the following capabilities in a controlled way.

| Feature | User value | Implementation boundary |
|---|---|---|
| Collecting apps from standard locations | Build personal launch cards from the common application directories. | Only check predefined application directories, or let the user explicitly pick a `.app` in a file chooser; no recursive whole-disk scan. |
| Native icons | Icons match the real app instead of being assigned ad hoc by AI. | Use the local icon provided by the bundle / `NSWorkspace`; no avatars, brand images, or network icons are downloaded. |
| Search, favorites, recents, manual grouping | Brings back the high-frequency browsing efficiency of the traditional Launchpad. | Data is stored only on this Mac; categories and ordering are controlled by the user, never changed by remote metadata or AI. |
| Launch on user click | Directly opens a graphical app the user has installed. | Only the user's explicit click may trigger `NSWorkspace.openApplication`; no shell, AppleScript, terminal handoff, or background queue. |
| Running state hint | Gives the card visible feedback when the app is "open". | Shows only local state at the bundle ID / display name level; no window content, files, command lines, or app data are collected. |
| Optional menu bar entry | Gives frequent users one way into Launch Deck. | Only shows/hides TermiPad's own window; it does not imitate the system menu bar or listen to the keyboard globally. |

### 2.3 Explicit non-goals

The following are vetoed for the L series and are not reopened for the sake of "being more like the old Launchpad".

| Non-goal | Reason |
|---|---|
| Modifying, reading, or restoring Apple's old Launchpad database and folders. | Unstable, non-public, likely to break with system upgrades, and outside TermiPad's authorization boundary. |
| Replacing Spotlight, or hijacking `Command-Space`, Dock items, or system gestures. | Conflicts with system-level navigation and needs unnecessary global permissions and always-on behavior. |
| Recursively browsing the user's Home, external disks, work folders, or network volumes. | Turns the launcher into a file browser and widens the privacy and security surface. |
| Scanning or showing system tools, background services, daemons, scripts, package managers, or installers. | Violates TermiPad's established scope of only user-facing, directly interactive tools. |
| Auto-launching, batch-launching, scheduled launching, or launching apps triggered by MCP / phone / network. | Breaks the control principle of "an explicit click by the user on this Mac". |
| Mixing graphical apps and CLI commands into actions that AI/MCP could rewrite. | AI, remote metadata, and MCP must never rewrite the user's fixed tool commands or launch targets. |

### 2.4 Suggested data model

To avoid polluting the existing `TerminalTool` model, add a separate, minimal persisted `LaunchDeckApp` record. It should record only the fields needed to restore the user interface.

| Field | Purpose | Privacy and security constraints |
|---|---|---|
| `id` | Local opaque primary key. | Not uploaded. |
| `bundleIdentifier` | Deduplication, and detecting whether the app still exists. | Not used for network lookups. |
| `displayName` | Card title. | Taken from the local bundle display name; a local alias from the user is allowed. |
| `bookmarkData` or a controlled URL reference | Keeps authorization for a non-standard app the user explicitly chose. | Store a security-scoped bookmark only when necessary; the raw path is not shown to MCP / mobile / diagnostics. |
| `sourceKind` | `standardDirectory` or `userSelected`. | Used to explain things in the UI; implies no trust promise. |
| `isFavorite`, `isHidden`, `groupID`, `lastLaunchedAt` | Local ordering and organization. | No app usage duration or window content is collected. |
| `iconFingerprint` (optional) | Decides whether the local icon cache needs refreshing. | Icons are cached only in a controlled local directory; no network. |

Do not copy the `.app`'s executable path, the full Info.plist, signing information, user files, or runtime output into the diagnostic package. If stronger source information is needed before release, design it separately, visible to the user and able to be turned off, rather than quietly widening collection.

---

## 3. Suggested phased implementation, L0–L3

> This plan recommends doing L0 and L1 first; L2/L3 are scheduled only after the first two phases get real usage feedback and it is confirmed again that the security surface does not widen.

| Phase | Scope | Acceptance criteria | Typical risks |
|---|---|---|---|
| **L0: design and security contract** | Data model, collection scope, explicit no-go areas, copy, and UI information architecture. | The plan passes review; no existing runtime code changes. | Writing a promise to replace the system Launchpad into the product by mistake. |
| **L1: local Launch Deck MVP** | User-initiated collection, lightweight discovery in standard directories, local icons, search/favorites/grouping, single-click launch, a native settings page. | Every launch is triggered by a user click; covered by unit tests and UI smoke tests. | Bundle changes, duplicate collection, window size adaptation. |
| **L2: reliability and discoverability** | Missing-app hints, icon refresh, running state, a menu bar "Show Deck" entry, keyboard shortcut hints. | Everything observed is minimal local state; no global keyboard listening. | Convenience evolving into always-on background automation. |
| **L3: cross-device product design (design only)** | Define the read-only catalog a future iPhone companion could see and the local approval boundary. | No network pairing is started and no paths/commands/output are transferred. | Connecting the launcher to remote control too early. |

**The recommendation is to approve only L0 for now.** The reason is not technical difficulty; the product center first needs to answer whether Launch Deck is "a personal app favorites entry" or part of "TermiPad's unified workspace" — the two differ in data boundaries, default entry, sidebar priority, and release narrative.

---

## 4. Why TermiPad's UI comes close to the native standard

### 4.1 Not a standalone magic module, but a set of reusable constraints

The quality of the current UI is not produced automatically by some closed component. It comes from a traceable engineering combination: system layouts from SwiftUI/AppKit carry the interaction, `AppPresentation.swift` centralizes language and appearance, and icons, tool cards, the sidebar, the toolbar, and empty states build the information hierarchy; stable accessibility identifiers and UI tests then keep the key paths continuously verifiable.

Apple's HIG explicitly recommends putting only high-frequency commands in the toolbar, grouping items logically, preferring system components and borderless system symbols, and always keeping an alternative entry to toolbar commands in the macOS menu bar.[3] Layout should adapt to window size, text length, and system appearance through SwiftUI or Auto Layout, and build hierarchy with clear grouping, whitespace, alignment, and progressive disclosure.[4]

| Design layer | Current TermiPad asset | Portable principle |
|---|---|---|
| Information architecture | Native sidebar entries: library, inbox, discovery, install & environment, task workbench, settings. | Divide stable workspaces first, then place concrete controls inside each workspace; do not wrap every feature in one big card. |
| System navigation | `NavigationSplitView`, the window title, `toolbar`, menu bar commands. | On macOS use sidebar + toolbar + menu commands; do not imitate an iPad body, status bar, or Home indicator. |
| Appearance and text | `AppLanguage`, `AppAppearance`, and `AppCopy` in `Sources/AppPresentation.swift`. | Centralize language, appearance, and short UI copy; do not scatter conditional strings inside every View. |
| Icon language | `Sources/ToolIconView.swift`, `Sources/ToolIconStore.swift`, and controlled local PNGs. | SF Symbols handle generic actions, and the local icon of the real tool/app handles recognition; no network avatars and no repeated decorative images. |
| Interaction rhythm | System controls, hover help, context menus, native sheets, segmented selection. | A small number of clear primary actions; important actions are left to the user's click; avoid oversized corner radii, excessive gradients, and custom imitation-mobile controls. |
| Local state | Immediate saving, visible status notes, hints on failure, recovery mode. | For what the user must know — "saved / closed / pending review" — give concise, persistent local feedback without adding a redundant global save button. |
| Accessibility | Semantic names and stable identifiers; avoid fragile assertions that depend on SwiftUI's merged hierarchy. | Put identifiers on stable accessible controls; UI tests verify the boundaries the user can actually see/operate, not the framework's internal structure. |

### 4.2 Code assets that can be handed over directly, not just screenshots

Other developers who want to reuse TermiPad's native experience should start from the asset groups below rather than copying one layout section of `LaunchpadView.swift`. The files depend on each other through the data model, copy, icon storage, and tests; copying a single View in isolation usually gives a result that "looks like the picture but is unstable".

| Handoff layer | Files or directories to hand over | Purpose | What cannot be copied as is |
|---|---|---|---|
| Visual foundation | `Sources/AppPresentation.swift` | Chinese/English, three appearance options, unified UI copy. | Specific product vocabulary and copy for sensitive operations. |
| Launcher UI | `Sources/LaunchpadView.swift` | How the sidebar, toolbar, search, icon wall, hover notes, and empty states are organized. | The existing CLI data model and launch logic. |
| Icon system | `Sources/ToolIconView.swift`, `Sources/ToolIconStore.swift` | Local icons first, controllable custom icons, fallback rules. | Must not be turned into an automatic downloader of remote avatars or AI-generated icons. |
| Status and security UI | `Sources/TaskPolicyWorkbenchView.swift` | How long-lived security state stays visible without creating noise. | The T0/T1/T2 policy content can be reused only under an equivalent security model. |
| Interaction tests | `UITests/TermiPadUITests/TermiPadUITests.swift` | Launch, first-run onboarding, sidebar, page visibility, failure screenshots, and lifecycle recovery. | Bundle ID, test environment switches, product-specific identifiers. |
| Consolidated verification | `scripts/verify-macos.sh` | One command covering syntax, guards, unit tests, build, UI tests, and `.xcresult` attachments. | The existing list of security keywords must be re-audited for the new product. |

### 4.3 The handoff package structure "copying" should use

The recommendation is to organize the current code into an **internal reuse package** in the future, rather than publicly copying all business source files now. The recommended handoff package has four parts: a design contract, a set of portable Views, a small design token / copy layer, and a UI automation skeleton.

```text
NativeWorkspaceKit/                 # future internal reuse package, not created yet
  DesignContract.md                 # platform, layout, color, motion, and accessibility rules
  Presentation/                     # conventions for appearance, language, copy, and symbol choice
  Components/                       # SidebarShell, WorkspaceToolbar, IconGrid, StatusRow
  Testing/                          # UI test helpers, attachment helpers, launch isolation
  Examples/                         # examples without user tools, commands, paths, credentials, or real data
```

This does not "turn the UI into a one-click generator". Code can reuse components, but it **cannot replace information architecture, product vocabulary, state machines, and security audits**. Anyone building a finance, healthcare, enterprise management, or remote control app must redefine the data and permission boundaries and cannot use TermiPad's views to imply they are equally safe.

---

## 5. Automated UI tests: how to spare the user repeated manual clicking

### 5.1 The actual mechanism in the current project

TermiPad does not have tests "look at a screenshot and guess". It uses Apple's `XCTest` and `XCUIAutomation` to launch the app, pass an isolated environment, find accessible elements, click the sidebar and first-run onboarding controls, wait for asynchronous state, and assert page boundaries, then terminates the app at the end and exports diagnostic attachments. Apple defines `XCUIApplication` as the proxy for launching, monitoring, and terminating the app under test, with APIs for launch arguments, launch environment, state waiting, activation, termination, and accessibility audits.[5] `XCTest` explicitly supports reproducing interaction sequences with XCUIAutomation and saving attachments as failure diagnostics.[6]

The structure of the current `UITests/TermiPadUITests/TermiPadUITests.swift` can be summarized as:

1. Each scenario launches the real macOS app with `XCUIApplication(bundleIdentifier: "com.termipad.app")`.
2. `-ApplePersistenceIgnoreState`, `TERMIPAD_UI_TEST_MODE`, and specific environment variables give a repeatable first-run, settings, or recovery mode without touching the user's real library.
3. If macOS restores the menu bar but not the window, the test creates an accessible main window through **New Window** in the app menu; this handles window restoration differences on real Macs.
4. Controls are found by stable accessibility identifiers, with `waitForExistence` before clicking, reducing false failures from "the UI has not appeared yet".
5. For each workspace it checks both "key controls that should appear" and "out-of-bounds controls that should not". For example, the task workbench must have the local MCP permission note and must not show the tool discovery button.
6. After a test ends, a screenshot and the text hierarchy are saved; the script exports the attachments from the `.xcresult`, so a problem can be located rather than yielding only a red failure line.

### 5.2 Why one command is more reliable than repeated manual testing

`scripts/verify-macos.sh` is the current "stand-in for local CI". It does not just run one build; in a fixed order it runs the toolchain check, shell syntax check, Swift source security guards, Swift Package manifest check, unit tests, XcodeGen project generation, the native build, UI Runner signature verification, and UI smoke tests; a failure at any step is written to the logs and `summary.md` in the same timestamped directory. On a UI failure it also exports text, screenshot, and video attachments from the `.xcresult` automatically.

| Verification layer | Problems verified automatically | What manual verification still cannot be replaced for |
|---|---|---|
| Static security guards | Forbids regressions such as network, arbitrary shell, PTY, output pipes, and direct SwiftData contention. | Whether a new feature's product intent and security model are sound. |
| Unit tests | Data models, policy state machine, rejection paths, the fixed task catalog, the MCP protocol. | Whether real users understand the risk notices. |
| Build / signing | Xcode/Swift version compatibility, project generation, test Runner integrity. | Developer ID, notarization, and Gatekeeper for external distribution. |
| UI smoke | Launch, window restoration, first-run onboarding, click navigation, page boundaries, accessible controls. | Subtle visual rhythm, long-term usage experience, a full assistive technology audit. |
| Failure attachments | Screenshots, UI hierarchy, and logs, for minimal reproduction. | Permissions unique to the user's machine, third-party apps, hardware, and network environment. |

### 5.3 A copyable test loop template

Other developers who want less "please click once more and take another screenshot" friction should build the following loop:

```text
Explicit acceptance statements
    ↓
Stable accessibility identifiers
    ↓
Unit tests (policy and data) + UI tests (real click paths)
    ↓
One consolidated verification command
    ↓
On failure, automatically produce summary + logs + xcresult attachments
    ↓
Ask the user only for the shortest failure summary; the developer makes the minimal fix
```

The key here is not "automatic clicking" itself but **encoding the observable product contract as tests**. If the product only says "make the UI look more premium", no automation can judge it reliably; if it says "the boundary notice must appear on first launch; the workbench must have the local switch; the remote terminal entry must not appear", the tests can give a stable pass or fail on the real operating system.

### 5.4 Why the experience differs so much between projects or collaborations

The capability of other tools or other collaboration setups cannot be judged from a single conversation; the differences more commonly come from whether the project has a runnable build, a UI test target, stable identifiers, the ability to build on the real target OS, a consolidated script, and requirements stated as acceptance conditions.

TermiPad can compress the user's repeated work to "pull, run one consolidated script, and return the summary at the end" because it invested in test infrastructure, failure attachments, and security guards up front. This does not mean every change needs no human confirmation: anything involving authorization, real accounts, external distribution, remote connections, payments, or real task execution must still be seen and explicitly decided by the user.

---

## 6. Suggested order of follow-up decisions

Before moving on to the native iPhone companion, discuss in the order below rather than implementing everything at once.

| Decision point | Recommended choice | What needs your confirmation |
|---|---|---|
| Whether to build Launch Deck | Do the **L0 design**, then decide whether to enter the L1 MVP. | Do you want it to hold only graphical apps, or share the screen with the existing CLI tools in clearly separated sections? |
| Default collection scope | Start with "manual add by the user + optional lightweight discovery in standard application directories". | Whether listing the `.app`s in `/Applications` and the user's Applications directory is allowed still needs your confirmation. |
| Shortcut entry | Start with the sidebar and an optional menu bar "Show Launch Deck". | Do not take over `Command-Space` or the old Launchpad gesture for now. |
| UI reuse | Produce the internal `NativeWorkspaceKit` extraction plan first. | Does the reuse package need to be delivered to a specific developer/team? |
| iPhone companion | Keep it in the next phase. | Do the M0/M1 information architecture and pairing security design after the L0 conclusion. |

---

## References

[1]: https://support.apple.com/en-gb/guide/mac-help/mchlp1008/mac "Apple Support: Search for anything with Spotlight on Mac"
[2]: https://developer.apple.com/documentation/appkit/nsworkspace "Apple Developer: NSWorkspace"
[3]: https://developer.apple.com/design/human-interface-guidelines/toolbars "Apple Human Interface Guidelines: Toolbars"
[4]: https://developer.apple.com/design/human-interface-guidelines/layout "Apple Human Interface Guidelines: Layout"
[5]: https://developer.apple.com/documentation/xcuiautomation/xcuiapplication "Apple Developer: XCUIApplication"
[6]: https://developer.apple.com/documentation/xctest "Apple Developer: XCTest"
