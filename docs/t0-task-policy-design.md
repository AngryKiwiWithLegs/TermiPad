# T0: local restricted task policy core

**Status:** In the implementation batch; this phase runs no tasks, creates no processes, and connects to no network, MCP, phone, PWA, Telegram, or PTY.

## Goal

T0 builds a local, auditable policy core for later temporary test tasks. What it solves is not "creating a shell inside the app", but first answering: does a one-off task belong to the fixed catalog shipped with the app, is it bound to a project scope the user chose on this Mac, is it inside a valid local review window, and has it been replayed, expired, cancelled, or revoked.

## Data contract

| Type | What is stored | What is not stored or sent out |
|---|---|---|
| `TaskProjectScope` | Local display name, project root, revocation state, time | Does not enter JSON backups, privacy diagnostics, chat, or web entries. |
| `TaskReviewWindow` | Project scope reference, maximum risk, start/end/revocation time | Does not represent remote permission and opens no network connection. |
| `TaskIntent` | Project scope ID, fixed task type, risk, nonce, time limit, state, and rejection category | Carries no free-form command, arguments, environment variables, paths, network addresses, input, or output. |
| `FixedTaskCatalog` | The fixed task types, command previews, and purposes shipped with the app | Accepts no commands from AI, READMEs, web pages, Bots, or MCP. |

## Local state machine

```text
Create proposal → pendingReview
       │
       ├─ local scope + valid review window + nonce not replayed → approved
       ├─ expired → expired
       ├─ cancelled → cancelled
       └─ scope/window revoked → revoked or rejected
```

`approved` triggers no execution in T0. It only proves that the future T1 local task runner can receive a task already reviewed per policy. T0 never treats `approved` as a permanent background authorization.

## Fixed catalog

The initial catalog contains only: `swift test`, `./scripts/verify-macos.sh`, and `xcodegen generate`. Catalog entries have a full command preview and a risk level; agents, the phone, MCP, and remote metadata cannot create or modify entries.

If the user later wants to turn a one-off task into an icon tool, it must be done on the Mac through a separate, explicit confirmation action; T0 does not support automatic promotion.

## Rejection rules

| Condition | Result |
|---|---|
| The task type is not in the fixed catalog | `unknownTaskKind` |
| The project scope is missing, its directory is unavailable, or it is revoked | `projectScopeUnavailable` |
| No local review window was ever opened | `localReviewRequired` |
| All configured windows have expired | `reviewWindowExpired` |
| The window's risk level is insufficient | `riskNotPermitted` |
| The nonce was already used for another non-rejected task | `nonceReplayed` |
| The proposal has expired, was cancelled, or is no longer awaiting review | The matching fixed rejection state |

## Privacy and diagnostics

Diagnostics record only fixed event categories: proposal created, review window opened, policy approved/rejected, cancelled, and scope revoked. Events contain no project names, paths, commands, variables, output, secrets, or network addresses; the current JSON backup contains no task scopes or task history either.

## Static guards

For the T0 source files the consolidated verification script forbids `URLSession`, network connections, WebSocket, AppleScript, `TerminalLauncher`, `Process`, PTY, `/bin/sh`, URLs, `stdin`, `stdout`, and `stderr`. It also requires the fixed task catalog to exist. If later phases want to introduce an executor, MCP, or mobile connections, a separate design, test, and review batch must be created; capability must not be widened silently by removing the T0 guards.
