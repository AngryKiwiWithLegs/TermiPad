# M2b 远程任务会话设计——手机端 zcode 标准体验 + 失窃四道防线

**状态：** 设计评审稿（2026-09-09）。先评审后实现；本文不宣称任何能力已实现。

**上位文档：** `docs/product-roadmap.md` §5 阶段 5（M2）与 §8 移动端入口决策；`docs/m2-secure-remote-session-design.md`（M2a 隧道——本批次传输层原样复用）；`docs/m0-m1-mobile-entry-design.md`（配对/加密/撤销层）。

**用户拍板（2026-09-09）：** 产品体验对齐 zcode 标准——手机端必须能看到任务交互界面、能执行任务（不要求终端仿真界面）；安全上接受四道防线架构，让偷手机的人无法执行。受限任务模型（固定任务目录 + 项目范围 + 时限 + 可停止）保留：手机提交的是"任务建议引用"（kind + scope），永远不是自由命令。

## 1. 目标与体验形态

北极星场景的完整实现：用户在外面，手机上是**任务会话**（task console）：

```
┌─ 手机端任务会话 ─────────────────────────────┐
│ 会话条目流（工具启动 + 固定任务，统一时间线）    │
│  ▶ swift test    succeeded  exit 0   12:31    │
│  ▶ 构建工具      launched           12:29     │
│  [+ 新任务] → 选范围 → 选固定任务 → 提交        │
│  运行中条目 → [停止]（仅限手机提交的任务）        │
└──────────────────────────────────────────────┘
```

- **看**：会话条目流（标题、状态 8 态、退出码、时间）+ 按输出档位的输出片段
- **执行**：提交固定任务建议（从 Mac 下发的目录里选 kind + scope，两段引用）→ Mac T0/T1 策略核验 → 执行
- **停止**：取消自己提交的运行中任务
- **更新机制**：手机轮询 `getTaskStatus`（3 秒间隔，会话活跃时）。任务以分钟计，轮询延迟无感；流式推送帧不进本批次（协议保持请求-响应模型，见 §6）

与 zcode 的唯一刻意差别：跑的是**受控任务**（固定目录 + 项目范围 + 超时 + 可停止），不是任意 shell。手机丢了的攻击者拿到的最大能力 = 点固定任务目录里那 5 个任务并提交——还要过四道防线（§4）。

## 2. 前提与复用（全部已验证）

| 组件 | 状态 | 本批次怎么用 |
|---|---|---|
| M2a 隧道（Tailscale serve + 回环 57148） | G5 真机通过 | 传输层原样复用，零改动 |
| M1 配对/加密/指纹/撤销 | G4 真机通过 | 握手链原样复用 |
| `PairedDeviceOperation` 五个预留 case | M2a 协议预留位 | 本批次激活（§5.1） |
| T0 `TaskIntentPolicy`（makeIntent/review/approve/cancel） | 单测覆盖 9 种拒绝路径 | 手机任务提交的核验核心 |
| T1 `TaskExecutionCoordinator`（8 态生命周期/超时/停止） | 单测 + 实机验证 | 手机任务的执行核心 |
| M1.1 `MobileLaunchSession`（5 分钟白名单） | 真机通过 | 确认档位推广到任务提交（§5.3） |

## 3. 协议增量（零破坏，decodeIfPresent 纪律）

### 3.1 请求载荷扩展

`MobilePairingRequest` 增加三个可选字段（旧手机/Mac 双向兼容，`decodeIfPresent` 自定义解码——测试锁）：

```swift
struct MobilePairingRequest: Codable {
    let operation: PairedDeviceOperation
    let requestID: UUID
    let toolID: UUID?
    var taskKind: String? = nil       // requestTaskProposal：FixedTaskCatalog 白名单 kind
    var projectScopeID: UUID? = nil   // requestTaskProposal：已登记 scope 的 id（引用，非路径）
    var taskIntentID: UUID? = nil     // getTaskStatus / cancelTask
}
```

**红线不变**：手机仍发不出 command/path/parameter/environment——载荷只有 UUID 与白名单枚举字符串。`MobilePairingProtocolTests` 的 key 集合锁同步更新。

### 3.2 回传结构（Mac → 手机，全部走既有 AEAD 信封）

```swift
/// 项目范围条目：手机只见 id + 显示名，rootPath 永不下发。
struct MobileScopeSummary: Codable {
    let id: UUID
    let displayName: String
}

/// 固定任务目录条目：kind + 双语用途 + 固定命令预览（目录字面量，非用户数据）。
struct MobileFixedTaskSummary: Codable {
    let kind: String
    let purpose: String
    let commandPreview: String
}

/// 会话条目：工具启动与固定任务统一形态。
struct MobileSessionEntry: Codable {
    let id: UUID                  // 工具启动事件 ID 或 TaskIntent ID
    let title: String             // 工具显示名 / 固定任务 purpose
    let kind: String              // "toolLaunch" | "fixedTask"
    let executionState: String    // 统一状态枚举（§3.3）
    let exitCode: Int?
    let startedAt: Date?
    let finishedAt: Date?
    var outputSnippet: String? = nil  // 仅输出档位 ≥ restricted 且任务由 T1 执行时非 nil
}

/// requestTaskProposal 的回执：接受/拒绝 + 任务引用（拒绝文案固定枚举）。
struct MobileTaskProposalResponse: Codable {
    enum Status: String { case accepted, rejected }
    let status: Status
    let reason: String?           // 固定枚举文案，无路径无命令
    let taskIntentID: UUID?       // 接受时手机后续 getTaskStatus/cancelTask 用
}
```

### 3.3 统一状态枚举

T1 的 `TaskExecutionState` 8 态原样字符串下发（notStarted…startFailed）。工具启动（终端交接）只有 launched/launchFailed 两态——会话条目 `kind` 区分，手机端按 kind 渲染状态集。**不新增状态语义**，不发明中间态。

### 3.4 帧与频率

- 所有新消息走既有 4 字节长度前缀帧 + 64 KB 上限；输出片段在帧内截断（§5.4）
- `getTaskStatus` 轮询与既有 `heartbeat` 同级白名单；Mac 端对未配对/已吊销设备一律拒绝（不变）

## 4. 失窃四道防线（本批次的立项核心）

用户拍板：体验对齐 zcode，同时让偷手机的人无法执行。防线压在**失窃后的路径**上，正常使用路径只有 Face ID 一次摩擦。

### 防线 1 · 手机门禁（iOS 端）

| 措施 | 设计 |
|---|---|
| App 锁 | 打开伴侣 app / 切回前台需 Face ID（LAContext，`deviceOwnerAuthentication`；无生物时回落设备密码）。默认开，设置内可关（用户自担）。 |
| 凭据保护 | 配对凭据 Keychain `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`：锁屏后不可读、不随 iCloud 备份迁移、换机不带走。（M1 落地时若用默认 accessible，本批次改并做迁移：旧凭据读出重写一次） |
| 输出不落盘 | 手机端会话条目仅内存 + `@Published`；输出片段不写文件不进快照。切后台超 5 分钟清空输出片段（保留状态摘要）。 |

### 防线 2 · 凭据短命（Mac 端）

- 配对记录带 `pairedAt`；resume 握手时 age > 30 天 → 拒绝 resume，手机端明确文案"配对已过期，请回到同网重新配对"（诊断 `mobilePairingExpired`，仅时间戳）
- 效果：偷手机的人拿到的钥匙最多活 30 天；正常用户 30 天内任意一次同网连接即续命（`pairedAt` 刷新）

### 防线 3 · Mac 侧执行防线（偷手机的人物理上绕不过的）

| 措施 | 本批次 | M3 |
|---|---|---|
| 锁屏拒绝新任务 | ✅ Mac 检测登录会话锁定（`CGSessionCopyCurrentDictionary` 的 `CGSSessionScreenIsLocked`）→ 锁屏期间拒绝一切远程任务提交与工具启动（诊断 `remoteTaskBlockedScreenLocked`） | 同左 |
| 速率限制 | ✅ 每设备每分钟 ≤ 10 次（提交+启动合计）；超限回执拒绝文案固定 | 可调 |
| 确认档位 | ✅ 复用 M1.1 三档推广：任务提交与工具启动同享 everyTime / perSession(5 分钟) / lowRisk 白名单；lowRisk 要求任务 risk == .low | 同左 |
| 每日本机解锁 | — | ✅ 每天第一次远程任务需 Mac 一次点按，此后当天即时 |
| panic code | — | ✅ 预设紧急口令输入即吊销全部移动配对 |

### 防线 4 · 吊销通道（三层，全部即时生效）

1. **Mac 端撤销**（已有）：设置里撤销设备配对——隧道与同网同时断
2. **关隧道开关**（已有）：serve 即撤、白名单即清
3. **Tailscale admin console**（现成，不自建）：用户在任何浏览器登录 Tailscale 账号 → Devices → 踢掉手机 → 隧道即断。**不自建"远程销毁"服务**——自建远程控制通道本身是新攻击面；Tailscale 账户体系已有成熟设备吊销。

### 失窃链路推演（设计自检）

偷手机的人要执行一个任务，依次需要：解锁 iPhone（Face ID）→ 打开伴侣 app 过 app 锁（Face ID 第二次）→ Mac 未锁屏 → 任务过确认档位（everyTime 时 Mac 本机确认，远程拿不到）→ 30 天内 Mac 配对未过期未吊销。其中任意一环失败即终止。**输出泄露面**：即使全部攻破，能读到的只有固定任务的截断输出片段（§5.4 脱敏后）——工具启动（终端交接路径）永无输出回传。

## 5. Mac 端设计

### 5.1 新组件 `MobileTaskConsoleService`（@MainActor ObservableObject）

职责：聚合"会话条目流" + 处理五个新操作 + 输出档位裁决。**唯一新增的 Sources 文件**；配对服务（`MobilePairingService`）收到新操作后全部转交给它，握手/加密/撤销链零改动。

```
MobilePairingService（既有，不动加密与撤销）
   └─ 操作分流 → MobileTaskConsoleService（新）
        ├─ listScopes      → TaskProjectScope 查询（SwiftData）→ [MobileScopeSummary]
        ├─ listFixedTasks  → FixedTaskCatalog → [MobileFixedTaskSummary]
        ├─ requestTaskProposal → §5.2 核验链 → TaskExecutionCoordinator
        ├─ getTaskStatus   → 会话条目流快照（含输出片段裁决）
        └─ cancelTask      → 仅手机提交且 running 的任务 → coordinator.stop
```

### 5.2 requestTaskProposal 核验链（顺序即攻击面检查顺序）

1. 设备配对有效（含 30 天时效）→ 否则拒绝 `pairingExpired`
2. 锁屏检查（防线 3）→ `screenLocked`
3. 速率限制 → `rateLimited`
4. `taskKind` 在 `FixedTaskCatalog`（白名单即攻击面）→ `unknownTaskKind`
5. `projectScopeID` 已登记、未撤销、目录可用 → `projectScopeUnavailable`
6. `TaskIntentPolicy.makeIntent` + `review`（T0 全策略：风险、窗口、nonce、过期）→ 拒绝原因原样映射回执
7. **确认档位**（M1.1 同款三档；everyTime 走 60 秒本机确认弹窗，perSession/lowRisk 命中白名单自动放行 + 诊断 `mobileTaskAutoConfirmed`）
8. `approve` → `TaskExecutionCoordinator.start`（T1 执行：固定 executable、固定参数、超时、可停止、空 stdin）

每步拒绝均写诊断（仅事件枚举 + 时间戳，无任务数据）。回执 `MobileTaskProposalResponse` 拒绝文案为固定枚举中文。

### 5.3 会话条目流

- 内存 ring buffer，最近 50 条；工具启动事件（M1 requestLaunch 链已有）与 T1 任务统一编入；条目 10 分钟后仅保留状态摘要（输出片段清空）
- `getTaskStatus` 返回全量快照（≤50 条，64 KB 帧内）；手机端整个替换渲染

### 5.4 输出捕获与档位（T1 变更，受控放宽）

T1 目前 stdout/stderr 全 nullDevice。本批次改为：**档位 ≥ restricted 时**捕获到**仅内存** ring buffer（上限 32 KB / 400 行，任一先到即停）；档位 minimal 时维持 nullDevice。

| 档位 | 手机能看到 | 缓冲 |
|---|---|---|
| `minimal` | 状态 + 退出码（现状语义） | 不捕获 |
| `restricted`（建议默认） | 末尾 32 行 + 脱敏（§5.5） | 内存，任务结束 10 分钟后清 |
| `full` | 完整缓冲内容（仍受 32 KB 上限与脱敏约束） | 同上 |

- 设置：`TermiPad.remoteOutputVisibility`（UserDefaults，Mac 是权威；MacResumeHello 不带此字段，档位效果由回传内容自然体现）
- **工具启动（终端交接路径）永无输出**——输出到真实终端窗口，本就无从捕获；这条不变
- 红线延续：输出片段不落盘（Mac/手机双端）、不进备份（BackupService 排除）、不进诊断

### 5.5 输出脱敏（restricted/full 通用）

发送前对片段跑固定正则族（字面量硬编码，不读用户配置）：常见 token/password/api-key/Bearer 赋值模式、AWS/GitHub 密钥前缀形态 → 替换为 `••••`。**不自造密码学、不做语义理解**，纯字面量模式匹配；漏脱风险由档位选择兜底（最敏感场景用 minimal）。

## 6. iOS 端设计（CompanionApp）

- **会话页**（新 Tab/主视图）：条目流渲染（状态图标 + 标题 + 退出码 + 时间；运行中带停止按钮）+ 下拉刷新 + 3 秒自动轮询（仅前台活跃时）
- **新任务页**：listScopes → listFixedTasks → 确认提交（显示 purpose + commandPreview + scope 名）
- **App 锁**：`LocalAuthentication`，切前台触发；5 次失败退设备密码
- **凭据迁移**：首次启动检测旧 accessible 属性的 Keychain 记录 → 读出 → 以 `WhenUnlockedThisDeviceOnly` 重写 → 删旧记录
- 输出片段仅内存；后台 > 5 分钟清空（状态摘要保留）

## 7. 新增守卫（进 verify-macos.sh）

1. `LocalAuthentication` import 只允许出现在 CompanionApp/（Mac 端不引入生物识别依赖）
2. `MobilePairingRequest` 编码 key 集合测试锁更新（3 新键，仍禁止 command/path/parameter/environment）
3. `CGSessionCopyCurrentDictionary` 只允许 `MobileTaskConsoleService.swift`（锁屏检测单点）
4. 输出脱敏函数必须有单测（每种模式一例）——restricted 档位上线的前置
5. 既有守卫全部不变（Process 白名单、funnel 禁用、tailscale 单文件、备份排除）

## 8. G6 验收清单（真机，全部通过才宣称 M2b 完成）

| # | 验证项 | 通过标准 |
|---|---|---|
| 1 | 会话可见 | 手机看到 Mac 上的工具启动与固定任务条目流；状态变化 ≤ 3 秒轮询到达 |
| 2 | 任务提交全链 | 异地（蜂窝）手机提交 swift test → （everyTime 时 Mac 确认）→ 状态 running → succeeded + exit 0 |
| 3 | 输出档位 | restricted 默认下手机看到末尾 32 行脱敏输出；minimal 下无输出字段；构造含 fake-token 的任务输出验证脱敏 |
| 4 | 停止 | 手机提交长任务（timeout 180）→ 手机点停止 → 状态 stopped ≤ 3 秒 |
| 5 | App 锁 | 杀 app 重开需 Face ID；锁屏后手机凭据不可读（连不上即证明） |
| 6 | 锁屏拒绝 | Mac 锁屏 → 手机提交任务 → 回执 screenLocked 拒绝文案 |
| 7 | 30 天时效 | 把测试配对 pairedAt 改 31 天 → resume 被拒 + 手机明确文案 |
| 8 | 撤销不变 | Mac 撤销设备 / 关隧道 → 全部新操作即拒（G4 #6/G5 #5 同语义回归） |
| 9 | 红线复核 | 手机全程无 command/path/变量/工具启动输出；备份 JSON 无 taskIntent/scope/输出字段；诊断无任务数据 |

## 9. 与 M3 的衔接

M3（远程允许窗口 + 每日解锁 + panic code）在 M2b 真机体感出来后单独立项设计：`MobileLaunchSession` 推广为 `RemoteAllowWindow`（工具+任务集合、用户设定时长、锁屏/休眠/策略变化立即失效、速率限制集中化）。本批次不预定义其字段。
