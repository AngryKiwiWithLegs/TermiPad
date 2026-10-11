# TermiPad TaskIntent data dictionary

**Source:** Aligned with row 1 of `docs/t0-development-preparation-checklist.md` §4 "materials and evidence that must be maintained during development": "TaskIntent data dictionary — prevents the semantics of project, command, risk, time limit, and result fields from drifting across entry points".

**Status:** Takeover commit 1.1 (2026-08-29, zcode) — this is the **first time** the one taking over **made** the §4.1 material **explicit**. Every later field addition or semantic change at a T0/T1/T2 entry point must update this document in step.

**Scope:** 5 SwiftData entities (`Sources/TaskIntent.swift` and `Sources/TerminalTool.swift`), covering the three entry points T0 workbench / T1 executor / T2 MCP.

## 1. Entity list

| Entity | File:lines | Purpose |
|---|---|---|
| `TaskProjectScope` | `Sources/TaskIntent.swift:68-90` | The project root the user selected on the Mac; a task is a sub-action of that directory |
| `TaskReviewWindow` | `Sources/TaskIntent.swift:93-124` | A short local review window the user opens deliberately (15 minutes by default) |
| `TaskIntent` | `Sources/TaskIntent.swift:127-199` | A one-off task proposal, bound to scope + kind + risk + nonce + lifecycle |
| `TerminalTool` | `Sources/TerminalTool.swift:418-501` | A fixed tool record (not on the T0 proposal path, but referenced by T2 MCP) |
| `CandidateTool` | `Sources/TerminalTool.swift:518-572` | A candidate tool from the scanning stage (not on the T0/T1/T2 paths) |

## 2. Enums and boundary values

| Enum | Location | Values | Purpose |
|---|---|---|---|
| `TaskKind` | `Sources/TaskIntent.swift:5-11` | `swiftPackageTests` / `macOSVerification` / `xcodegenGeneration` | Fixed task catalog categories — every MCP proposal must be ∈ this set |
| `TaskRiskLevel` | `Sources/TaskIntent.swift:13-23` | `low` / `standard` | `.permits(_:)` decides whether a review window allows this risk |
| `TaskIntentState` | `Sources/TaskIntent.swift:25-32` | `pendingReview` / `approved` / `rejected` / `expired` / `revoked` / `cancelled` | The proposal's policy state machine |
| `TaskExecutionState` | `Sources/TaskIntent.swift:35-44` | `notStarted` / `running` / `succeeded` / `failed` / `timedOut` / `stopped` / `startRejected` / `startFailed` | The minimal result states returned by the executor |
| `TaskRejectionReason` | `Sources/TaskIntent.swift:55-65` | `unknownTaskKind` / `projectScopeUnavailable` / `localReviewRequired` / `reviewWindowExpired` / `riskNotPermitted` / `nonceReplayed` / `taskExpired` / `taskNotPending` / `taskCancelled` | 9 rejection paths — see the unit tests in §3 |
| `TaskExecutionRejectionReason` | `Sources/TaskIntent.swift:46-53` | `intentNotApproved` / `intentExpired` / `taskAlreadyStarted` / `projectScopeUnavailable` / `taskDefinitionUnavailable` / `taskPreflightFailed` | 6 reasons a "start" is rejected |

## 3. TaskProjectScope field table

| Field | Type | Default | Use across entry points | In JSON backup | In diagnostics |
|---|---|---|---|---|---|
| `id` | UUID | `UUID()` | All of T0/T1/T2 | ❌ | ❌ |
| `displayName` | `String` | Required | Shown in the T0 workbench, not read by T1, summarized by T2 | ❌ | ❌ |
| `rootPath` | `String` | Required + standardized | T0 scope constraint, T1 cwd, T2 checks availability | ❌ | ❌ |
| `isRevoked` | `Bool` | `false` | All of T0/T1/T2 | ❌ | ❌ |
| `createdAt` | `Date` | `Date()` | T0/T2 sorting | ❌ | ❌ |
| `revokedAt` | `Date?` | `nil` | All of T0/T1/T2 | ❌ | ❌ |

**Red lines:** the `rootPath` path **never** enters the JSON backup, the `iconURLString` path **never** enters diagnostics, and the scope display name is truncated to 80 characters in the T2 MCP response (see `Sources/TaskMCPBridge.swift:127-128`).

## 4. TaskReviewWindow field table

| Field | Type | Default | Use across entry points | In JSON backup | In diagnostics |
|---|---|---|---|---|---|
| `id` | UUID | `UUID()` | T0/T2 | ❌ | ❌ |
| `projectScopeID` | UUID | Required | T0 links the scope, T1 links the scope, not read by T2 | ❌ | ❌ |
| `maximumRiskRawValue` | `String` | `"standard"` | T0 policy check | ❌ | ❌ |
| `openedAt` | `Date` | `Date()` | T0 sorting | ❌ | ❌ |
| `expiresAt` | `Date` | Required | T0 `isActive(at:)` | ❌ | ❌ |
| `revokedAt` | `Date?` | `nil` | T0 policy check | ❌ | ❌ |

**Red line:** the window lifetime is hard-coded by `localReviewWindowLifetime: TimeInterval = 15 * 60` at `Sources/TaskIntentPolicy.swift:11`; any window longer than 15 minutes must define a separate `localReviewWindowLifetime` constant in code and update this table in step.

## 5. TaskIntent field table

| Field | Type | Default | Use across entry points | In JSON backup | In diagnostics |
|---|---|---|---|---|---|
| `id` | UUID | `UUID()` | T0/T1/T2 | ❌ | ❌ |
| `projectScopeID` | UUID | Required | T0 scope constraint, T1 cwd derivation, T2 lists the scope | ❌ | ❌ |
| `kindRawValue` | `String` | Required (must be ∈ `TaskKind.allCases`) | T0/T1/T2 | ❌ | ❌ |
| `riskRawValue` | `String` | `low` (from `FixedTaskCatalog`) | T0 risk tiering, reused by T1, shown by T2 | ❌ | ❌ |
| `stateRawValue` | `String` | `"pendingReview"` | T0 state machine, T1 guard, T2 `state` | ❌ | ❌ |
| `nonce` | UUID | `UUID()` | T0 replay defense (the `.review` check) | ❌ | ❌ |
| `proposedAt` | `Date` | `Date()` | T0 sorting, shown by T2 | ❌ | ❌ |
| `expiresAt` | `Date` | `proposedAt + 5min` (`proposalLifetime`) | T0 expiry check | ❌ | ❌ |
| `approvedAt` | `Date?` | `nil` | T0/T1/T2 | ❌ | ❌ |
| `resolvedAt` | `Date?` | `nil` | T0/T1/T2 | ❌ | ❌ |
| `rejectionReasonRawValue` | `String?` | `nil` | T0 rejection reason, T2 summary | ❌ | ❌ |
| `executionStateRawValue` | `String?` | `nil` ("notStarted") | Written by T1, read by T2 | ❌ | ❌ |
| `executionStartedAt` | `Date?` | `nil` | Written by T1 | ❌ | ❌ |
| `executionFinishedAt` | `Date?` | `nil` | Written by T1 | ❌ | ❌ |
| `executionExitCode` | `Int?` | `nil` | Written by T1, read by T2 | ❌ | ❌ |
| `executionRejectionReasonRawValue` | `String?` | `nil` | Written by T1, read by T2 | ❌ | ❌ |

**Red lines:**
- `kindRawValue` **must** be ∈ `TaskKind.allCases`, otherwise `Sources/TaskIntentPolicy.swift:40-42` returns `.rejected(.unknownTaskKind)`.
- The uniqueness of `nonce` is guaranteed by `Sources/TaskIntentPolicy.swift:49-54` (`existingIntents.contains`).
- The T2 MCP response returns only the `state` / `executionState` / `exitCode` / `executionReason` fields — it does **not** return commands, paths, variables, or the scope path. `Sources/TaskMCPBridge.swift:201-211` is the only place that returns `LocalMCPTaskState`.

## 6. TerminalTool field table (the part related to T0/T1/T2)

| Field | Type | Default | Relation to tasks | In JSON backup | In diagnostics |
|---|---|---|---|---|---|
| `id` | UUID | `UUID()` | Library ID | ✅ as `ToolRecord.id` | ❌ |
| `name` | `String` | Required | Tool name | ✅ | ❌ |
| `executablePath` | `String` | Required | Not read by T0, not read for T1 cwd | ✅ (confirmed by the user) | ❌ |
| `workingDirectoryPath` | `String?` | `nil` | Not read by T0/T1 | ❌ (locally sensitive) | ❌ |
| `commandTemplate` | `String` | `name` (fallback) | Not read by T0/T1 | ✅ (confirmed by the user) | ❌ |
| `toolDescription` | `String` | `""` | Not read by T0/T1/T2 | ✅ | ❌ |
| `categoryRawValue` | `String` | `ToolCategory.other.rawValue` | Not read by T0/T1/T2 | ✅ | ❌ |
| `iconSymbol` | `String` | `"terminal"` | Not read by T0/T1/T2 | ✅ | ❌ |
| `iconStyleIdentifier` | `String?` | `nil` | Not read by T0/T1/T2 | ✅ | ❌ |
| `customIconFilename` | `String?` | `nil` | Not read by T0/T1/T2 | ❌ (path of a controlled local PNG) | ❌ |
| `iconURLString` | `String?` | `nil` | Always `nil` (replaced by Source & Trust) | ❌ (never exported/restored) | ❌ |
| `repositoryFullName` | `String?` | `nil` | Not read by T0/T1/T2 | ✅ | ❌ |
| `installationSourceRawValue` | `String?` | `ToolInstallationSource.detect(...)` | Not read by T0/T1/T2 | ✅ | ❌ |
| `metadataProvenanceRawValue` | `String?` | `"local"` or `"manual"` | Not read by T0/T1/T2 | ✅ | ❌ |
| `metadataMatchConfidence` | `Int?` | `0` | Not read by T0/T1/T2 | ✅ | ❌ |
| `metadataUpdatedAt` | `Date?` | `nil` | Not read by T0/T1/T2 | ✅ | ❌ |
| `isFavorite` | `Bool?` | `false` | Not read by T0/T1/T2 | ✅ | ❌ |
| `isUserCustomized` | `Bool` | `false` | Not read by T0/T1/T2 | ✅ | ❌ |
| `isHidden` | `Bool` | `false` | Not read by T0/T1/T2 | ✅ | ❌ |
| `variableValuesJSON` | `String?` | `nil` | Not read by T0/T1 | ❌ (locally sensitive; the user opts in at export) | ❌ |
| `lastLaunchedAt` | `Date?` | `nil` | Not read by T1 | ✅ | ❌ |
| `createdAt` | `Date` | `Date()` | Not read by T0/T1/T2 | ✅ | ❌ |

## 7. CandidateTool field table (not read by T0/T1/T2, for the record only)

| Field | Type | In JSON backup |
|---|---|---|
| `id` | UUID | ✅ |
| `name` | `String` | ✅ |
| `executablePath` | `String` | ✅ |
| `categoryRawValue` | `String` | ✅ |
| `statusRawValue` | `String` | ✅ |
| `installationSourceRawValue` | `String?` | ✅ |
| `discoveredAt` | `Date` | ✅ |

**Note:** the T0/T1/T2 paths do not reference `CandidateTool` (it is used only by the inbox flow of `LaunchpadView.performScan`). It is listed only to cover every SwiftData entity in the project.

## 8. Invariance of field semantics across entry points

**Key invariants** (no commit may break them):

1. The 5 fields written at the **T0 entry point** (`Sources/TaskPolicyWorkbenchView.swift`) (`projectScopeID` / `kindRawValue` / `riskRawValue` / `stateRawValue` / `nonce` / `proposedAt` / `expiresAt`) must be **semantically consistent with** the matching fields read by T2 MCP.
2. The 4 execution fields written at the **T1 entry point** (`Sources/TaskExecutionService.swift`) (`executionStateRawValue` / `executionStartedAt` / `executionFinishedAt` / `executionExitCode`) must **correspond one-to-one with** the `executionState` / `exitCode` read by T2 MCP.
3. For the **JSON backup** (`Sources/BackupService.swift:159-171`), the two parameters of `TermiPadBackup.make(tools:candidates:...)` are **by type `tools: [TerminalTool]` and `candidates: [CandidateTool]`** — `TaskProjectScope` / `TaskReviewWindow` / `TaskIntent` **cannot, by type, get in**. This is the type-system-level guarantee of the §4.5 migration and backup decision.
4. The **T2 MCP response** (`Sources/TaskMCPBridge.swift:201-211`) builds only the 8-field `LocalMCPTaskState` — with no commands/paths/variables/process output.

## 9. Reference diagram

```
TaskProjectScope
    ↑ referenced by id
    │ (scope.directoryIsAvailable / scope.isRevoked)
    │
TaskReviewWindow
    ↑ scope.id == TaskIntent.projectScopeID
    │
TaskIntent
    ↑ TaskKind (3 fixed) → FixedTaskCatalog (executable + args + preflight)
    │ TaskRiskLevel (.low / .standard)
    │ TaskIntentState (6 states) + TaskRejectionReason (9 reasons)
    │ TaskExecutionState (8 states) + TaskExecutionRejectionReason (6 reasons)
    │
    ↓ referenced by MCP (MCPStdIORuntime 5 tools, TaskMCPBridge 5 handlers)
    ↓ referenced by Executor (TaskExecutionCoordinator / TaskExecutionPolicy)
    ↓ referenced by Workbench (TaskPolicyWorkbenchView)
```

## 10. Maintenance rules

- **Any new SwiftData entity or field**: must update §3-§7 of this file + the invariants in §8.
- **Any change to the signature of `TermiPadBackup.make` at `Sources/BackupService.swift:159-171`**: must keep invariant 3 of §8.
- **Any change to the construction of `LocalMCPTaskState` at `Sources/TaskMCPBridge.swift:201-211`**: must keep invariant 4 of §8.
- **Commits of this file must stay in step with the code** — code changed without this file changing = an incomplete commit.
