# Launchpad standalone project: effort, difficulties, and staffing assessment

**Status:** Decision assessment draft; it does not mean development has started. This document is based on TermiPad Mendocino's native macOS project, icon system, and consolidated verification script, all verified on a real Apple Silicon Mac; it creates no Launchpad repository, migrates no code, and does not change TermiPad.

---

## 1. Conclusion

> **Launchpad does not start from zero, but it is by no means "rename it and you are done".** If the goal is limited to a reliable launcher for local graphical apps, much of the engineering method and UI foundation can be handed over; an estimated **35%–45%** of the repeated engineering work can be saved. The remaining core work must still be done anew: the application catalog data model, controlled collection, bundle icon resolution, launch on user click, missing-app handling, separate persistence, separate tests, and a separate brand.

My judgment is therefore: **worth doing, moderately difficult, with controllable risk; best implemented as "a clean new project + selective reuse of TermiPad's foundation layer".** Its MVP is not a few hours of renaming, but it also does not need to retrace TermiPad's whole path of building the native UI, icon system, XcodeGen, SwiftData, and real-Mac UI test infrastructure from scratch.

| Item | Assessment |
|---|---|
| Nature of the project | A sibling project with a similar structure and different business. |
| Degree of reuse | About 35%–45% of the engineering work can be reused directly or ported quickly; not 80% or more. |
| MVP difficulty | Moderate. Much easier than TermiPad's start, but more complex than a purely static icon wall. |
| Biggest technical risk | App collection scope, bundle/icon changes, sandbox/permission boundaries, window adaptation, and UI automation stability. |
| Biggest product risk | Over-pursuing "replacing the old Launchpad", leading to whole-disk scanning, batch launching, system hijacking, or mixing with TermiPad's CLI logic. |
| Best first-batch scope | Only a local `.app` catalog, search, favorites, recents, grouping, launch on user click, and one complete verification script. |

---

## 2. What can be reused and what must be redone

### 2.1 High-reuse-value assets

TermiPad has already solved the part of Launchpad that is easiest to underestimate: the native macOS UI skeleton, window restoration, bilingual UI and appearance, icon presentation, SwiftData local data recovery, test launch isolation, failure attachment collection, and one consolidated verification command. These capabilities can substantially lower the "engineering foundation" cost of the new project.

| Work layer | How it is reused | Effect on effort |
|---|---|---|
| XcodeGen + macOS 14+/Swift 5.9 project skeleton | Copy, then rename the targets, bundle ID, and test targets. | Saves about 0.5–1 person-day of initial project configuration and local Runner troubleshooting. |
| Native workspace, sidebar, toolbar, window policy | Split out and reuse the navigation shell, search state, empty states, and toolbar controls. | Saves about 1–2 person-days of trial and error on UI structure. |
| Chinese/English and System/Light/Dark appearance | Reuse the presentation layer pattern and rebuild the Launchpad copy table. | Saves about 0.5–1 person-day; new copy and an accessibility proofread are still needed. |
| Icon rendering and the local custom icon mechanism | Keep the ideas of a controlled local cache, manual override, and fallback. | Saves about 0.5–1 person-day; resolving real app bundle icons still has to be built. |
| SwiftData, recovery, and privacy-preserving diagnostics pattern | Reuse the container factory and recovery approach, with separate `LaunchAppEntry` data. | Saves about 1 person-day; data migration / missing-app state is new logic. |
| UI automation and the consolidated script | Copy the launch, window restoration, attachment export, and summary structure; rewrite the product assertions and guards. | Saves about 1.5–2.5 person-days and clearly lowers later diagnosis cost. |

### 2.2 The product core that must be implemented anew

Launchpad's value is not in "drawing a grid" but in reliably managing the graphical apps the user selected. TermiPad's `TerminalTool` contains the executable path, command template, variables, terminal handoff, CLI source, and task policy; those semantics cannot be carried over directly to the new project.

| New work item | Why it cannot be copied directly | Estimated complexity |
|---|---|---|
| `LaunchAppEntry` data model | A `.app`'s bundle ID, display name, source, bookmark, and missing state differ from a CLI command object. | Moderate. |
| Controlled app collection | Needs to be limited to standard directories and manual user selection, with deduplication and handling of moved/deleted apps. | Moderate. |
| Bundle metadata and icon resolution | Needs the local bundle / `NSWorkspace` rather than the CLI's semantic SF Symbol icon table. | Moderate. |
| Launch on user click | Should launch the app with `NSWorkspace` and give minimal failure feedback. | Low to moderate. |
| Favorites / recents / group ordering | Simple behavior, but it must be recoverable, testable, and must not pollute the original apps. | Moderate. |
| Launchpad-specific UI copy / first-run onboarding | Needs to explain "local catalog, refresh, privacy, manual add" and cannot reuse TermiPad's terminal risk copy. | Moderate. |
| New test guards | Must forbid shell, MCP, network, and remote launching, but cannot reuse TermiPad's task/MCP guards. | Moderate. |

---

## 3. Effort by phase

The table below uses **person-days** (effective development days of one skilled macOS/SwiftUI engineer); it is not a commitment to calendar dates, costs, or release outcomes. The ranges already include a reasonable buffer for code review, static audit, and real-Mac verification; they exclude Developer ID, notarization, the App Store, trademark review, and other external account processes.

| Phase | Content | Central estimate | Reasonable range | What the user needs to do |
|---|---|---:|---:|---|
| **L0: design freeze** | Product scope, data contract, permission boundary, information architecture, working name, test acceptance. | 1 person-day | 0.5–2 person-days | Only confirm 4–6 product choices. |
| **Proof of concept** | The new project launches; manually add one `.app`; local icon grid; launch on user click; minimal unit tests. | 3.5 person-days | 2–5 person-days | Run one consolidated verification on the real Mac. |
| **L1: usable MVP** | Manual refresh of standard directories, manual add, deduplication, search, favorites, recents, grouping, Chinese/English, appearance, recovery, UI smoke tests, and the consolidated script. | 12 person-days | 8–15 person-days | Usually 2–4 consolidated verifications, returning only the summary at the end each time. |
| **L2: reliability hardening** | Missing-app handling, icon refresh, accessibility, window/multi-display adaptation, menu bar entry, performance and migration audit. | 7 person-days | 5–10 person-days | 2–3 real-environment regressions and experience judgments. |
| **External distribution preparation** | Developer ID, notarization, Gatekeeper, privacy statement, website/support page, etc. | Counted separately | Depends on the account and external processes | Needs an Apple Developer account and a human release decision. |

By the central estimates, the proof of concept is about **3.5 person-days**; an L1 MVP that is really usable day to day is about **12 person-days**; the L2 version including reliability hardening is about **19 person-days**. Calendar time also depends on requirement confirmation, real-Mac verification rounds, and how fast issues are reported back: driven continuously by someone familiar with the project, L1 should usually be thought of as about **2–3 weeks**; with a newcomer building the test foundation while learning SwiftUI/AppKit, it often stretches to **4–8 weeks or longer**.

### 3.1 Why it is not "easy to knock out in one go"

"An app icon grid + opening apps" is not hard in itself, and a proof of concept can indeed appear quickly. But "delivering a launcher that can be used for the long term" includes a lot of inconspicuous work: how to recover after an app is duplicated/moved, what to do when a bundle icon is missing, how to avoid scanning into user files, how to render stably at different window sizes and system appearances, why the test app ends up with only a menu bar and no window, and how to get usable evidence on failure. These are exactly the parts where TermiPad has accumulated some methods but which the new project still has to re-adapt and re-verify.

So the right way to put it is: **it does not start from zero and the first version can be sped up markedly; but if the same robustness as TermiPad is required, the separate product core and verification loop must be built anew.**

---

## 4. Who should do it: me, a senior developer, or a newcomer

### 4.1 Recommendation

If the goal is "get, as soon as possible, a Launchpad MVP that can be maintained long term, looks consistent with TermiPad, and does not keep asking you to verify by hand", the recommendation is that **someone who already knows TermiPad's architecture and verification history** owns L0, the proof of concept, and the core security/data/test loop of L1. In the current context I can directly use the existing module split, the known Xcode 26.6 / SwiftUI behavior, the real-Mac verification script, and the UI automation problems already hit, so I am better placed to lead the architecture and hardening of the first version.

A newcomer is not incapable, but having a newcomer "copy TermiPad and rename it" alone from day one is not recommended. They are likely to carry CLI, Terminal, AI/network, or MCP logic unintentionally into an early version that seems to run, or to finish only the static visuals without a separate verification loop. A newcomer is better suited, once the L0 contract, component list, and test templates are clear, to tasks that do not touch the launch security boundary, such as standalone empty states, group editing, bilingual copy proofreading, additional test cases, or polishing the icon arrangement experience.

| Delivery mode | Early speed | UI consistency | Security/test risk | Recommended role |
|---|---|---|---|---|
| **Led through L0–L1 by someone familiar with the current architecture** | High. No need to relearn the existing tests and platform differences. | High. The established design language can be reused. | Low to moderate. Real-Mac verification is still needed. | **Most recommended**: the first version's product definition, data layer, launch path, test script, and hardening. |
| An experienced independent macOS developer takes over | Moderate. Needs 1–3 person-days of familiarization and migration notes. | Moderate to high, depending on how the design contract is followed. | Moderate. The consolidated script and code review should be mandatory. | Feasible: with clear handoff documents and a clean foundation package free of TermiPad business logic. |
| A newcomer derives from TermiPad alone | Fast on the surface, often slow in practice. | Unstable; easily slides back to "web-style cards" or copies the wrong business logic. | High. Tests, window restoration, and privacy boundaries are often overlooked. | Not recommended for the MVP core; suited to restricted, reviewable subtasks after L1. |
| Mixed mode | High. | High. | Low to moderate. | **Most practical**: I / a senior developer freeze the architecture and tests; the newcomer fills in UI and copy in small tasks. |

### 4.2 Minimum handoff bar for a newcomer

If a newcomer is to take part in the future, four clear materials should be prepared first: the Launchpad product contract, the list of reusable components, the list of modules that must not be copied, and a verification script that runs in one step on a real Mac. Every task needs an observable acceptance statement rather than "make it look more premium". For example, it should read "after the user clicks a collected `.app`, only the system app launch API may be called; no shell or network code may appear in the tests; a screenshot attachment is produced on failure".

This kind of handoff keeps a newcomer's contribution controllable and lets different collaboration styles or developers get closer results later; but it still cannot fully replace practical experience with SwiftUI, AppKit, SwiftData, and macOS UI automation.

---

## 5. Final recommendation

I recommend **not starting right away**, and there is no need for a newcomer to begin copying code now. Put Launchpad in the standalone project queue as "assessed, awaiting approval". When you decide to do it, prefer the following order:

1. Have the deliverer familiar with TermiPad complete L0 first, settling the new project's working name, catalog scope, data model, privacy boundary, and L1 acceptance.
2. Create a brand-new private repository and bundle ID, and selectively port the presentation layer, icon mechanism, test scaffolding, and consolidated verification structure onto a clean XcodeGen project.
3. Do a proof of concept of about 3.5 person-days first, confirming that real `.app` icons and launch on user click work as expected on your Mac.
4. Invest in L1 only after the proof of concept passes; at that point UI subtasks that do not touch the launch path can be assigned to a newcomer, with tests and code review guarding the boundary.
5. Revisit the iPhone companion only after L1/L2 are both stable; do not let Launchpad connect to MCP, a phone, the web, or remote launching ahead of time.

This path uses what TermiPad has already built up without mistaking "related" for "no independent engineering cost".
