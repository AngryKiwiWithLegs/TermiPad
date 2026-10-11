# TermiPad phase-two value review to-dos

- [x] Assess the feasibility of reusing TermiPad's native macOS architecture, design system, icon mechanism, and automated verification for a standalone Launchpad project, separating code that can be copied from business/security logic that must not be inherited.
- [x] Define the standalone Launchpad project's minimal app-launcher MVP, data boundaries, off-by-default optional capabilities, and explicit non-goals; no changes to macOS itself and no new features stuffed into TermiPad.
- [x] Plan the new private repository, the derivation approach, attribution of history, the test baseline, and batch-by-batch verification; create the project or migrate code only after the user confirms the product scope.

## Launchpad standalone project: effort and delivery assessment

- [x] Quantify the reuse ratio of TermiPad's base workspace, icon system, persistence, automated tests, and verification scripts, and the new work needed for Launchpad's application catalog model and user launch logic.
- [x] Assess the effort, the number of real-Mac verification rounds, the main technical risks, and the uncertainties across four layers: proof of concept, usable MVP, reliability hardening, and external distribution preparation.
- [x] Compare reuse efficiency, testing ability, UI consistency, and security/maintenance risk between a senior deliverer who already knows the TermiPad architecture and a newcomer taking over; do not start the new project.

## Approved: Launchpad standalone project kickoff and handoff

- [ ] Archive TermiPad's latest verification baseline, portable infrastructure, modules that must not be copied, the development environment, and the real-Mac verification method into a standalone handoff package.
- [ ] Freeze the Launchpad L0 product contract: local graphical `.app`s only, launch on user click, separate data storage, no CLI/MCP/network/remote control; TermiPad is not modified.
- [ ] Create a new private Launchpad repository and a clean XcodeGen native macOS project, copying only the approved presentation, icon, and test foundations.
- [ ] Write the architecture, design, data, testing, security boundary, newcomer onboarding, and phased roadmap material into the Launchpad repository; do not copy user tools, commands, variables, secrets, or TermiPad data.
- [ ] Complete the static audit, commit and push, and request one Launchpad-specific consolidated macOS baseline verification before entering L1 feature development.

- [x] Audit the existing TermiPad launcher, native UI, design docs, and UI automation test assets into a topic checklist that is reusable without leaking user configuration.
- [x] Research the system capabilities of the current macOS Launchpad / app launchers, and determine the boundary between a standalone enhanced launcher TermiPad could implement and system components that cannot be replaced.
- [x] Write the topic plan "TermiPad launcher extension, native UI system, and automated UI verification"; deliver the decisions and the description of portable assets first, without automatically changing the product's security scope or starting iPhone development.

- [ ] Take stock of the verified core launcher capabilities and the candidate phase-two capabilities, so the completed P2 security extensions and phone collaboration are not mixed into one development phase.
- [ ] Evaluate by user value, expected frequency, security complexity, maintenance cost, and external account/hosting dependencies: icon library improvements, a local phone companion, a Telegram Bot, a Telegram Mini App, a PWA icon panel, and a truly restricted launch entry.
- [ ] Decide the phase-two tiers: invest now, keep as a design reserve, or do not invest until there is real usage evidence.
- [ ] Make explicit that no phone or Telegram capability changes the product red lines "the Mac opens no public ports, no arbitrary commands, no sensitive output".
- [ ] Deliver the phase-two roadmap recommendation to the user, and do not start any real Bot/Mac integration before the user explicitly picks a direction.

## Approved: phase-two local icon system

- [x] Audit `TerminalTool`, `ToolIconView`, the tool edit UI, the migration/backup model, and the existing icon tests.
- [x] Design and implement a persisted local icon identity, keeping the custom-PNG-first rule, without transferring icons or adding network resources.
- [x] Extend the built-in semantic SF Symbol catalog, and implement stable, deterministic, conflict-aware local fallback assignment for unknown tools.
- [x] Offer user-initiated built-in icon selection and restore-automatic-assignment actions in the tool edit flow.
- [x] Complete the final static audit, commit and push, and pass the existing consolidated macOS verification script once on the user's real Mac.

## Re-evaluation of the phone app as a formal capability

- [ ] State the phone product promise explicitly: when away from the Mac, the user can view and tap their own authorized fixed tool entries on the phone, and the Mac hands off safely and locally; "has it been widely validated" is not a precondition for rejection.
- [ ] Assess the technical feasibility, long-term cost, release dependencies, and security conditions of this scenario along three paths: a same-network native companion, a PWA, and a Telegram Mini App.
- [ ] Make explicit the scope of restricted launching, status confirmation, and revocation this capability can deliver, and the boundary that it cannot accept arbitrary commands, arguments, paths, output, or a public entry point into the Mac.
- [ ] Produce a phased roadmap that can serve as a formal follow-up capability, and do not connect real tokens, web services, or remote execution before the user authorizes it.

## Restricted MCP server assessment

- [ ] Position TermiPad's MCP as a local restricted tool server: agents may list approved tools, read minimized descriptions, and request fixed tool launches; no arbitrary shell, path, variable, terminal output, or file browsing tools are provided.
- [ ] Check whether the current session has usable MCP/connector configuration, and research the security requirements of local stdio and remote transports for MCP servers.
- [ ] Design the MCP tool contract, per-tool authorization, user confirmation, short execution windows, audit events, and rejection/revocation rules.
- [ ] Make explicit that the MCP agent path and the phone path share TermiPad's local policy layer without widening each other's permissions; do not implement or expose the server before the user explicitly approves.

## Direct terminal MCP vs. the TermiPad gateway

- [ ] Compare an arbitrary-terminal-execution MCP with TermiPad's restricted-tool MCP in terms of invocation power, approval, auditing, revocation, output handling, and mobile exposure surface.
- [ ] Verify against official MCP security material and existing practice with terminal execution capabilities, identifying prompt injection, command construction, secret leakage, permission inheritance, and irreversible operation risks.
- [ ] Make explicit the unique capabilities TermiPad offers as a gateway, and whether the extra complexity it brings is worth keeping.
- [ ] Give the product architecture conclusion: pure direct MCP, pure restricted gateway, or both layers side by side, and who each path is for.

## Isolated temporary terminal and instant testing from the phone

- [ ] Define the minimal product promise of what the user calls a "clean terminal": one-off, constrained to the project directory, stoppable, expiring, and returning only minimal results to the phone.
- [ ] Research the feasibility and limits on macOS of a new shell, a restricted workspace, alternatives to sandbox-exec, permission inheritance, and process lifecycle.
- [ ] Compare how "a new shell", "a project-restricted workspace", and "a full remote interactive terminal" cover the pain point of instant testing from the phone, with their risks and development costs.
- [ ] Decide whether the isolated temporary terminal should be a separate TermiPad product line; do not add a PTY, remote input, terminal output return, or network listening before the user explicitly approves.

## Formal comparison: instant testing from the phone and agent collaboration

- [ ] Collect the candidate architectures: fixed icon launching, a Telegram/PWA phone entry, direct terminal MCP, restricted TermiPad MCP, a plain new shell, a project-restricted temporary task session, and a full remote PTY.
- [ ] Score them uniformly on coverage of the scenario "away from the Mac and unable to copy a temporary test command", security isolation, development cost, always-on operations, external account dependencies, and product consistency.
- [ ] State the recommended architecture, the local foundation to build first, the later remote bridging capability, and the permanent remote shell scope that should stay out of the product.
- [ ] Produce the follow-up development opinion; do not implement network bridging, a PTY, or a real agent terminal connection before the user approves a specific phase.

## Phone entry form decision

- [ ] Separate the "phone UI entry" from the "Mac restricted task execution core": whether the choice is an app, a PWA, or Telegram, none may bypass the TaskIntent policy layer.
- [ ] Compare a native iPhone app, a home-screen PWA, a Telegram Mini App, and a pure Bot on ad hoc tasks away from the Mac, icon experience, identity, notifications, release dependencies, and long-term operations.
- [ ] Pick one primary entry and an optional secondary entry, and state that a pure Bot text interface is not treated as the icon workbench.

## Long-term mobile positioning (confirmed)

- [ ] Make the native iPhone app TermiPad's final mobile management entry, responsible for device pairing, the tool catalog, task approval, the remote allow window, status, and revocation.
- [ ] Demote the PWA to quick validation, install-free access, and a reusable UI layer; it is not the sole carrier of long-term permission management.
- [ ] Demote the Telegram Mini App to an optional in-chat shortcut entry, and limit the Bot to fixed notifications and deep links; it carries no free-form commands and no primary security policy.
- [ ] Finish the Mac's local TaskIntent and temporary task session core before developing the mobile UI, so the phone does not get an interface without an execution security boundary first; this capability is now the next development batch.

## Overall product roadmap

- [x] Take stock of the currently verified TermiPad Mendocino baseline, the local icon batch that passed consolidated verification, and external release gates such as the Apple account.
- [x] Unify the launcher, restricted temporary tasks, restricted MCP, the native iPhone management app, the PWA validation layer, and the optional Telegram entry into one product architecture.
- [x] Define the goal, scope, dependencies, security red lines, acceptance criteria, and explicit non-goals for every later phase.
- [x] Publish and commit the full roadmap and name the most reasonable next development batch; do not change the execution boundary or start networked implementation before the user approves.

## T0 pre-development notes and materials

- [x] Against the existing project summary, the private beta audit, the icon batch status, and the overall roadmap, confirm the verification and security constraints that must not regress in this round.
- [x] List the project scope, policy, test, and external account materials that the user or the development environment must provide before developing restricted TaskIntent, MCP, and the native mobile app.
- [x] Separate materials and evidence needed immediately, those to keep saving during development, and those needed only at the mobile/release stage.

## Approved: T0 local restricted task policy core

- [x] Audit the existing terminal handoff, SwiftData models, backup/restore, diagnostic records, settings entry points, and test structure to determine T0's minimal integration points.
- [x] Freeze the local data contract for `TaskIntent`, project scope, task category, risk, time limit, nonce, rejection reasons, minimal result, and revocation.
- [x] Implement the purely local task policy: explicit project scope, one-off authorization, rejection on expiry/replay/revocation, cancellation, and a minimal state machine; no remote connections beyond starting child processes.
- [x] Add a minimal local task workbench and test coverage, and statically forbid network, PTY, remote input/output, and arbitrary shell interfaces in the verification script.
- [x] Complete the static audit, commit and push, and pass one consolidated macOS verification on the user's real Mac.

## T0 compile fix

- [x] Fix the conditional foreground style of the project scope status icon in `TaskPolicyWorkbenchView` so every branch returns the same SwiftUI `Color` type.
- [x] Complete the static audit, commit and push, and pass one consolidated macOS regression verification on the user's real Mac; no changes to the task model, policy, fixed catalog, or security guards.

## Next phase: T1 local temporary task workbench

- [ ] Design the restricted task executor: runs only approved `TaskIntent`s, constrained to the project scope, stoppable, with automatic timeout, and producing only minimized local results.
- [ ] Define the rules for user confirmation before the executor starts, environment stripping, result retention, and failure recovery; still no network, MCP, mobile, or remote PTY.

## Approved: T1 local temporary task executor

- [x] Audit the T0 data model, the fixed task catalog, and existing process usage to determine the minimal integration point that lets only approved tasks into the executor.
- [x] Freeze the contract for the executor, process lifecycle, timeout, cancellation, minimal result, and privacy handling; free-form commands, arguments, environment variables, PTY, and network are explicitly unsupported.
- [x] Implement local execution constrained to the project scope, stopping, and automatic timeout, and have the task workbench show the minimal status and result.
- [x] Add tests for normal completion, non-zero exit, timeout, cancellation, repeated start, rejection of unapproved/revoked tasks, and output minimization, and add T1 static guards to the verification script.
- [x] Complete the static audit, commit and push, and pass one consolidated macOS verification on the user's real Mac.

## T1 Swift 6 concurrency fix

- [x] Change the `Process` termination and timeout callbacks to pass only the Sendable task ID, process identity, and exit information to the main-thread execution coordinator, without capturing the SwiftData `TaskIntent` or the non-Sendable `Process` across domains.
- [x] Complete the static audit, commit and push, and pass one consolidated macOS regression verification on the user's real Mac; no changes to the fixed task catalog, project scope, empty input/output, or network boundary.

## T1 exit code type fix

- [x] Explicitly convert `Int32` to the `Int` used by the task's minimal result model at the `Process.terminationStatus` callback boundary.
- [x] Complete the static audit, commit and push, and pass one consolidated macOS regression verification on the user's real Mac; no changes to the concurrency hand-back, fixed catalog, or execution scope.

## Next phase: T2 local restricted MCP collaboration

- [ ] Freeze the minimal tool contract of the local `stdio` MCP server, exposing only fixed tool queries and restricted task proposal/status/cancel, with no arbitrary shell, file browsing, or full output.
- [ ] Design the MCP client identity, the mapping of each request to a TaskIntent, revocation, and the diagnostics policy; no HTTP port or external connection is opened.

## Approved: T2 local restricted MCP collaboration

- [x] Audit the T0/T1 data models, the fixed task catalog, existing process entry points, and the current session's MCP configuration, confirming the server can only be used through local stdio.
- [x] Freeze the MCP initialization, tool schemas, client identity, request mapping, rejection categories, and minimal response contract; no commands, paths, variables, file contents, or full output are exposed.
- [x] Implement the restricted stdio MCP server and the local bridge to the Mac main app, supporting only querying fixed tools, proposing tasks, reading minimal status, and cancelling tasks.
- [x] Add protocol / tool schema / rejection / revocation tests and static guards, and provide a minimal local MCP management status; HTTP, WebSocket, network listening, and arbitrary shell are forbidden.
- [x] Complete the static audit, commit and push, and pass one consolidated macOS verification after this batch (2026-08-26, archive `20260826-212137`).

## T2 Core Foundation type fix

- [x] Explicitly convert the `replyMode` of `CFMessagePortSendRequest` from `CFRunLoopMode?` to the `CFString?` the API requires.
- [x] Complete the static audit, commit and push, and pass one consolidated macOS regression verification (2026-08-26, archive `20260826-212137`); no changes to JSON-RPC, the CFMessagePort bridge, the task policy, or the network boundary.

## T2 modern CFRunLoop API fix

- [x] Remove the deprecated `kCFRunLoopDefaultMode` and use `CFRunLoopMode.defaultMode.rawValue` to produce the default replyMode CFMessagePort needs.
- [x] Complete the static audit, commit and push, and pass one consolidated macOS regression verification (2026-08-26, archive `20260826-212137`); no changes to JSON-RPC, the CFMessagePort bridge, the task policy, or the network boundary.

## T2 CFData bridging fix

- [x] Explicitly bridge the local CFMessagePort callback request from `CFData` to Foundation `Data`, and check that the reverse conversion of the reply data stays compatible.
- [x] Complete the static audit, commit and push, and pass one consolidated macOS regression verification (2026-08-26, archive `20260826-212137`); no changes to JSON-RPC, the CFMessagePort bridge semantics, the task policy, or the network boundary.

## T2 SwiftData main-thread isolation fix

- [x] Explicitly isolate the local MCP bridge type that holds `ModelContainer.mainContext`, and its install path, to the main execution context.
- [x] Complete the static audit, commit and push, and pass one consolidated macOS regression verification (2026-08-26, archive `20260826-212137`); no changes to JSON-RPC, CFMessagePort, the task policy, the fixed catalog, or the network boundary.

## T2 MCP test return fix

- [x] Add the missing explicit `return` of `LocalMCPBridgeResponse` in the test helper bridge, keeping the existing mock response and protocol assertion semantics unchanged.
- [x] Complete the static audit, commit and push, and pass one consolidated macOS regression verification (2026-08-26, archive `20260826-212137`); no changes to the MCP runtime, CFMessagePort, the task policy, or the network boundary.

## T2 local MCP user guide

- [x] Check the verified local `stdio` launch path, the in-app enabling steps, the five tool contracts, the minimal results, and the rejection categories.
- [x] Write a guide for local MCP clients covering configuration, operation, disabling/revocation, and troubleshooting; no Manus connector is configured, and no phone, PWA, Telegram, or network bridge is connected.
- [x] Statically check that the guide does not overstate the implementation scope, then commit and push the document; no extra consolidated macOS verification is required at this stage.

## T2 OpenCode local MCP compatibility check

- [x] Verify the configuration file, field shapes, launch method, and tool permission behavior of local `stdio` MCP in the official OpenCode documentation.
- [x] Compare OpenCode's configuration model item by item against TermiPad's fixed `command + args`, no URL/secret/environment variable, and local review boundary.
- [x] Added a secret-free minimal configuration and read-only walkthrough steps; no Manus connector is created, no task is run, and no phone or network service is connected.

## T2 OpenCode one-off read-only integration walkthrough

- [x] Confirm OpenCode 1.14.33 on the user's Mac, the absolute path of the TermiPad executable, a normally running main app, and the local MCP state explicitly turned on by the user.
- [x] Prepare a revocable minimal OpenCode `type: "local"` configuration on the user's Mac that explicitly denies OpenCode's shell, edit, network, and sub-agent tools; no URL, secret, or environment variable is written.
- [x] Check the OpenCode service status only after the user turns MCP on in TermiPad on the Mac: `termipad-local` shows `connected` in OpenCode 1.14.33.
- [x] Explicitly disable `quick9-wormhole` of the same session in the temporary configuration, and list project scopes and fixed tasks successfully through `termipad-local` only; the scope list is empty, and no task was created, approved, run, or cancelled.
- [x] After the walkthrough the user turns off TermiPad's MCP switch, and `termipad-local` is set to `disabled` in the temporary OpenCode configuration; no task was created, approved, run, or cancelled.

## OpenCode NVIDIA DeepSeek default model switch

- [x] Discover the available DeepSeek model identifiers read-only on the user's Mac; confirmed there is no `nvidia` provider and the old `nvidia-nim-proxy.js` is not running; the user confirmed choosing the currently available NVIDIA NIM `nim/deepseek-ai/deepseek-v4-flash-0731`; no provider configuration, API key, token, or environment variable was read or displayed.
- [x] After confirming the exact model identifier, back up first and then update only the default model of the temporary read-only walkthrough configuration to `nim/deepseek-ai/deepseek-v4-flash-0731`; TermiPad MCP, other MCP services, and the permission deny rules are untouched.
- [x] Confirm NVIDIA NIM DeepSeek V4 Flash is active in the isolated session, and complete the TermiPad-only read-only queries `list_task_scopes` and `list_fixed_tasks`; the service is turned off again after the walkthrough.

## Local task workbench save feedback audit

- [x] Check the actual save/apply paths of project scopes, review windows, task proposals, and the local MCP switch, confirming all are saved locally at once; the missing save button is the auto-save design, but visible feedback was missing.
- [x] Keep auto-save, and add "saved automatically" feedback in keeping with native macOS conventions plus the current enabled/disabled state of local MCP; no changes to the task or MCP security boundaries.
- [x] Add a minimal UI regression assertion, complete the static audit, commit and push, and request one consolidated macOS verification before resuming the OpenCode read-only walkthrough. (Verification passed; see the several later [x] items.)

## Auto-save feedback UI accessibility fix

- [x] Fix the failing `task-policy-auto-save-status` assertion caused by macOS XCTest not exposing the `Label` identifier, by changing the status control to a stable accessible text element.
- [x] Change the workbench's single-parameter `onChange` to the macOS 14+ compatible signature, removing the deprecation warning; the switch's save semantics are unchanged.
- [x] Complete the static audit, commit and push, and request one consolidated macOS verification; resume the OpenCode read-only walkthrough only after it passes. (The consolidated macOS verification passed; see commit `0cdbc90` and `.verification/20260827-085159`.)

## Auto-save status: second UI hierarchy investigation

- [x] Extract the exact accessibility tree of the task workbench from the failure attachment of 2026-08-27 `20260827-104635`, confirming that the status text with the identifier is not exposed by SwiftUI as a queryable element.
- [x] Fold the auto-save feedback into the label of the task policy boundary element that is verified to be accessible, and adjust the minimal UI assertion; the user-visible feedback is not removed, and persistence, MCP, the task policy, and the executor are untouched.
- [x] Complete the static audit, commit and push, and request one consolidated macOS verification; resume the OpenCode read-only walkthrough only after it passes.

## Auto-save status accessibilityLabel compile fix

- [x] Fix the compile-time type mismatch in Xcode 26.6 where `accessibilityLabel` needs a SwiftUI `Text` rather than a `String`, keeping the single-accessibility-element design of the policy boundary.
- [x] Complete the static audit, commit and push, and request one consolidated macOS verification; resume the OpenCode read-only walkthrough only after it passes.

## Auto-save status Text dynamic label compile fix

- [x] Fix the issue in Xcode 26.6 where `Text` cannot match an initializer with the current dynamic interpolation, by building the policy boundary's dynamic accessibilityLabel with `Text(verbatim:)`.
- [x] Complete the static audit, commit and push, and request one consolidated macOS verification; resume the OpenCode read-only walkthrough only after it passes.

## Auto-save status nested interpolation compile fix

- [x] Fix the Xcode 26.6 parse failure caused by escaped strings nested inside the policy boundary's dynamic accessibilityLabel, by extracting it into a separate `Text` property.
- [x] Complete the static audit, commit and push, and request one consolidated macOS verification; resume the OpenCode read-only walkthrough only after it passes.

## Auto-save status UI assertion stability fix

- [x] Remove the fragile assertion that depended on the dynamic text of macOS SwiftUI's combined `accessibilityLabel`, keeping the user-visible auto-save status text.
- [x] Narrow the UI smoke coverage to the stably visible task workbench boundary, the MCP switch, and the fixed local security note; auto-save, MCP, the task policy, and the executor are untouched.
- [x] Complete the static audit, commit and push, and request one consolidated macOS verification; resume the OpenCode read-only walkthrough only after it passes.

## T2 OpenCode MCP protocol version compatibility fix

- [x] Verify that the MCP `initialize.protocolVersion` sent by OpenCode 1.14.33 is `2025-11-25`, confirming why it does not match TermiPad's currently fixed `2025-03-26`.
- [x] Implement exact version negotiation that accepts only the verified `2025-03-26` and `2025-11-25`, plus an OpenCode initialization unit test; no changes to the five tools, the strict schemas, CFMessagePort, SwiftData isolation, request rate limiting, or the local review/execution boundary.
- [x] The static audit is complete and `5c7d202` is pushed, and the consolidated macOS verification passed on 2026-08-27 `20260827-085159`; only one OpenCode read-only connection retry remains, with no task created, approved, run, or cancelled.

## UI smoke: shared launch failure investigation

- [x] Collect the minimal failing assertion from 2026-08-27 `20260827-082441`, confirming that all six UI scenarios stop at the shared launch step because the app already has an accessible UI but is not judged to be `.runningForeground`.
- [x] Fix only the shared root cause in UI test launch, window restoration, or test isolation: ensure an accessible main window first, then accept "foreground or an accessible main window" as launch evidence; no changes to the OpenCode protocol negotiation, MCP tools, CFMessagePort, the task policy, the executor, or the network boundary.
- [x] Complete the static audit, commit and push, and pass the consolidated macOS regression verification on 2026-08-27 `20260827-085159`; only then retry the OpenCode read-only integration.
