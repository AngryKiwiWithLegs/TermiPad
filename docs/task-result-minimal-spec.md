# TermiPad 最小结果规范（t0-checklist §4.4）

**来源：** 对齐 `docs/t0-development-preparation-checklist.md` §4 第 4 行 "最小结果规范 — 防止 stdout/stderr 被不加区分地输送给手机或智能体 — 结构化状态与摘要字段逐项审计"。

**状态：** 接手 commit 1.4（2026-08-29，zcode）。本文档是 `Sources/TaskIntent.swift` 中 3 个枚举（`TaskIntentState` / `TaskExecutionState` / `TaskRejectionReason` / `TaskExecutionRejectionReason`）的回传白名单显式化。

**作用范围：** 任何 T0 工作台、T1 执行器读取、T2 MCP 桥接、未来 PWA/Telegram/iPhone 入口读取 task 结果时，**只能**回传本文档 §2 白名单字段。**不能**回传命令、路径、变量、stdout、stderr。

## 1. 状态枚举（来自 `Sources/TaskIntent.swift`）

| 枚举 | 行号 | 取值数量 | 用途 |
|---|---|---|---|
| `TaskIntentState` | 25-32 | 6 | 提案在策略层的状态机：`pendingReview` / `approved` / `rejected` / `expired` / `revoked` / `cancelled` |
| `TaskExecutionState` | 35-44 | 8 | 执行器返回的执行生命周期：`notStarted` / `running` / `succeeded` / `failed` / `timedOut` / `stopped` / `startRejected` / `startFailed` |
| `TaskRejectionReason` | 55-65 | 9 | 策略层拒绝路径：`unknownTaskKind` / `projectScopeUnavailable` / `localReviewRequired` / `reviewWindowExpired` / `riskNotPermitted` / `nonceReplayed` / `taskExpired` / `taskNotPending` / `taskCancelled` |
| `TaskExecutionRejectionReason` | 46-53 | 6 | 执行层"开始"被拒路径：`intentNotApproved` / `intentExpired` / `taskAlreadyStarted` / `projectScopeUnavailable` / `taskDefinitionUnavailable` / `taskPreflightFailed` |

## 2. 最小结果白名单（每个状态可回传哪些字段）

### 2.1 `TaskIntent` 主体字段（`Sources/TaskIntent.swift:127-199`）

| 字段 | 可回传 | 红线 |
|---|---|---|
| `id` | ✅ | 不透明 UUID 即可，**不**回传内部递增 ID |
| `projectScopeID` | ✅ | 同上 |
| `kindRawValue` | ✅ | 必须 ∈ `TaskKind.allCases`（固定 3 个） |
| `riskRawValue` | ✅ | `low` / `standard` |
| `stateRawValue` | ✅ | 6 个枚举值之一 |
| `nonce` | ✅ | 仅用于本地重放防御审计；**不**回传用户 |
| `proposedAt` | ✅ | 时间戳 |
| `expiresAt` | ✅ | 时间戳 |
| `approvedAt` | ✅ | 时间戳（如果已批准） |
| `resolvedAt` | ✅ | 时间戳（如果已解决） |
| `rejectionReasonRawValue` | ✅ | 9 个枚举值之一（如果被拒） |
| `executionStateRawValue` | ✅ | 8 个枚举值之一（如果已执行） |
| `executionStartedAt` | ✅ | 时间戳 |
| `executionFinishedAt` | ✅ | 时间戳 |
| `executionExitCode` | ✅ | 0-255 整数 |
| `executionRejectionReasonRawValue` | ✅ | 6 个枚举值之一（如果执行被拒） |

### 2.2 `TaskProjectScope` 字段（`Sources/TaskIntent.swift:68-90`）

| 字段 | 可回传 | 红线 |
|---|---|---|
| `id` | ✅ | |
| `displayName` | ⚠️ **仅元数据** | `Sources/TaskMCPBridge.swift:127-128` 已截断至 80 字符，且**替换 `\n` 为空格**（防日志注入） |
| `rootPath` | ❌ **永不** | macOS 路径、用户项目结构——**永不出本机** |
| `isRevoked` | ✅ | 布尔 |
| `createdAt` | ✅ | |
| `revokedAt` | ✅ | |

**T2 MCP 实际回传字段**（`Sources/TaskMCPBridge.swift:130-140` 的 `LocalMCPScopeSummary`）：只 `scopeID` / `displayName` (80 char) / `status` (3 枚举值：`revoked` / `available` / `unavailable`)。**`rootPath` 不在此结构体里**。

### 2.3 T2 MCP 实际响应字段（`Sources/TaskMCPBridge.swift:201-211` `summary(for:)`）

| 字段 | 类型 | 用途 |
|---|---|---|
| `taskID` | UUID | 不透明 |
| `taskKind` | String | ∈ TaskKind.allCases |
| `risk` | String | `low` / `standard` |
| `state` | String | ∈ TaskIntentState 6 值 |
| `executionState` | String | ∈ TaskExecutionState 8 值（可能 nil） |
| `exitCode` | Int? | 0-255 |
| `executionReason` | String? | ∈ TaskRejectionReason / TaskExecutionRejectionReason |
| `expiresAt` | ISO8601 String | 时间戳 |

**`LocalMCPTaskState` 8 字段的代码事实** = 本规范白名单 = 任何 T2 MCP 客户端能看到的全部。

## 3. 红线（绝对不进入任何外部协议）

| 数据 | 永不外发 | 来源 |
|---|---|---|
| **`rootPath` / `workingDirectoryPath`** | 路径即用户身份 | `Sources/TaskIntent.swift:71`、`Sources/TerminalTool.swift:423` |
| **`commandTemplate` / `executablePath`** | 命令即执行能力 | `Sources/TerminalTool.swift:421-424` |
| **`variableValuesJSON`** | 变量值含 token / 凭据 | `Sources/TerminalTool.swift:443` |
| **`customIconFilename`** | 本地受控 PNG 路径 | `Sources/TerminalTool.swift:432` |
| **`iconURLString`** | 永不写入、永不回填（`Sources/TerminalTool.swift:433`） | `Sources/BackupService.swift:48,71,101` |
| **`Process.standardOutput` / `standardError`** | 任何任务输出 | `Sources/TaskExecutionService.swift:139-141` 用 `FileHandle.nullDevice` 屏蔽 |
| **API Key** | Keychain only | `Sources/KeychainStore.swift:6` |
| **完整 stdout/stderr** | 永不持久化、绝不回传 | `Sources/TaskExecutionService.swift:139-141` + 本文 §2.3 |

## 4. 审计 event 映射（commit 1.4 同时新增 2 个）

`Sources/DiagnosticsService.swift:6-43` 的 `DiagnosticEventKind` 包含 45 个事件。task 域相关：

| 事件 | 触发位置 | 审计意义 |
|---|---|---|
| `taskProposalCreated` | T0 工作台 + T2 MCP | 提案被创建 |
| `taskReviewWindowOpened` | T0 工作台 | 用户主动开窗 |
| `taskPolicyApproved` | T0 工作台 + T2 MCP 审批 | 策略层允许 |
| `taskPolicyRejected` | T0 工作台 + T2 MCP 审批 | 策略层拒绝（9 个 reason） |
| `taskCancelled` | T0 工作台 + T2 MCP 取消 | 主动取消 |
| `taskScopeRevoked` | T0 工作台 | 用户撤销 scope |
| `taskExecutionStarted` | T1 执行器 | process run() 成功 |
| `taskExecutionSucceeded` | T1 执行器 | exit 0 |
| `taskExecutionFailed` | T1 执行器 | exit ≠ 0 |
| `taskExecutionStopped` | T1 执行器 | 用户主动 stop |
| `taskExecutionTimedOut` | T1 执行器 | timeout 触发 |
| `taskExecutionRejected` | T1 执行器 | 开始时 .rejected |
| `taskExecutionStartFailed` | T1 执行器 | process.run() 抛错 |
| **`taskExecutionResultRead`**（**新增**） | T2 MCP 读 task 状态 | task 域审计，与 `.mcpTaskStatusRead` 互补 |
| **`taskProposalExpiringSoon`**（**新增**） | T0/T2 读 task 时检查 expiresAt-60s 边界 | 即将过期前给工作台提示用 |
| `mcpToolListed` | T2 MCP `tools/list` | MCP 客户端枚举工具 |
| `mcpTaskProposed` | T2 MCP `propose_task` | MCP 客户端发起提案 |
| `mcpTaskStatusRead` | T2 MCP `get_task_status` | MCP 协议层审计 |
| `mcpTaskCancelled` | T2 MCP `cancel_task` | MCP 客户端取消 |

**双层审计**（commit 1.4 实现）：T2 MCP 读 task 状态时**同时**记 `.mcpTaskStatusRead`（协议层）和 `.taskExecutionResultRead`（task 域）。两次记录是独立的——可分别分析"MCP 客户端总流量"与"task 状态被查询频率"。

## 5. 维护规则

- **新增 T0/T1/T2 任何入口**：必须更新 §2 白名单——**只能**把已有字段加进白名单，**不能**新建字段到 `LocalMCPTaskState` 而不在本文登记。
- **新增 `DiagnosticEventKind`**：必须在 §4 表里加一行，写明触发位置 + 审计意义。
- **新增状态枚举值**（如 `TaskIntentState` 加 `.paused`）：必须更新 §1 + §2 表格 + 任何断言测试。
- **本文件 commit 必须与代码同步**——代码改了但本文件没改 = 不完整 commit。
