# TermiPad TaskIntent 数据字典

**来源：** 对齐 `docs/t0-development-preparation-checklist.md` §4 "开发时必须维护的材料与证据" 第 1 行 "TaskIntent 数据字典——防止项目、命令、风险、时限和结果字段在多入口间语义漂移"。

**状态：** 接手 commit 1.1（2026-08-29，zcode）——这是接手人对 §4.1 材料的**首次显式化**。后续每个 T0/T1/T2 入口的字段新增或语义变化必须同步更新本文档。

**作用范围：** 5 个 SwiftData 实体（`Sources/TaskIntent.swift` 与 `Sources/TerminalTool.swift`），覆盖 T0 工作台 / T1 执行器 / T2 MCP 三个入口。

## 1. 实体清单

| 实体 | 文件:行 | 用途 |
|---|---|---|
| `TaskProjectScope` | `Sources/TaskIntent.swift:68-90` | 用户在 Mac 本机选定的项目根目录；任务是该目录的子动作 |
| `TaskReviewWindow` | `Sources/TaskIntent.swift:93-124` | 用户主动开启的短期本地审阅窗口（默认 15 分钟） |
| `TaskIntent` | `Sources/TaskIntent.swift:127-199` | 一次性任务提案，绑定 scope + kind + 风险 + nonce + 生命周期 |
| `TerminalTool` | `Sources/TerminalTool.swift:418-501` | 固定工具记录（不在 T0 提案路径上，但被 T2 MCP 引用） |
| `CandidateTool` | `Sources/TerminalTool.swift:518-572` | 扫描阶段的候选工具（不在 T0/T1/T2 路径上） |

## 2. 枚举与边界值

| 枚举 | 位置 | 取值 | 用途 |
|---|---|---|---|
| `TaskKind` | `Sources/TaskIntent.swift:5-11` | `swiftPackageTests` / `macOSVerification` / `xcodegenGeneration` | 固定任务目录类别——任何 MCP 提案必须 ∈ 此集合 |
| `TaskRiskLevel` | `Sources/TaskIntent.swift:13-23` | `low` / `standard` | `.permits(_:)` 决定审阅窗口是否允许此风险 |
| `TaskIntentState` | `Sources/TaskIntent.swift:25-32` | `pendingReview` / `approved` / `rejected` / `expired` / `revoked` / `cancelled` | 提案的策略状态机 |
| `TaskExecutionState` | `Sources/TaskIntent.swift:35-44` | `notStarted` / `running` / `succeeded` / `failed` / `timedOut` / `stopped` / `startRejected` / `startFailed` | 执行器返回的最小结果状态 |
| `TaskRejectionReason` | `Sources/TaskIntent.swift:55-65` | `unknownTaskKind` / `projectScopeUnavailable` / `localReviewRequired` / `reviewWindowExpired` / `riskNotPermitted` / `nonceReplayed` / `taskExpired` / `taskNotPending` / `taskCancelled` | 9 种拒绝路径——见 §3 单测 |
| `TaskExecutionRejectionReason` | `Sources/TaskIntent.swift:46-53` | `intentNotApproved` / `intentExpired` / `taskAlreadyStarted` / `projectScopeUnavailable` / `taskDefinitionUnavailable` / `taskPreflightFailed` | 6 种"开始"被拒原因 |

## 3. TaskProjectScope 字段表

| 字段 | 类型 | 默认 | 跨入口使用 | 进 JSON 备份 | 进诊断 |
|---|---|---|---|---|---|
| `id` | UUID | `UUID()` | T0/T1/T2 全部 | ❌ | ❌ |
| `displayName` | `String` | 必填 | T0 工作台显示、T1 不读、T2 摘要 | ❌ | ❌ |
| `rootPath` | `String` | 必填 + 标准化 | T0 范围约束、T1 cwd、T2 校验可用性 | ❌ | ❌ |
| `isRevoked` | `Bool` | `false` | T0/T1/T2 全部 | ❌ | ❌ |
| `createdAt` | `Date` | `Date()` | T0/T2 排序 | ❌ | ❌ |
| `revokedAt` | `Date?` | `nil` | T0/T1/T2 全部 | ❌ | ❌ |

**红线：** `rootPath` 路径**永不**进 JSON 备份、`iconURLString` 路径**永不**进诊断、scope 显示名在 T2 MCP 响应里截断至 80 字符（见 `Sources/TaskMCPBridge.swift:127-128`）。

## 4. TaskReviewWindow 字段表

| 字段 | 类型 | 默认 | 跨入口使用 | 进 JSON 备份 | 进诊断 |
|---|---|---|---|---|---|
| `id` | UUID | `UUID()` | T0/T2 | ❌ | ❌ |
| `projectScopeID` | UUID | 必填 | T0 关联 scope、T1 关联 scope、T2 不读 | ❌ | ❌ |
| `maximumRiskRawValue` | `String` | `"standard"` | T0 策略检查 | ❌ | ❌ |
| `openedAt` | `Date` | `Date()` | T0 排序 | ❌ | ❌ |
| `expiresAt` | `Date` | 必填 | T0 `isActive(at:)` | ❌ | ❌ |
| `revokedAt` | `Date?` | `nil` | T0 策略检查 | ❌ | ❌ |

**红线：** 窗口生命周期由 `Sources/TaskIntentPolicy.swift:11` `localReviewWindowLifetime: TimeInterval = 15 * 60` 硬编码；任何超 15 分钟的窗口必须在代码层另立 `localReviewWindowLifetime` 常量并同步本表。

## 5. TaskIntent 字段表

| 字段 | 类型 | 默认 | 跨入口使用 | 进 JSON 备份 | 进诊断 |
|---|---|---|---|---|---|
| `id` | UUID | `UUID()` | T0/T1/T2 | ❌ | ❌ |
| `projectScopeID` | UUID | 必填 | T0 范围约束、T1 cwd 派生、T2 列出 scope | ❌ | ❌ |
| `kindRawValue` | `String` | 必填（必须 ∈ `TaskKind.allCases`） | T0/T1/T2 | ❌ | ❌ |
| `riskRawValue` | `String` | `low`（来自 `FixedTaskCatalog`）| T0 风险分级、T1 复用、T2 显示 | ❌ | ❌ |
| `stateRawValue` | `String` | `"pendingReview"` | T0 状态机、T1 守卫、T2 `state` | ❌ | ❌ |
| `nonce` | UUID | `UUID()` | T0 重放防御（`.review` 检查）| ❌ | ❌ |
| `proposedAt` | `Date` | `Date()` | T0 排序、T2 显示 | ❌ | ❌ |
| `expiresAt` | `Date` | `proposedAt + 5min`（`proposalLifetime`）| T0 过期检查 | ❌ | ❌ |
| `approvedAt` | `Date?` | `nil` | T0/T1/T2 | ❌ | ❌ |
| `resolvedAt` | `Date?` | `nil` | T0/T1/T2 | ❌ | ❌ |
| `rejectionReasonRawValue` | `String?` | `nil` | T0 拒绝原因、T2 摘要 | ❌ | ❌ |
| `executionStateRawValue` | `String?` | `nil`（"notStarted"）| T1 写入、T2 读取 | ❌ | ❌ |
| `executionStartedAt` | `Date?` | `nil` | T1 写入 | ❌ | ❌ |
| `executionFinishedAt` | `Date?` | `nil` | T1 写入 | ❌ | ❌ |
| `executionExitCode` | `Int?` | `nil` | T1 写入、T2 读取 | ❌ | ❌ |
| `executionRejectionReasonRawValue` | `String?` | `nil` | T1 写入、T2 读取 | ❌ | ❌ |

**红线：**
- `kindRawValue` **必须** ∈ `TaskKind.allCases`，否则 `Sources/TaskIntentPolicy.swift:40-42` 返回 `.rejected(.unknownTaskKind)`。
- `nonce` 唯一性由 `Sources/TaskIntentPolicy.swift:49-54` 保证（`existingIntents.contains`）。
- T2 MCP 响应只返回 `state` / `executionState` / `exitCode` / `executionReason` 字段——**不**返回命令、路径、变量、scope 路径。`Sources/TaskMCPBridge.swift:201-211` 是唯一返回 `LocalMCPTaskState` 的地方。

## 6. TerminalTool 字段表（与 T0/T1/T2 关联部分）

| 字段 | 类型 | 默认 | 与 task 关联 | 进 JSON 备份 | 进诊断 |
|---|---|---|---|---|---|
| `id` | UUID | `UUID()` | 工具库 ID | ✅ 进 `ToolRecord.id` | ❌ |
| `name` | `String` | 必填 | 工具名 | ✅ | ❌ |
| `executablePath` | `String` | 必填 | T0 不读、T1 cwd 不读 | ✅（用户已确认） | ❌ |
| `workingDirectoryPath` | `String?` | `nil` | T0/T1 不读 | ❌（本地敏感） | ❌ |
| `commandTemplate` | `String` | `name`（fallback） | T0/T1 不读 | ✅（用户已确认） | ❌ |
| `toolDescription` | `String` | `""` | T0/T1/T2 不读 | ✅ | ❌ |
| `categoryRawValue` | `String` | `ToolCategory.other.rawValue` | T0/T1/T2 不读 | ✅ | ❌ |
| `iconSymbol` | `String` | `"terminal"` | T0/T1/T2 不读 | ✅ | ❌ |
| `iconStyleIdentifier` | `String?` | `nil` | T0/T1/T2 不读 | ✅ | ❌ |
| `customIconFilename` | `String?` | `nil` | T0/T1/T2 不读 | ❌（本地受控 PNG 路径） | ❌ |
| `iconURLString` | `String?` | `nil` | 永远为 `nil`（来源与可信度已替代）| ❌（永不导出/恢复）| ❌ |
| `repositoryFullName` | `String?` | `nil` | T0/T1/T2 不读 | ✅ | ❌ |
| `installationSourceRawValue` | `String?` | `ToolInstallationSource.detect(...)` | T0/T1/T2 不读 | ✅ | ❌ |
| `metadataProvenanceRawValue` | `String?` | `"local"` 或 `"manual"` | T0/T1/T2 不读 | ✅ | ❌ |
| `metadataMatchConfidence` | `Int?` | `0` | T0/T1/T2 不读 | ✅ | ❌ |
| `metadataUpdatedAt` | `Date?` | `nil` | T0/T1/T2 不读 | ✅ | ❌ |
| `isFavorite` | `Bool?` | `false` | T0/T1/T2 不读 | ✅ | ❌ |
| `isUserCustomized` | `Bool` | `false` | T0/T1/T2 不读 | ✅ | ❌ |
| `isHidden` | `Bool` | `false` | T0/T1/T2 不读 | ✅ | ❌ |
| `variableValuesJSON` | `String?` | `nil` | T0/T1 不读 | ❌（本地敏感，由用户在导出时勾选） | ❌ |
| `lastLaunchedAt` | `Date?` | `nil` | T1 不读 | ✅ | ❌ |
| `createdAt` | `Date` | `Date()` | T0/T1/T2 不读 | ✅ | ❌ |

## 7. CandidateTool 字段表（T0/T1/T2 不读，仅作记录）

| 字段 | 类型 | 进 JSON 备份 |
|---|---|---|
| `id` | UUID | ✅ |
| `name` | `String` | ✅ |
| `executablePath` | `String` | ✅ |
| `categoryRawValue` | `String` | ✅ |
| `statusRawValue` | `String` | ✅ |
| `installationSourceRawValue` | `String?` | ✅ |
| `discoveredAt` | `Date` | ✅ |

**注：** T0/T1/T2 路径不引用 `CandidateTool`（仅 `LaunchpadView.performScan` 收件箱流用）。列出仅为完整覆盖项目所有 SwiftData 实体。

## 8. 跨入口字段语义不变性

**关键不变量**（任何 commit 不得破坏）：

1. **T0 入口**（`Sources/TaskPolicyWorkbenchView.swift`）写入的 5 个字段（`projectScopeID` / `kindRawValue` / `riskRawValue` / `stateRawValue` / `nonce` / `proposedAt` / `expiresAt`）必须**与** T2 MCP 读取的对应字段**语义一致**。
2. **T1 入口**（`Sources/TaskExecutionService.swift`）写入的 4 个执行字段（`executionStateRawValue` / `executionStartedAt` / `executionFinishedAt` / `executionExitCode`）必须**与** T2 MCP 读取的 `executionState` / `exitCode` **一一对应**。
3. **JSON 备份**（`Sources/BackupService.swift:159-171`）`TermiPadBackup.make(tools:candidates:...)` 的两个参数**类型上是 `tools: [TerminalTool]` 和 `candidates: [CandidateTool]`**——`TaskProjectScope` / `TaskReviewWindow` / `TaskIntent` **类型上不可能进入**。这是 §4.5 迁移与备份决定的类型系统级保证。
4. **T2 MCP 响应**（`Sources/TaskMCPBridge.swift:201-211`）只构造 8 字段的 `LocalMCPTaskState`——不含命令/路径/变量/进程输出。

## 9. 引用关系图

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

## 10. 维护规则

- **任何新增 SwiftData 实体或字段**：必须更新本文件 §3-§7 + §8 不变量。
- **任何修改 `Sources/BackupService.swift:159-171` 的 `TermiPadBackup.make` 签名**：必须保留 §8 第 3 条不变量。
- **任何修改 `Sources/TaskMCPBridge.swift:201-211` 的 `LocalMCPTaskState` 构造**：必须保留 §8 第 4 条不变量。
- **本文件 commit 必须与代码同步**——代码改了但本文件没改 = 不完整 commit。
