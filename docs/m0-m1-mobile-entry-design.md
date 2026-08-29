# TermiPad M0 / M1 移动端入口设计

**来源：** 对齐 `docs/product-roadmap.md` §5 阶段 4 "M0/M1 — 原生 iPhone App 产品与同网配对" + `docs/t0-development-preparation-checklist.md` §6 第 1 行 "原生 iPhone 同网配对：真实 iPhone、真实 Mac、局域网、系统本地网络权限"。

**状态：** 阶段 2 接手 commit 2.1（2026-08-29，zcode）。**纯设计文档**——无代码改动，无运行时代码修改。

**作用范围：** M0 = TermiPad 内部为每个工具加 6 个用户控制字段（默认全关）的本地原型。**M0 完成后**才能考虑 M1 同网配对实现。**M0 不需要外部条件**（无 iPhone、无 Apple Developer 账户、无 Bonjour）；**M1 启动需要 G4 闸门**（真实 iPhone + 真实 Mac + 局域网 + 系统本地网络权限）。

**红线继承**：`product-roadmap.md` §7 "不可妥协的产品红线"——Mac 不开放公网终端、无任意远程 Shell、命令不可被 AI 改写、最小数据回传、每个权限可撤销、本地优先、不替代专业远程终端。本设计**全文不越线**。

## 1. M0 / M1 / M2 / M3 在 product-roadmap 的位置

`product-roadmap.md` §5 阶段 4-7 给出完整路径。本文档只覆盖 M0 + M1：

| 阶段 | 名称 | 状态 | 启动条件 |
|---|---|---|---|
| 阶段 0-3 | Mendocino 核心 / P0 / P1 / P2 / T0 / T1 / T2 / 图标 | ✅ 完成 | — |
| **阶段 4: M0/M1** | 原生 iPhone App + 同网配对 | ❌ 未开始 | M0：无；M1：G4（真机 + 局域网 + Apple 开发者账户）|
| 阶段 5: M2 | 异地安全会话 | ❌ 未开始 | G5（双设备 + 会话服务 + 攻击面审计）|
| 阶段 6: M3 | 远程允许窗口 | ❌ 未开始 | M2 稳定 + 真实使用反馈 |
| 阶段 7 | 发行与生态（Developer ID / 公证 / Gatekeeper） | ❌ 未开始 | Apple 开发者账户 + 真实旧 store 升级 |

**M0 完成的判定** = `feature/track-protocol-materials` 阶段 1 commit `414a417` 之后**新增**一个 `feature/m0-implementation` 分支（独立于 `m0-m1-design`），含 3-5 commit 实现 M0 字段 + 守卫 + 测试。M0 **不**等价于 M1 可启动——见 §6 G4 闸门。

## 2. M0：Mac 本地移动入口原型

### 2.1 目标

在 TermiPad 的工具编辑面板为**每个工具**加 6 个用户控制字段（默认全关）。**完成 M0 后**：用户在 Mac 上能精确决定"哪个工具允许出现在手机端 / 是否允许手机发起启动 / 是否需要本地确认"。**完成 M0 不需要**任何外部条件（无 iPhone、无 Bot、无 HTTPS 域名、无 Apple 账户）。

**M0 是所有移动端入口的共享地基**——无论后续选 iPhone 主线、Telegram 备线还是 PWA 验证层，6 字段策略层都复用。**M0 完成后** M1（iPhone）或 Telegram 专项 M1（静态 HTTPS 页面）可基于这层策略层启动。

### 2.2 数据模型：在 `Sources/TerminalTool.swift` 加 6 字段

依据 `docs/task-intent-data-dictionary.md` §6 的 `TerminalTool` 字段表，**新增 6 字段**：

| 字段 | 类型 | 默认 | 语义 |
|---|---|---|---|
| `mobileDisplayName` | `String?` | `nil`（用本地 `name`） | 手机端显示名（短、与本地 `name` 可不同）|
| `mobileDescription` | `String` | `""` | 用途说明，**严禁**含命令/路径/变量；客户端展示前服务端脱敏 |
| `showInMobileEntry` | `Bool` | **`false`** | 是否进入手机目录的最小化列表 |
| `allowMobileLaunchRequest` | `Bool` | **`false`** | 允许手机对**已批准图标**发起启动请求 |
| `mobileLocalConfirmPolicy` | `enum MobileLocalConfirmPolicy` | `.everyTime` | 本地确认策略（见 §2.3）|
| `revokeMobilePermissionAt` | `Date?` | `nil` | 立即撤销时间戳，点了"撤销"按钮写入 |

**与现有字段的关系**：6 字段**不**替代或修改 `name` / `executablePath` / `commandTemplate` / `variableValuesJSON` / `workingDirectoryPath` / `customIconFilename` / `iconURLString` / `metadataProvenance*` 等任何已有字段。**M0 是叠加层**。

**红线约束**（与 `docs/task-intent-data-dictionary.md` §6 一致）：
- 6 字段**永不**进 JSON 备份（与 `workingDirectoryPath` / `customIconFilename` 一致——见 §2.5）
- 6 字段**不**进诊断事件（除了专门加的 `taskProposalExpiringSoon` 这类审计事件——目前**不**记录 M0 字段读/写，因为字段本身是 UI 设置，不是 task 生命周期）
- 6 字段**不**通过 T2 MCP 回传（`LocalMCPTaskState` 8 字段白名单固定，不增 M0 字段）

### 2.3 枚举 `MobileLocalConfirmPolicy`

```swift
enum MobileLocalConfirmPolicy: String, Codable, CaseIterable, Sendable {
    /// 每次手机请求都要求 Mac 本机用户在工作台点击确认
    case everyTime
    /// 同一会话内（≤5min）不重复确认；新会话或超时会话必须重确认
    case perSession
    /// 仅 5min 内的会话，且任务风险为 .low；其他情况要求重确认
    case lowRiskSessionOnly
}
```

**为什么是 3 个 case**：原方案 §1 红线 "每个权限可撤销" 暗示确认策略不能 "永久允许"；`perSession` 与 `lowRiskSessionOnly` 都依赖会话超时 = 强制重确认，**没有** 永不过期选项。`everyTime` 是最严格默认。

### 2.4 工具编辑面板 UI：新增 "手机入口" Section

在 `Sources/LaunchpadView.swift` 的 `ToolEditView`（875-1118 行）追加 Section：

```
工具编辑
├── 基本信息（已有）
├── 启动命令（已有）
├── 整理（已有）
├── 工具状态（已有）
├── 工作目录（已有）
├── 自定义图标（已有）
├── **手机入口**（M0 新增）
│   ├── 手机显示名称 (TextField)
│   ├── 手机说明 (TextField, vertical 2-4 line)
│   ├── 在手机入口显示 (Toggle, default off)
│   ├── 允许手机发起启动请求 (Toggle, default off, gated by 上一项)
│   ├── 本地确认策略 (Picker: everyTime / perSession / lowRiskSessionOnly)
│   └── [撤销手机权限] (Button, role: .destructive, sets revokeMobilePermissionAt = now)
├── 图标选择（已有）
└── 来源与可信度（已有）
```

**accessibility identifier**：`tool-mobile-entry-section` / `tool-mobile-show-in-entry` / `tool-mobile-allow-launch` / `tool-mobile-confirm-policy` / `tool-mobile-revoke`。

**撤销按钮**（`revokeMobilePermissionAt`）：**不是隐藏字段**——是 destructive 按钮，**点击立即**写 `Date()` 进 `revokeMobilePermissionAt`，**清零** `allowMobileLaunchRequest` 与 `showInMobileEntry`（双重保护：撤销时间戳 + 字段都关）。撤销后用户**可以**重新勾选（撤销**不**是永久黑名单，是"立即撤回当前会话状态"）。

### 2.5 备份与隐私（与 `docs/task-result-minimal-spec.md` §2 一致）

6 字段**永不出 JSON 备份**。**`Sources/BackupService.swift` 类型签名已保证**——`TermiPadBackup.make(tools:candidates:...)` 只接受 `[TerminalTool]`，`TermiPadBackup.ToolRecord.init(tool:includeSavedVariableValues:)` 在 commit 1.5 后**不会**复制 6 字段。

**验证**（`Tests/TermiPadTests/BackupServiceTaskExclusionTests.swift` 已建立的模式）：M0 实现后新增 `BackupServiceMobileFieldExclusionTests.swift` 断言 JSON **不**含 6 字段名。

**verify-macos.sh 静态守卫**（commit 1.5 模式）：M0 实现后新增 `mobile_entry_code` 块，要求 `Sources/BackupService.swift` **不**含 `mobileDisplayName` / `mobileDescription` / `showInMobileEntry` / `allowMobileLaunchRequest` / `mobileLocalConfirmPolicy` / `revokeMobilePermissionAt` 任何字段名。

### 2.6 诊断事件（与 `docs/task-result-minimal-spec.md` §4 一致）

M0 **不**新增 `DiagnosticEventKind`。**为什么**：
- 6 字段是 UI 设置，非 task 生命周期事件
- 现有的 `taskExecutionResultRead` 也不含 M0 字段
- 撤销按钮 click 是 UI 行为，不是 task 行为——记诊断会污染审计语义

**唯一新增**：撤销按钮触发时**写 1 个新 `DiagnosticEventKind.mobilePermissionRevoked`**（commit 2.x 阶段如果进 M0 实现时可加）。**M0 设计阶段不预判**——留给实现 commit 决定。

### 2.7 M0 完成度门槛

| 验证项 | 形式 |
|---|---|
| 6 字段持久化 | `MobileEntryTests.swift`：SwiftData round-trip |
| 6 字段默认 false/nil/everyTime | `MobileEntryTests.swift` |
| 6 字段不进 JSON 备份 | `BackupServiceMobileFieldExclusionTests.swift` |
| `Sources/BackupService.swift` 静态守卫 | `verify-macos.sh` `mobile_entry_code` 块 |
| UI Section 可见 + 撤销按钮 | `TermiPadUITests.swift` 新增场景 |
| 全量 `verify-macos.sh` 绿 | baseline `.verification/<时间戳>/summary.md` |

## 3. M1：本地网络配对

### 3.1 启动条件（G4 闸门）

`docs/t0-development-preparation-checklist.md` §6 第 1 行 + `docs/product-roadmap.md` §8 G4："原生 iPhone 同网配对在真实两设备上测试通过 — 未开始；受 Apple 设备/签名条件影响。"

| 闸门 | 含义 | 当前状态 |
|---|---|---|
| Apple Developer Program 账户 | 真机调试 + 局域网 NSLocalNetworkUsageDescription 权限 | ❌ 未具备 |
| 真实 iPhone | 物理 iPhone，running iOS 16+（与 macOS 14 同步）| ❌ 未具备 |
| 真实 Mac（已具备） | 当前开发机即可 | ✅ |
| 局域网 | 同一 Wi-Fi、Bonjour 可发现 | ❌ 取决于上面 2 项 |

**M0 完成 ≠ M1 可启动**。M0 是 Mac 本地工作，**不**依赖 G4。**M1 设计可以现在写**（commit 2.1），**M1 实现必须等 G4 闸门具备后再开新分支**。

### 3.2 选型：Network framework + Bonjour + 本地 TLS

**为什么不是** WebSocket / NFS / iCloud / 第三方推送：
- WebSocket：**需要服务器**——TermiPad 是不开放公网的本地 app
- NFS：macOS 文件共享协议，**不是为了 RPC**
- iCloud：依赖 Apple Developer 账户 + 真实多设备——**和 G4 同样阻塞**
- 第三方推送（APNs/FCM）：**必须经过 Apple/Google 服务器**——违反红线

**为什么是** Network framework + Bonjour + 本地 TLS：
- Network framework 是 macOS 14+ 现代网络 API（替代 BSD sockets）
- Bonjour（mDNS）**正是**为 LAN 设备发现设计——iPhone 和 Mac 同 Wi-Fi 互找不需要服务器
- 本地 TLS 1.3 防止同 Wi-Fi 嗅探；自签证书双方首次互验（Mac 显示 fingerprint 让用户在 iPhone 输入）

### 3.3 配对流程

```
iPhone App (远期)                 Mac (TermiPad)
       │                              │
       │ 1. 打开 iPhone app, 输入 Mac LAN 主机名 (或扫码)
       │ ─────────────────────────────────────────────►
       │                              │
       │                          2. Bonjour 发现 iPhone
       │                          3. iPhone 发起 TLS 1.3 握手
       │ ◄─────────── TLS 握手 + 自签证书 ──────────
       │                              │
       │ 4. iPhone 显示 Mac 提供的 fingerprint (e.g. "AB12:CD34:...")
       │    用户在 iPhone 输入/确认 fingerprint
       │ ──────── 已验证 fingerprint (SHA-256) ──────►
       │                              │
       │                          5. 双方交换：
       │                          - Mac: 推送公钥 + 短期 nonce
       │                          - iPhone: 推送公钥 + 短期 nonce
       │                              │
       │ 6. 双方各保存对方公钥 + nonce + paired-device ID
       │    (Keychain on iPhone, SwiftData + Keychain on Mac)
       │                              │
       │ 7. 配对完成, iPhone 可以请求"列出工具" + "启动工具"
       │                              │
       ▼                              ▼
```

**关键点**：
- 配对**只发生一次**——后续通讯用双方公钥 + 短期会话密钥
- **fingerprint 必须** 由用户在 iPhone 上**人工**确认——这是抗中间人攻击的关键
- 配对后 iPhone 在 `PairedDevice` 列表里——可**在 Mac 工作台撤销**（**必须**有撤销路径，§7 红线"每个权限可撤销"）

### 3.4 M1 数据模型（待 G4 后实现）

```swift
@Model final class PairedDevice {
    var id: UUID
    var displayName: String           // iPhone 配对时填的
    var publicKeyHash: String          // 配对时 iPhone 公钥的 SHA-256
    var lastConnectedAt: Date?
    var createdAt: Date
    var revokedAt: Date?               // 撤销时间戳
    var pairedFromScope: TaskProjectScope?  // 可选：限制 iPhone 只能触发某个 scope 的 task
}

enum PairedDeviceOperation: String, Codable {
    case listTools                // 列出 showInMobileEntry=true 的工具
    case requestLaunch            // 对 allowMobileLaunchRequest=true 发起启动
    case listScopes               // 列出 task scope (TaskProjectScope.displayName + availability)
    case listFixedTasks           // 列出 FixedTaskCatalog.definitions
    case requestTaskProposal      // 发起 task proposal (需本地确认)
    case getTaskStatus            // 读 task 状态
    case cancelTask               // 取消未启动 task
    case heartbeat                // 30s 一次
}
```

**PairedDevice + 5 个旧 case 是 M1 引入的"操作白名单"——任何 iPhone 请求必须 match 这个 enum，否则拒绝**。这与 `Sources/TaskMCPBridge.swift:5-12` 的 `LocalMCPBridgeOperation` 5 个 case 设计一致。

### 3.5 验证 M1

M1 的验证**不能**在 Mac 端单边完成——必须有真机 iPhone：

| 验证项 | 形式 | 闸门 |
|---|---|---|
| Bonjour 发现 | 同一 LAN iPhone + Mac 互发现 | G4（真机）|
| TLS 握手 | fingerprint 互验 | G4 |
| 配对成功 | `PairedDevice` 持久化 | G4 |
| 撤销路径 | 用户在 Mac 工作台撤销 → iPhone 立即无响应 | G4 |
| 启动请求 | iPhone 点图标 → Mac 工作台弹确认 → 用户确认 → `TerminalLauncher.launch` | G4 + `mobileLocalConfirmPolicy` |

**M1 实施必须在 G4 闸门具备后**——`docs/post-takeover-plan.md`（commit 2.2）会显式列出 G4 状态。

## 4. M0 vs M1 实现路径

| 阶段 | 工作 | 分支 | 预计 commit | 阻塞 |
|---|---|---|---|---|
| M0 设计 | 本文 (commit 2.1) | `feature/m0-m1-design` | 1 | 无 |
| M0 实现 | 数据模型 + 枚举 + 工具编辑 UI + 备份守卫 + 单测 + UI 测试 | `feature/m0-mobile-entry-prototype` | 3-5 | 无（**不依赖 G4**）|
| M1 设计 | 选型 (Network/Bonjour/TLS) + 配对流程 + 数据模型 + 验证方案 | `feature/m0-m1-design`（本文档 §3）| 1 | 无 |
| M1 实现 | 配对 API + TLS 握手 + PairedDevice + iPhone app | `feature/m1-local-network-pairing` | 5-10 | **G4 闸门** |
| M2 设计 + 实现 | 出站长连接 + 会话模型 | `feature/m2-remote-secure-session` | 10+ | **G5 闸门** |

## 5. 与原方案 §4 已补强材料的关系

M0 启动依赖**已完成的**阶段 1 全部 commit：

| 阶段 1 commit | M0 依赖 |
|---|---|
| §4.1 数据字典 (`docs/task-intent-data-dictionary.md`) | 6 字段作为 §6 "TerminalTool 字段表" 的扩展，文档同步更新 |
| §4.4 最小结果规范 (`docs/task-result-minimal-spec.md`) | M0 6 字段不进入 T2 MCP 回传白名单；新增守卫保证 |
| §4.5 迁移与备份决定 (commit `6b931c4`) | M0 6 字段不进入 JSON 备份——新守卫的扩展基线 |

**M0 实现 commit 应**：
1. 在 `Sources/TerminalTool.swift` 加 6 字段
2. 在 `docs/task-intent-data-dictionary.md` §6 "TerminalTool 字段表" 加 6 行
3. 在 `docs/task-result-minimal-spec.md` §4 审计 event 表加 1 行（撤销按钮 event）
4. 在 `scripts/verify-macos.sh` 新增 `mobile_entry_code` 块
5. 新增 `Tests/TermiPadTests/MobileEntryTests.swift` + `BackupServiceMobileFieldExclusionTests.swift`
6. 新增 1 个 UI 场景（打开工具编辑面板 + 看到手机入口 section）

## 6. G4 闸门现状

**当前未具备**。G4 闸门要求：
- Apple Developer Program 账户（年费 $99）—— 用户决定
- 真实 iPhone 物理设备（项目维护者持有）—— 用户决定
- 同一局域网环境（家庭/办公室 Wi-Fi 即可）—— 用户决定

**M1 启动决策树**：
- G4 闸门具备 → 开 `feature/m1-local-network-pairing` 分支 → 按 §3 实施
- G4 闸门不具备 → 暂不启动 M1 → 维护 `docs/post-takeover-plan.md`（commit 2.2）反映现状

## 7. 红线再次确认

任何 M0/M1 实现**必须**满足 `docs/product-roadmap.md` §7：

| 红线 | M0/M1 实现如何满足 |
|---|---|
| Mac 不开放公网终端 | M1 用 Bonjour 局域网发现，**不**监听公网端口 |
| 无任意远程 Shell | PairedDeviceOperation enum 5 个 case 固定白名单 |
| 命令不可被 AI 改写 | iPhone 只能从 `showInMobileEntry=true` 的工具发起启动，命令是 Mac 已保存的 `commandTemplate` |
| 最小数据回传 | iPhone 收到的 `listTools` 响应**不**含命令/路径/变量——只含 `id` / `mobileDisplayName` / `mobileDescription` / 图标标识 |
| 每个权限可撤销 | `PairedDevice.revokedAt` + `TerminalTool.revokeMobilePermissionAt` 双重撤销 |
| 本地优先 | 所有数据存 Mac SwiftData，6 字段不外发 |
| 不替代专业远程终端 | iPhone 只能"启动"已有工具，**不**能输入任意命令 |

## 8. 维护规则

- 任何 M0 实现 commit 必须**同步更新** §5 列出的 5 份材料
- 任何 M1 启动 commit 必须先在 `docs/post-takeover-plan.md`（commit 2.2）确认 G4 闸门状态
- 任何后续发现 G4 闸门不具备的 commit，**先**在本文 §6 更新，**后**写代码
