# TermiPad Minimal Result Spec (t0-checklist §4.4)

**Source:** Aligned with row 4 of `docs/t0-development-preparation-checklist.md` §4, "Minimal result spec — prevents stdout/stderr from being piped indiscriminately to the phone or an agent — structured status and summary fields are audited one by one".

**Status:** Takeover commit 1.4 (2026-08-29, zcode). This document makes the return allowlist explicit for the 3 enums in `Sources/TaskIntent.swift` (`TaskIntentState` / `TaskExecutionState` / `TaskRejectionReason` / `TaskExecutionRejectionReason`).

**Scope:** When any T0 workbench, T1 executor read, T2 MCP bridge, or future PWA/Telegram/iPhone entry reads a task result, it may return **only** the allowlisted fields in §2 of this document. It must **not** return commands, paths, variables, stdout, or stderr.

## 1. State Enums (from `Sources/TaskIntent.swift`)

| Enum | Lines | Number of values | Purpose |
|---|---|---|---|
| `TaskIntentState` | 25-32 | 6 | State machine of a proposal at the policy layer: `pendingReview` / `approved` / `rejected` / `expired` / `revoked` / `cancelled` |
| `TaskExecutionState` | 35-44 | 8 | Execution lifecycle returned by the executor: `notStarted` / `running` / `succeeded` / `failed` / `timedOut` / `stopped` / `startRejected` / `startFailed` |
| `TaskRejectionReason` | 55-65 | 9 | Policy-layer rejection paths: `unknownTaskKind` / `projectScopeUnavailable` / `localReviewRequired` / `reviewWindowExpired` / `riskNotPermitted` / `nonceReplayed` / `taskExpired` / `taskNotPending` / `taskCancelled` |
| `TaskExecutionRejectionReason` | 46-53 | 6 | Execution-layer paths where "start" is rejected: `intentNotApproved` / `intentExpired` / `taskAlreadyStarted` / `projectScopeUnavailable` / `taskDefinitionUnavailable` / `taskPreflightFailed` |

## 2. Minimal Result Allowlist (which fields each state may return)

### 2.1 `TaskIntent` Core Fields (`Sources/TaskIntent.swift:127-199`)

| Field | Returnable | Red line |
|---|---|---|
| `id` | ✅ | An opaque UUID is enough; internal incrementing IDs are **not** returned |
| `projectScopeID` | ✅ | Same as above |
| `kindRawValue` | ✅ | Must be ∈ `TaskKind.allCases` (a fixed 3) |
| `riskRawValue` | ✅ | `low` / `standard` |
| `stateRawValue` | ✅ | One of the 6 enum values |
| `nonce` | ✅ | Used only for local replay-defense auditing; **not** returned to the user |
| `proposedAt` | ✅ | Timestamp |
| `expiresAt` | ✅ | Timestamp |
| `approvedAt` | ✅ | Timestamp (if approved) |
| `resolvedAt` | ✅ | Timestamp (if resolved) |
| `rejectionReasonRawValue` | ✅ | One of the 9 enum values (if rejected) |
| `executionStateRawValue` | ✅ | One of the 8 enum values (if executed) |
| `executionStartedAt` | ✅ | Timestamp |
| `executionFinishedAt` | ✅ | Timestamp |
| `executionExitCode` | ✅ | Integer 0-255 |
| `executionRejectionReasonRawValue` | ✅ | One of the 6 enum values (if execution was rejected) |

### 2.2 `TaskProjectScope` Fields (`Sources/TaskIntent.swift:68-90`)

| Field | Returnable | Red line |
|---|---|---|
| `id` | ✅ | |
| `displayName` | ⚠️ **Metadata only** | `Sources/TaskMCPBridge.swift:127-128` already truncates it to 80 characters and **replaces `\n` with a space** (prevents log injection) |
| `rootPath` | ❌ **Never** | macOS paths and the user's project structure — **never leave this Mac** |
| `isRevoked` | ✅ | Boolean |
| `createdAt` | ✅ | |
| `revokedAt` | ✅ | |

**Fields T2 MCP actually returns** (`LocalMCPScopeSummary` at `Sources/TaskMCPBridge.swift:130-140`): only `scopeID` / `displayName` (80 char) / `status` (3 enum values: `revoked` / `available` / `unavailable`). **`rootPath` is not in this struct**.

### 2.3 Fields in the Actual T2 MCP Response (`Sources/TaskMCPBridge.swift:201-211` `summary(for:)`)

| Field | Type | Purpose |
|---|---|---|
| `taskID` | UUID | Opaque |
| `taskKind` | String | ∈ TaskKind.allCases |
| `risk` | String | `low` / `standard` |
| `state` | String | ∈ the 6 TaskIntentState values |
| `executionState` | String | ∈ the 8 TaskExecutionState values (may be nil) |
| `exitCode` | Int? | 0-255 |
| `executionReason` | String? | ∈ TaskRejectionReason / TaskExecutionRejectionReason |
| `expiresAt` | ISO8601 String | Timestamp |

**The code fact of the 8 fields of `LocalMCPTaskState`** = this spec's allowlist = everything any T2 MCP client can see.

## 3. Red Lines (never enter any external protocol)

| Data | Never sent out | Source |
|---|---|---|
| **`rootPath` / `workingDirectoryPath`** | A path is the user's identity | `Sources/TaskIntent.swift:71`, `Sources/TerminalTool.swift:423` |
| **`commandTemplate` / `executablePath`** | A command is execution capability | `Sources/TerminalTool.swift:421-424` |
| **`variableValuesJSON`** | Variable values contain tokens / credentials | `Sources/TerminalTool.swift:443` |
| **`customIconFilename`** | Path of a locally controlled PNG | `Sources/TerminalTool.swift:432` |
| **`iconURLString`** | Never written, never backfilled (`Sources/TerminalTool.swift:433`) | `Sources/BackupService.swift:48,71,101` |
| **`Process.standardOutput` / `standardError`** | Any task output | `Sources/TaskExecutionService.swift:139-141` blocks it with `FileHandle.nullDevice` |
| **API Key** | Keychain only | `Sources/KeychainStore.swift:6` |
| **Full stdout/stderr** | Never persisted, never returned | `Sources/TaskExecutionService.swift:139-141` + §2.3 of this document |

## 4. Audit Event Mapping (commit 1.4 also adds 2)

`DiagnosticEventKind` at `Sources/DiagnosticsService.swift:6-43` contains 45 events. Those related to the task domain:

| Event | Trigger location | Audit meaning |
|---|---|---|
| `taskProposalCreated` | T0 workbench + T2 MCP | A proposal was created |
| `taskReviewWindowOpened` | T0 workbench | The user opened a window on purpose |
| `taskPolicyApproved` | T0 workbench + T2 MCP approval | Allowed by the policy layer |
| `taskPolicyRejected` | T0 workbench + T2 MCP approval | Rejected by the policy layer (9 reasons) |
| `taskCancelled` | T0 workbench + T2 MCP cancellation | Cancelled on purpose |
| `taskScopeRevoked` | T0 workbench | The user revoked a scope |
| `taskExecutionStarted` | T1 executor | process run() succeeded |
| `taskExecutionSucceeded` | T1 executor | exit 0 |
| `taskExecutionFailed` | T1 executor | exit ≠ 0 |
| `taskExecutionStopped` | T1 executor | The user stopped it on purpose |
| `taskExecutionTimedOut` | T1 executor | Timeout triggered |
| `taskExecutionRejected` | T1 executor | .rejected at start |
| `taskExecutionStartFailed` | T1 executor | process.run() threw |
| **`taskExecutionResultRead`** (**new**) | T2 MCP reading task status | Task-domain audit, complementary to `.mcpTaskStatusRead` |
| **`taskProposalExpiringSoon`** (**new**) | T0/T2 check the expiresAt-60s boundary when reading a task | Gives the workbench a hint shortly before expiry |
| `mcpToolListed` | T2 MCP `tools/list` | An MCP client enumerates tools |
| `mcpTaskProposed` | T2 MCP `propose_task` | An MCP client submits a proposal |
| `mcpTaskStatusRead` | T2 MCP `get_task_status` | MCP protocol-layer audit |
| `mcpTaskCancelled` | T2 MCP `cancel_task` | An MCP client cancels |

**Two-layer audit** (implemented in commit 1.4): when T2 MCP reads task status it records **both** `.mcpTaskStatusRead` (protocol layer) and `.taskExecutionResultRead` (task domain). The two records are independent — "total MCP client traffic" and "how often task status is queried" can be analyzed separately.

## 5. Maintenance Rules

- **Adding any T0/T1/T2 entry**: §2's allowlist must be updated — existing fields may **only** be added to the allowlist; a new field must **not** be created on `LocalMCPTaskState` without being registered in this document.
- **Adding a `DiagnosticEventKind`**: a row must be added to the §4 table stating the trigger location + audit meaning.
- **Adding a state enum value** (such as adding `.paused` to `TaskIntentState`): §1 + the §2 tables + any assertion tests must be updated.
- **Commits of this file must stay in step with the code** — code changed without this file changing = an incomplete commit.
