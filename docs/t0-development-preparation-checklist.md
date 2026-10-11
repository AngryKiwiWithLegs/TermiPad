# TermiPad T0 pre-development notes and preparation checklist

**Applies when:** After the stage 0 icon system acceptance and before entering the T0 local task policy core on the Mac.

**Purpose:** T0 handles "one-off temporary tasks" for the first time. It is not an ordinary UI extension, so the execution scope, result boundary, and verification evidence need to be frozen first. This checklist does not ask the user to apply for an Apple Developer account, buy a domain, create a Bot, or provide any token now.

## 1. Existing constraints that must be inherited

| Constraint | How this round must inherit it |
|---|---|
| Consolidated verification discipline | For each large batch, after the static audit, commit, and push, the user runs `./scripts/verify-macos.sh` only once; no repeated manual pasting of test commands. |
| Command sovereignty | The command of a saved tool is never rewritten by AI, remote metadata, MCP, or the phone. |
| Local-first | Commands, project scopes, icons, diagnostics, backups, and policy stay on the Mac by default; the network is off by default. |
| Minimal data | API keys, variables, paths, command bodies, or full terminal output are never returned to diagnostics, the PWA, Telegram, MCP clients, or the phone. |
| Recovery compatibility | New persisted task/policy fields must come with migration, compatibility with old data missing the fields, a backup/restore decision, and isolated recovery tests. |
| Execution boundary | No full remote PTY inside the app; no public port; temporary tasks never become fixed tools automatically. |

## 2. The only acceptance that must be completed before entering T0

The current local icon system commit `0265caf` has finished code, tests, and the static audit, but has not yet completed consolidated verification on the user's real Mac. So before starting T0, back at the Mac the user should run only:

```bash
cd ~/TermiPad && git pull --ff-only origin master && ./scripts/verify-macos.sh
```

The only evidence to keep is the success or failure fragment at the end; on failure, follow the script's hint to the matching log. Do not introduce the task workbench in parallel before the icon batch is verified, or attributability is lost.

## 3. T0 policy inputs the user needs to provide or confirm

These are not credentials and need no answer now; at the T0 design review TermiPad should offer conservative defaults and then let the user decide whether to adjust them.

| Decision item | Conservative T0 default | What the user needs to confirm later |
|---|---|---|
| First allowed projects | Only TermiPad's own project root | Whether to add other explicit project roots. |
| First task types | Build, unit tests, UI tests, read-only status checks | Whether other variable-free test-style commands are allowed. |
| Network | Temporary tasks mark their network needs by default; external network actions are rejected without explicit permission | Which projects/tasks may use the network. |
| Remote window | T0 has no network and opens no remote window | Whether to allow it in the future, the maximum duration, and when it closes automatically. |
| Result return | Only `passed/failed/cancelled/timed out/needs local confirmation` and a structured test summary | Which redacted diagnostic snippets may enter an authorized agent session in the future. |
| Promotion to a fixed tool | Only by the user clicking confirm on the Mac | Which tasks are worth turning into icon tools. |

## 4. Materials and evidence that must be maintained during development

| Material | Why it is needed | How it is maintained |
|---|---|---|
| TaskIntent data dictionary | Prevents the semantics of project, command, risk, time limit, and result fields from drifting across entry points | Written into the design docs and locked down by unit tests. |
| Policy rejection matrix | Proves that tasks with an unknown project, expired, replayed, revoked, timed out, with a locked screen, or without permission are all rejected | At least one unit test per rejection path. |
| Harmless test task set | Tests the lifecycle with fixed build/test/status examples, without real secrets or destructive commands | Only repeatable commands inside the repository are used. |
| Process tree and cancellation evidence | Proves that stopping terminates the task and its child processes, leaving no background execution behind | Integration tests / real-Mac verification records. |
| Minimal result spec | Prevents stdout/stderr from being piped indiscriminately to the phone or an agent | Structured status and summary fields are audited one by one. |
| Migration and backup decision | States explicitly whether task history, project references, and permission policies are backed up, avoiding carrying local paths or sensitive runtime information | Reviewed together with the existing JSON backup and isolated recovery design. |
| Verification artifacts | Keep `.verification/<timestamp>/summary.md`, failure logs, the xcresult, and UI attachments | Archived only after each large batch's consolidated verification. |

## 5. Materials that need no preparation now

| Item | Why it is not needed now |
|---|---|
| Apple Developer account, certificates, or TestFlight | T0/T1 are the local task core on the Mac; real distribution of the native iPhone app belongs to a later external gate. |
| Bot token, Telegram webhook, Mini App URL | Telegram is an optional shortcut entry and takes no part in T0. |
| Public domain, cloud service, or fixed IP | T0 has no network; these need separate evaluation only before M2 remote sessions. |
| Remote terminal / PTY components | These are not in the approved product scope. |
| API keys, SSH private keys, or real production secrets | They should not be used as task test material, nor submitted to TermiPad, MCP, or chat entries. |

## 6. External conditions needed only in later phases

| Phase entered | External conditions | Notes |
|---|---|---|
| Native iPhone same-network pairing | A real iPhone, a real Mac, a LAN, the system local network permission | Used to verify Bonjour, local TLS, pairing, revocation, and background behavior. |
| Native iPhone long-term install / distribution | An Apple account and the applicable signing conditions | Until they are available, TestFlight, the App Store, or formal mobile distribution are not declared done. |
| Remote session / PWA | HTTPS origin, device identity, session service, and revocation model | Configured only after T0–T3 mature and the user explicitly approves. |
| Telegram Mini App | A private Bot, Keychain storage of the Bot token, a fixed HTTPS origin, server-side `initData` validation | Only an optional shortcut entry; webhooks and free-text commands are disabled. |
| macOS external distribution | Developer ID, Hardened Runtime, notarization, Gatekeeper cold start test | Still an external release gate. |

## 7. Pre-development conclusion

Before entering T0, what is really needed is not an account, a cloud server, or a phone Bot, but three things: **finish the consolidated macOS verification of the current icon batch; freeze conservative defaults for the first allowed projects and task categories; and write task result minimization and permission revocation as testable rules.**

Once these three are ready, T0 can proceed entirely inside the existing native macOS project, locally and offline. The native iPhone app, PWA, Telegram, MCP connectors, and remote sessions should be introduced layer by layer after the local policy core is stable.
