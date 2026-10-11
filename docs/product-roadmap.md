# TermiPad overall product roadmap

**Product positioning:** TermiPad is a native macOS **trusted terminal capability manager**. It organizes the CLI workflows the user configured deliberately — explainable and revocable — into icon tools; in later phases it will also offer restricted one-off test tasks, agent collaboration, and a native mobile management app, but it will not evolve into a public remote shell.

**Roadmap status:** Development planning; it does not mean every phase is implemented, verified, signed, or distributable.

## 1. North-star scenario

The user is discussing a project with an agent on the phone. The agent proposes a new test or fix command; the user is not at the Mac and cannot copy the command into a terminal. The user should be able to confirm the task proposal from their own mobile device, with TermiPad creating a restricted task session on the Mac that has a project scope, time limit, permissions, and the ability to stop, and returning only the minimal necessary result to the authorized session.

Meanwhile, already stable build, test, deploy, sync, or conversion flows should keep appearing as icon tools the user recognizes, without the agent regenerating the command every time.

> **Long-term promise:** fixed workflows are productized as trusted icon capabilities; temporary work is constrained into reviewable, expiring tasks; the Mac is always the sole execution authority.

## 2. Current product baseline

| Layer | Current status | Conclusion |
|---|---|---|
| **Mendocino core launcher** | Consolidated verification complete on the user's real Apple Silicon Mac, baseline `70d9d40` | Usable as the private development / self-test baseline. |
| **P0, P1, P2-A/B/C** | Complete and verified on real macOS | The review inbox, conservative project discovery, controlled install review, and read-only environment report are all finished. |
| **iPad-inspired macOS workspace** | Complete and verified | Keeps the native macOS structure and does not imitate an iPad body. |
| **Local icon system** | Consolidated verification complete on the user's real Mac, commit `0265caf` | The latest full verification passed on 2026-08-26 17:51; all 5 UI tests and the UI smoke test passed. |
| **Telegram / PWA icon preview** | Static prototype and design research complete | Connects to no real Mac, stores no token, and runs no tasks. |
| **T0 restricted temporary task policy** | Verified on real macOS | The fixed catalog, project scope, local review window, risk, nonce, expiry, cancellation, revocation, and privacy-preserving diagnostics are implemented; it runs no tasks. |
| **T1 local restricted task executor** | Verified on real macOS | Runs only fixed tasks approved by T0; project scope, fixed executable/arguments, stop, timeout, minimal status / exit code, and empty input/output are implemented. |
| **T2 local restricted MCP collaboration** | Verified on real macOS and the isolated read-only walkthrough is done | When the user explicitly turns it on and the app is running, the separate local `stdio` server offers, through CFMessagePort, only fixed task / scope queries, task proposals for review, minimal status reads, and cancellation of tasks that have not started; it supports exactly `2025-03-26` and the `2025-11-25` initialization version confirmed with OpenCode 1.14.33. The real-machine OpenCode walkthrough only listed scopes and fixed tasks, and the service was turned off again afterwards; no network or execution rights are opened. |
| **Native iPhone app** | Later phase | Not implemented, and it should not bypass the later security and acceptance gates. |
| **External distribution, iCloud, CloudKit** | Not implemented | Limited by external gates such as Apple Developer, signing, notarization, Gatekeeper, and real multi-device testing. |

The verified scope of the private beta, the release restrictions, and the external Apple gates are detailed in `docs/private-beta-release-audit.md`. For now Developer ID, Hardened Runtime, notarization, Gatekeeper cold start, iCloud, or a public release must not be described as done.

## 3. Final product architecture

TermiPad is centered not on some phone entry or chat platform but on the local policy core on the Mac. Fixed tools, temporary tasks, agent requests, and phone requests must all go through the same local decision.

```text
Native iPhone app (long-term primary entry)
PWA (validation / compatibility layer)
Telegram Mini App / Bot (optional shortcut entry and notifications)
Local MCP client (agent collaboration)
                 │
                 ▼
        TermiPad local policy core (Mac)
tool permission · project scope · remote allow window · risk level
signature · nonce · time limit · rate limiting · stop · revocation · audit
                 │
      ┌──────────┴──────────┐
      ▼                     ▼
Fixed icon tools        Restricted temporary task session
saved commands          one-off command, project boundary, timeout
Terminal/iTerm/Warp     minimal result return
```

### Two execution planes

| Execution plane | Suitable work | Command source | External result |
|---|---|---|---|
| **Fixed icon tools** | Stable, frequent, verified flows | Fixed commands saved by the user | Fixed states; commands and terminal output are not exposed. |
| **Restricted temporary tasks** | Test, build, or diagnostic tasks just generated in a conversation | A reviewable one-off `TaskIntent` | Structured results / minimal diagnostics limited by policy; no full interactive terminal is transferred. |

A fixed tool is never rewritten because of an agent request; and a temporary task is never silently promoted to a fixed tool. Only after the user explicitly confirms on the Mac can a temporary task be saved as a new icon tool.

## 4. Strategic layers

| Product layer | Purpose | Final form | Current priority |
|---|---|---|---|
| **A. Local trusted tool library** | Let users recognize, organize, launch, and recover their own CLI tools | Native macOS TermiPad | Highest; being finished continuously. |
| **B. Restricted task workbench** | Give one-off test tasks a scope, a time limit, and the ability to stop | Local TaskIntent / Task Session on the Mac | The next core development line. |
| **C. Agent collaboration** | Let local agents invoke fixed capabilities or propose temporary tasks | `stdio` TermiPad MCP | Implemented after B matures. |
| **D. Native mobile management app** | Manage pairing, icons, tasks, allow windows, and revocation | Native iPhone app | The long-term mobile end state. |
| **E. Compatibility and notification entries** | Install-free validation, opening shortcuts inside chat, status notifications | PWA, Telegram Mini App/Bot | Only reuse the core; they own no policy. |
| **F. Release and ecosystem** | Private beta, signing, notarization, future sync | Developer ID / Apple services | Depends on external accounts and real verification. |

## 5. Phase roadmap

### Stage 0: finish acceptance of the current icon system (done)

**Goal.** Move the local icon system of `0265caf` from the static-audit-complete state to the real-macOS-verified state.

**Scope.** Extended local SF Symbol catalog; persisted, deterministic fallback styles for unknown tools; manual icon selection; restoring automatic assignment; controlled local PNG with the highest priority; backup/restore compatibility; static guard against network icons.

**Acceptance.** Back at the Mac, the user runs the existing consolidated script once:

```bash
cd ~/TermiPad && git pull --ff-only origin master && ./scripts/verify-macos.sh
```

**Completion condition.** `TEST EXECUTE SUCCEEDED` and `[PASS] ui-smoke-test`. This condition was met on 2026-08-26 17:51; the icon batch has entered the real macOS verification baseline.

### Stage 1: T0 — local task policy core on the Mac (done)

**Goal.** Establish the `TaskIntent` for one-off tasks and its state machine, without networking, agents, or the phone at first.

**Implemented scope.** Project root reference, the fixed task catalog shipped with the app, command preview, risk level, short local review window, nonce, expiry, rejection reasons, cancellation, revocation, minimal status, and privacy-preserving fixed diagnostic events.

**Security principles.** A temporary task is not a "hidden shell"; no permanent background interactive session; no dynamic argument pass-through; no task automatically promoted to a fixed tool; no automatic install, upgrade, uninstall, or trust change. T0 runs no commands, creates no processes, and connects to no network, MCP, phone, PWA, Telegram, or PTY.

**Acceptance.** Unit tests cover the fixed catalog, review window, risk mismatch, expiry, replay, unknown task, revocation, cancellation, persistence, and diagnostics privacy; the real macOS consolidated script passed in the `20260826-181107` result directory on 2026-08-26.

### Stage 2: T1 — local temporary task executor and workbench on the Mac (done)

**Goal.** Without growing into an interactive terminal, let the user run local tasks approved by T0 on the Mac in a visible, understandable, controllable way.

**Implemented scope.** Runs only approved `TaskIntent`s; project scope constraint; fixed executable/arguments; empty stdin/stdout/stderr; explicit start/reject/stop; task-level automatic timeout; minimal local status, time, and exit code; failure states and stopping the direct task process. Commands, arguments, environment variables, URLs, PATH searches, and shells outside the fixed catalog cannot form an execution request.

**Explicit non-goals.** No embedded full terminal emulator; no PTY input; no showing or exporting a full terminal record by default; no network.

**Acceptance.** Policy tests cover approved fixed tasks, scope pre-check, rejection of unapproved/expired/repeated starts, and the minimal result of a non-zero exit; UI smoke covers the restricted local execution boundary; the real macOS consolidated script passed in the `20260826-183921` result directory on 2026-08-26.

### Stage 3: T2 — local restricted MCP collaboration (done)

**Goal.** Let local MCP-capable agents call TermiPad, rather than giving agents an arbitrary shell.

**Implemented scope.** The separate local `stdio` MCP server exposes only the five restricted capabilities `list_task_scopes`, `list_fixed_tasks`, `propose_task`, `get_task_status`, and `cancel_task`. The server does not access SwiftData directly; it goes back to the T0 policy core through the local CFMessagePort bridge held by the running main app; MCP is off by default and must be turned on explicitly by the user on the Mac. T2 cannot approve or run tasks; cancelling a running T1 task is explicitly rejected, and the user is asked to stop it in the local workbench.

**Security principles.** No `execute(command, cwd, env)` is exposed; no automatic reading of the whole disk; no automatic return of full stdout/stderr; clients, tasks, and approval records are distinguishable and revocable.

**Acceptance.** Protocol tests, strict tool schema tests, rejection of calls before initialization, rejection by the local switch, rejection of unknown fields, the minimal fixed task response, proposals for review, and cancellation tests; the verification script also statically forbids MCP / the bridge from using the network, XPC, processes, terminal handoff, PTY, output pipes, and direct SwiftData access from stdio. This condition was first met in the `20260826-212137` result directory on 2026-08-26; the regression including OpenCode 1.14.33 `2025-11-25` exact negotiation, workbench auto-save feedback, and the stable UI smoke assertion then passed again on 2026-08-27 `20260827-115315`, with output `TEST EXECUTE SUCCEEDED` and `[PASS] ui-smoke-test`. An isolated read-only walkthrough with OpenCode 1.14.33 was then completed: only `termipad-local` was enabled, only `list_task_scopes` and `list_fixed_tasks` were called, and it was turned off again at the end; no task was created, approved, run, or cancelled.

### Stage 4: M0/M1 — native iPhone app product and same-network pairing

**Goal.** Use a native iPhone app as the long-term mobile management entry, and validate device pairing and the task management experience on the same LAN.

**Scope.** Native tool icon catalog, device pairing, Mac online state, fixed tool requests, task cards, cancel/revoke, and remote allow window management. The network layer uses the Network framework, Bonjour, local TLS, the Keychain, and CryptoKit; the Mac remains the execution authority.

**External conditions.** Verification on a real iPhone/Mac, the network permission, and `Info.plist` declarations; long-term real-device install, TestFlight, or public distribution remain limited by Apple account/signing conditions.[1]

**Explicit non-goals.** No PTY on the phone; no full terminal output shown on the phone; no free shell accepted; no inbound public port opened on the Mac.

### Stage 5: M2 — remote secure session

**Goal.** Solve the north-star scenario of the user being out with only a phone and unable to copy a temporary test command.

**Scope.** The Mac actively maintains an authenticated outbound session; the native iPhone app submits fixed tool requests or temporary task proposals; the TaskIntent is re-verified locally on the Mac and then run; only the minimal result is returned.

**Entry strategy.** The native iPhone app is the long-term primary entry. The PWA is for quick UI validation and install-free compatibility; the Telegram Mini App is an optional in-chat shortcut entry; the Bot only handles fixed notifications and deep links.

**Security principles.** No public Mac address is exposed; the phone, PWA, or Telegram never hold commands, paths, variables, secrets, or full output; every device and session can be revoked.

**Transport technology decision (user decision of 2026-09-08).** The remote channel uses a **built-in tunnel** (following a pattern proven in the OpenClaw/SSH ecosystem): the service on the Mac binds only to the loopback address and reaches the phone through a Tailscale-style WireGuard tunnel (outbound connection, mutual device authentication, zero inbound ports on the router); nothing is uploaded to a third-party cloud relay and the Mac opens no public listener. The alternatives (public relay / self-built VPN) are not adopted. The same-network M1 direct connection (Bonjour + LAN) is kept as the near-field path; the tunnel is the remote path, and the two share the same pairing/encryption/revocation layer.

**M2a implementation and acceptance record (2026-09-09).** Relying on the user's own Tailscale install: on the Mac, `tailscale serve --tcp` forwards 57147 on the tailnet side to a 57148 listener bound only to loopback (NWListener `requiredInterfaceType = .loopback`), and tunnel connections share the pairing-encryption handshake chain with same-network resume (only resume from already-paired devices is accepted; first pairing must be on the same network); a same-network resume sends `tailnetEndpoint` along with MacResumeHello and persists it in the phone's keychain, so nothing needs to be done when leaving home; the phone prefers the LAN and falls back to the tailnet immediately after 6 seconds without a result or on cellular ENETDOWN. G5 real-device acceptance passed (2026-09-09: the full chain of remote channel connection over cellular, catalog, launch request, confirmation on the Mac, and receipt). Investigation note: the real device was at one point running an old build without the M2a code, creating the illusion of the tunnel being "silently not ready" — pairing diagnostic logs have since been added to the tunnel's three failure branches. M2b (minimal status feedback: the phone sees tool run status and exit codes, not commands or output) and the remaining G5 items (remote re-check of device revocation, abnormal paths) proceed in later commits.

### Stage 6: M3 — remote allow window and maturing the task policy

**Goal.** Reduce the confirmation friction of restricted remote tasks when the user clearly needs it.

**Scope.** Open a short remote allow window only for variable-free, individually authorized fixed tools or low-risk test tasks; the window expires automatically; requests are rejected immediately when the Mac is locked, asleep, the bridge stops, or the policy changes.

**Acceptance.** The remote window lifecycle, automatic expiry, device revocation, recovery after losing contact, rate limiting, result minimization, and abnormal rejection are all tested on real devices.

### Stage 7: release and ecosystem gates

**Goal.** Advance the controlled private beta and release quality once the external prerequisites are in place.

**Scope.** Developer ID, Hardened Runtime, entitlement review, notarization, Gatekeeper cold start, real old SwiftData store upgrade verification, and version and rollback strategy. iCloud/CloudKit become a separate project only after a development team, container, conflict model, and two-device verification are in place.

**Explicit non-goals.** No passing off ad hoc signing as external distribution; no substituting a local switch for iCloud; no promising a store listing, TestFlight, iCloud, or completed notarization without Apple's external conditions.

## 6. Mobile entry decision

| Entry | Long-term role | Use cases | Responsibilities it does not take |
|---|---|---|---|
| **Native iPhone app** | The final way to manage | Pairing, tool catalog, task approval, revocation, status, and the remote window | Does not hold the Mac's execution rights directly. |
| **PWA** | Validation and compatibility layer | Install-free preview, UI iteration, restricted access | Not the sole long-term permission store. |
| **Telegram Mini App** | Optional shortcut entry | Opening the icon workbench inside chat | Not the sole security control surface. |
| **Telegram Bot** | Notifications and deep links | Fixed status notifications, task reminders | Does not accept free commands or carry the tool grid. |

## 7. Non-negotiable product red lines

| Red line | Constraint across all phases |
|---|---|
| The Mac opens no public terminal | No terminal, HTTP MCP, or PTY listening on the public internet. |
| No arbitrary remote shell | The phone, Telegram, PWA, and restricted MCP accept no arbitrary commands, paths, variables, or URLs. |
| Commands cannot be rewritten by AI | Fixed tool commands are managed only by the user on the Mac; an agent can at most propose a temporary task. |
| Minimal data return | API keys, command bodies, working directories, environment variables, and full stdout/stderr are not sent to external entries. |
| Every permission is revocable | Devices, sessions, tools, projects, tasks, and remote windows can each be revoked independently. |
| Local-first | Icons, the catalog, commands, backups, and diagnostics stay under local control; network features are optional and off by default. |
| Not a replacement for professional remote terminals | A full remote PTY, arbitrary keyboard input, remote file browsing, and a permanent shell stay out of the product scope. |

## 8. Dependencies and decision gates

| Gate | Must be met before entering the next phase | Current status |
|---|---|---|
| G0 | The current icon system passes consolidated verification on a real Mac | Passed on 2026-08-26 17:51. |
| G1 | The T0 task policy core is thoroughly tested locally and has no network implementation | Passed the consolidated verification `20260826-181107` on 2026-08-26. |
| G2 | The T1 local temporary task UI passes real macOS verification | Passed the consolidated verification `20260826-183921` on 2026-08-26. |
| G3 | T2 local MCP exposes only restricted tools and has passed protocol/policy tests | Passed the consolidated verification `20260826-212137` on 2026-08-26; the regression including OpenCode `2025-11-25` exact negotiation, auto-save feedback, and the stable UI smoke assertion passed again on 2026-08-27 `20260827-115315`; the isolated OpenCode read-only walkthrough was completed on this Mac and the service turned off. |
| G4 | Native iPhone local pairing is tested successfully on two real devices | Testing in progress (2026-09-06: discovery / fingerprint comparison / pairing persisted, 3/7 passed, iPhone 14 Plus ↔ Mac on the same network); the remaining acceptance is completed after the session encryption and launch request channels are implemented. Free personal team signing is confirmed to work. |
| G5 | The remote session has device revocation, session expiry, minimal result return, and an attack surface audit | Not started. |
| G6 | Developer ID, notarization, and Gatekeeper cold start acceptance are complete | Blocked by external Apple conditions. |

## 9. Next development decision

**T2 is complete; the next step should be driven by a product decision first, rather than widening permissions by default.** The candidate next batches are: first, write a configuration and usability guide for the verified T2 and exercise it with a real local MCP client; second, without connecting a remote network or real tokens, start the pairing and local task management design of the M0/M1 native iPhone companion. Neither path may introduce HTTP MCP, a public Mac port, an arbitrary shell, a PTY, full output, or a bypass of local review on the Mac.

G0, G1, G2, and G3 are all complete. The project now has a verified local foundation running from "icon system improvements" and the "local restricted task workbench" to "local restricted MCP collaboration"; the phone UI, Telegram, and network bridging remain separate later phases that must be introduced layer by layer, each completing verification on real devices or against external conditions.

## References

[1]: https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy "Apple: TN3179 Understanding Local Network Privacy"
[2]: https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox "Apple: Configuring the macOS App Sandbox"
[3]: https://modelcontextprotocol.io/specification/2025-03-26/basic/transports "Model Context Protocol: Transports"
[4]: https://core.telegram.org/bots/webapps "Telegram: Mini Apps"
[5]: https://core.telegram.org/bots/api#getupdates "Telegram Bot API: getUpdates"
