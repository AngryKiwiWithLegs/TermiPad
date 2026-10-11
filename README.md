# TermiPad

**TermiPad** is a native macOS launcher for terminal tools: it organizes the CLI tools you installed yourself and use interactively into a searchable, categorized library you can launch with one click.

> This repository is a private development build. The project is still being polished ahead of a public release; do not write API keys into the source or commit them to the repository.

## What works today

| Capability | Current behavior |
|---|---|
| Candidate discovery | Scans `$PATH` and common third-party install directories; new commands go to the **Review Inbox** first and never pollute the tool wall automatically. |
| Manual curation | Accept, ignore, or restore candidates; add tools manually, and edit, hide, restore, or delete accepted tools. |
| Frequent tools | Favorite a tool from its card's context menu; the left sidebar offers "Favorites" and "Recent" (sorted by last successful launch), both stored only on this Mac. |
| Quick access | The menu bar status item and the "Tools" menu open the library, Favorites, Recent, discovery, and manual add; `⌘1`, `⌘2`, `⌘3`, `⇧⌘D`, and `⇧⌘N` are supported. |
| Project Discovery Preview | Off by default; only when the user explicitly enables it and refreshes manually does it read a fixed public GitHub CLI repository query, using locally explainable ranking and an ETag cache. It is not an official GitHub trending list or a security rating, and it never installs software, generates commands, adds projects automatically, or uploads local tool data. |
| Update checks | Off by default; reads the configured HTTPS JSON version feed only when the user triggers it manually, and never downloads, installs, or executes an update. |
| iCloud sync | Explicitly disabled by default. It will be implemented only after an Apple Developer team, a CloudKit container, a conflict policy, and two-device verification are in place; see [`docs/icloud-sync-design-gate.md`](docs/icloud-sync-design-gate.md). |
| Command templates | Supports `{{variable_name}}` placeholders; on first launch it asks for the variables, shows a command preview, and saves the defaults on this Mac. |
| Working directory | Choose a local working directory per tool; at launch the command is only wrapped in a shell-escaped `cd --` prefix, and if the directory is gone you are taken straight to editing to fix it, with no probing command run. |
| Terminal launching | Choose Terminal.app, iTerm, Warp, or "Copy Command Only" in Settings. Warp uses the conservative approach of opening the app and copying the command. |
| Tool health | For the recorded absolute executable path, only existence and execute permission are checked; if the path is no longer valid, launching is blocked and an edit-to-fix entry is offered directly, with no check command run. |
| Enrichment | Optional GitHub README lookup and AI summarization; network enrichment is off by default, and on failure the local command and manual editing remain available. The AI API key is stored only in the macOS Keychain. |
| Icons | By default uses locally built-in, differentiated semantic icons with a stable gradient fallback; you can pick a local image as a custom icon. The chosen image is copied into a controlled local PNG directory; GitHub owner avatars are never downloaded or shown. |
| Local storage | Tools, candidates, categories, hidden state, command templates, and variable values are stored in a local SwiftData container. |

## Running locally

### Prerequisites

- macOS 14 or later.
- Xcode 15 or later.
- Use **macOS / My Mac** as the run destination; do not choose an iPhone or iPad simulator.

### Recommended: generate the Xcode project from the project definition

The project includes `project.yml`, which generates a native project with unit tests and macOS UI tests.

```bash
brew install xcodegen
cd TermiPad
xcodegen generate
open TermiPad.xcodeproj
```

In the Xcode toolbar choose **TermiPad > My Mac**, then press `Command + R`. The first run explains the boundaries of scanning, data, local terminal automation, and optional network enrichment; confirm, then use "Discover Tools". After the first scan, open the **Review Inbox** in the left sidebar to confirm which tools to accept.

### Swift Package

You can also open the package definition directly:

```bash
cd TermiPad
open Package.swift
```

You must still choose **My Mac** in Xcode. The package route suits source browsing and basic builds; for the full UI automation tests, use the generated `.xcodeproj`.

## Workflow

```text
Local tools: Discover Tools → accept in the Review Inbox → (optional) GitHub / AI enrichment → click the icon
→ fill in the form if the template has variables → run in your preferred terminal or copy the command

Project Discovery Preview: off by default → the user refreshes public repository metadata manually → review the project and its official channels yourself
(browse only; it does not install software, generate commands, or add anything to the library)
```

## First launch, data, and network boundaries

On first launch TermiPad states the following explicitly: scanning only checks PATH and common third-party install directories, and excludes macOS system directories, Apple Command Line Tools, the Xcode toolchain, package managers, service processes, and script parts; new commands go to the Review Inbox first and are never added to the tool wall automatically; tools, categories, templates, and variable values are stored on this Mac by default; GitHub / AI network enrichment is optional and off by default. A terminal command is handed to the chosen terminal only after you click a tool.

From **Settings** in the library's left sidebar, or **TermiPad → Settings… → AI Service** in the macOS menu bar, you can set an OpenAI Chat Completions-compatible service URL, model, and API key. The API key is written only to the macOS Keychain, never to UserDefaults or the repository; after you remove the API key, the app falls back to local descriptions and manual editing. GitHub enrichment accepts only the built-in official repository mapping or a high-confidence name match; low-confidence search results are never written to a tool automatically. AI may only add a purpose description and a category and **never rewrites the launch command**; a GitHub repository owner's avatar is not treated as the tool's official icon either, so icons keep coming from the local catalog or the stable fallback.

From **Settings → Backup & Restore** in the left sidebar, or **TermiPad → Settings… → Backup & Restore** in the menu bar, you can export a versioned JSON backup, or import a backup from another Mac and preview the merge first. A backup contains tools, candidates, categories, local icon metadata, installation source, GitHub match evidence, favorite state, last launch time, and command templates; **API keys are never exported**, and saved variable values are excluded by default and included only when the user explicitly checks the option. A custom image the user chose is stored only in the controlled local directory and is not exported as a JSON path or binary content; when restoring on another Mac it safely falls back to the local icon strategy. Per-tool working directories are likewise stored only on this Mac and are not written as JSON paths into backups or diagnostic packages; after a restore the current Mac's local preference is kept or the default launch context is used. Import merges by record ID and executable path and never deletes existing tools or candidates. For compatibility with old schema 1 backups, missing source and trust fields are derived safely from the local path; remote avatar URLs that may exist in old backups are ignored and never exported again.

The Review Inbox shows each command's local installation source. After accepting a tool, **Edit Tool → Source & Trust** shows which kind of local directory it came from, whether it went through the official GitHub mapping or a high-confidence name match, the linked repository, and the match score. Commands the user edited manually keep priority and are never overwritten by remote enrichment.

In **Settings → Diagnostics & Support** the user can deliberately export a local JSON diagnostic package or clear the records. Diagnostics contain only fixed event categories, timestamps, terminal names, and counts; they **never** contain tool names, executable paths, commands, variable values, API keys, or GitHub content. The diagnostic package is never uploaded automatically and never touches the network.

In **Settings → Update Checks** the user can opt in to a manual HTTPS version check. TermiPad ships with no preset update feed and never downloads, installs, or executes any update; even when a new version is found, the user still reads the notes and obtains it through a separate distribution process. The JSON format and the full boundaries are in [`docs/update-check-contract.md`](docs/update-check-contract.md).

## Terminal preference

From **Settings** in the left sidebar, or **TermiPad → Settings…** in the macOS menu bar:

- **Terminal.app**: runs the command in a new tab or window via AppleScript.
- **iTerm**: writes the command into the current session; creates a default window if none is open.
- **Warp**: opens Warp and copies the full command so the user can review it and paste it to run.
- **Copy Command Only**: opens no terminal and only copies the final command to the clipboard.

### macOS Automation permission

The first time you use one-click launch with **Terminal.app** or **iTerm**, macOS may ask whether TermiPad may control the chosen terminal. This is a system privacy mechanism the app cannot bypass. Choose Allow in the prompt; if you denied it earlier, go to **System Settings → Privacy & Security → Automation** and enable the corresponding Terminal.app or iTerm under TermiPad.

If the permission has not been granted yet, TermiPad does not discard the command you filled in or rendered: it copies the command to the clipboard automatically and shows the explicit authorization path above. After granting permission, click the tool again to continue with one-click launch.

## Command templates

Write anything the user must fill in as `{{variable_name}}`, for example:

```text
claude --model {{model}} {{prompt}}
```

TermiPad shows a form before launching. Variable values are shell-escaped with POSIX single quotes so that spaces or quotes cannot accidentally change the command structure; the user should still confirm the final command and its effects before running it.

## Automated verification

On a Mac, prefer running the following one-step verification script:

```bash
cd ~/TermiPad
./scripts/verify-macos.sh
```

The script regenerates the `.xcodeproj`, then runs Swift Package manifest validation, unit tests, and the `xcodebuild` build in order, and verifies the local signature of the test Runner before the UI smoke tests. Each run's logs, `.xcresult`, exportable UI screenshots, and summary are written to `.verification/`. To quickly check only the core logic and the build, run `./scripts/verify-macos.sh --skip-ui`.

The GitHub Actions workflow includes:

1. Swift unit tests: scan filtering, categorization, command variables, and icon fallback.
2. `xcodebuild` macOS build.
3. macOS UI smoke test: completes the first-run trust onboarding, checks the main controls, and archives the `.xcresult` and screenshots.

Cloud runs of GitHub Actions are currently blocked by an account-level billing/quota limit; once that is resolved, the workflow resumes the verification above automatically.

### Release artifact check

`./scripts/verify-macos.sh` only verifies development builds; it does not and cannot replace Developer ID signing and Apple notarization. On an archived, signed `.app`, you can run the following script to archive evidence of the signature, Hardened Runtime, entitlements, and (optionally) Gatekeeper/ticket checks:

```bash
cd ~/TermiPad
./scripts/verify-release-artifact.sh "/path/to/TermiPad.app"
# After notarization is complete and the ticket is stapled:
./scripts/verify-release-artifact.sh "/path/to/TermiPad.app" --require-notarization
```

The script does **not** sign, upload for notarization, or publish software; it only audits an already-built release artifact and writes the evidence to `release-evidence/`. The requirements for a formal release are in [`docs/private-beta-release-audit.md`](docs/private-beta-release-audit.md).

## Project structure

```text
TermiPad/
├── scripts/verify-macos.sh      # one-step local macOS verification
├── scripts/verify-release-artifact.sh # evidence check for a signed release artifact
├── Sources/
│   ├── TerminalTool.swift       # SwiftData tool and candidate models
│   ├── ToolScanner.swift        # scanning of PATH and common ecosystem paths
│   ├── CommandTemplate.swift    # {{variable}} parsing, rendering, and escaping
│   ├── TerminalLauncher.swift   # Terminal / iTerm / Warp / clipboard launch adapters
│   ├── LaunchpadView.swift      # native sidebar, Review Inbox, tool wall, and forms
│   ├── PreferencesView.swift    # app preferences
│   └── ToolIconView.swift       # differentiated icon system
├── Tests/                       # unit tests for the core logic
├── UITests/                     # macOS UI automation tests
├── project.yml                  # XcodeGen native project definition
└── .github/workflows/           # cloud builds and screenshot archiving
```

## Roadmap before the public release

Before going public, formal signing and notarization, a release package review, and deeper UI tests are still needed. Icons stay in the local semantic catalog; if brand icons are ever introduced, they must use verifiable sources, explicit user control, and a local caching strategy. Detailed priorities are in the private development document `termipad_development_backlog.md`.

## Language and appearance

TermiPad supports an immediate in-app language switch between **English** (the default) and **简体中文** (Simplified Chinese). Use the compact **中 / EN** segmented control in the main toolbar, or open **TermiPad → Settings… → Language**. Tool names, commands, paths, and README-derived descriptions are deliberately left unchanged.

The compact three-segment appearance control in the main toolbar, and **Settings → Appearance**, provides one-click access to **System**, **Light**, and **Dark**. The preference is stored locally and applied to both the main window and the Settings window.

### Soft macOS appearance

Light mode uses a slightly blue-grey window background and near-white content surfaces instead of large areas of pure white; dark mode uses graphite grey and layered card surfaces instead of pure black. The sidebar, content area, and tool cards share one semantic hierarchy. Switching between "System / Light / Dark" completes with an ease-in-out transition of about 0.30 seconds; if "Reduce motion" is enabled in macOS, the app respects that accessibility setting and drops the animation.

### Native controls and initial window position

Tool cards use a more compact `7pt` continuous corner radius, a light stroke, and a short shadow to approach the geometry of macOS content surfaces; candidate actions and the toolbar keep using the system bordered / borderedProminent control styles.

On first launch TermiPad places the main window in the **left half of the main display's usable area** (avoiding the menu bar and the Dock). After that the app respects the position and size you set manually and never grabs the window again. To experience the first-launch placement again, run:

```bash
defaults delete com.termipad.app TermiPad.hasPlacedInitialMainWindow
```

The project definition has updated the Xcode upgrade check marker. After pulling the update, be sure to run `xcodegen generate` again; do not keep using the old `.xcodeproj`.

### Tool tile tips and toolbar controls

The language and appearance segmented controls in the main window use the regular macOS control size, with extra spacing between the two groups. A tool tile always shows only the icon and the tool name, staying compact and consistent; categories are still used for filtering in the left sidebar, internal organization, and description fallback, but take no space on the tile. When the pointer rests on any tool tile, a native macOS popover shows two short notes above the tool wall: **Purpose** says what it helps you get done, and **Getting started** says where to launch it, what to prepare, or how to continue. The notes use continuous rounded corners, a neutral light-grey material, a thin stroke, and a soft shadow, and adjust their surface contrast for light and dark appearances. Common CLIs (such as Claude, GitHub CLI, Lazygit, FFmpeg, fzf, and Terraform) get more specific local notes; a reliable README / AI summary, when available, is preferred as the purpose. Legacy background statuses such as "正在尝试 AI 增强" ("attempting AI enrichment") are no longer shown as hover tips or accessibility text.

`project.yml` explicitly enables the Xcode-recommended Dead Code Stripping, User Script Sandboxing, String Catalog Symbol Generation, and Asset Symbol Extensions. After regenerating the project, the project-level "Update to recommended settings" checklist should no longer ask for these settings.
