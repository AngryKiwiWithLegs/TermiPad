# TermiPad M0 / M1 移动端入口设计

**来源：** 对齐 `docs/product-roadmap.md` §5 阶段 4 "M0/M1 — 原生 iPhone App 产品与同网配对" + `docs/t0-development-preparation-checklist.md` §6 第 1 行 "原生 iPhone 同网配对：真实 iPhone、真实 Mac、局域网、系统本地网络权限"。

**状态：** 阶段 2 接手 commit 2.1（2026-08-29，zcode）。**纯设计文档**——无代码改动，无运行时代码修改。

**2026-09-06 更新（zcode）：** 用户确认用免费 Apple ID（personal team）支撑 M1 真机开发验证——G4 的"开发验证"前提已解锁；"长期安装/TestFlight/外部分发"仍需付费会员（见 §3.1、§6）。M1 实现分支 `feature/m1-local-network-pairing` 同日启动。§3.4 修订：Mac 端配对设备记录改为只存 Keychain（原 SwiftData 方案废弃），理由见该节。

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

| 闸门 | 含义 | 当前状态（2026-09-06）|
|---|---|---|
| 真机安装签名 | 免费 Apple ID（personal team）即可 Xcode 真机调试：每设备 ≤3 app、App ID/设备注册 7 天过期需重签、iPhone 需开启开发者模式；CloudKit/Developer ID/公证/TestFlight 仍是付费专属 | ✅ 解锁（用户已有免费账号；付费会员只在"长期安装/分发/iCloud"时才需要）|
| 真实 iPhone | 物理 iPhone，iOS 16+，开发者模式已开启 | ⚠️ 用户提供 |
| 真实 Mac | 当前开发机即可 | ✅ |
| 局域网 | 同一 Wi-Fi、Bonjour 可发现 | ⚠️ 用户提供 |

**M0 完成 ≠ M1 可启动**。M0 是 Mac 本地工作，**不**依赖 G4。**M1 设计可以现在写**（commit 2.1）。2026-09-06 起开发验证前提已具备——M1 实现分支 `feature/m1-local-network-pairing` 已启动；**双设备真机验收（G4 完成）仍需用户提供真实 iPhone + 局域网**，未实测前不得宣称 G4 通过。

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

### 3.3.1 会话复用协议（2026-09-06 增补，G4 #4-6 的前置）

配对码是一次性的、连接在配对后即断开——重连的已配对手机必须能被 Mac 认出，且无需用户再输码。

**手机端持久化**（配对完成时写入 iOS Keychain，复用 `KeychainStore` 同一 service 域）：
- 自身 X25519 私钥（长期身份，替代首版"每次配对临时生成"）
- Mac 公钥 + Mac 指纹（信任锚点 = 初次配对时人工比对过的那串）
- `deviceID`（Mac ack 下发）

**复用握手**（区别于 §3.3 配对握手：Mac 仍先发 `MacHello`，手机按本地是否有凭据分流）：
1. 手机连接后发 `PhoneResumeHello { protocolVersion, deviceID, phonePublicKey, phoneNonce }`（无 pairingCode 字段——Mac 按字段存在性区分 pairing/resume 两种 hello）
2. Mac 验证：版本钉死；按 `deviceID` 查活跃设备；`SHA256(phonePublicKey) == record.publicKeyHash`——公钥被换即拒绝
3. 双方各派生会话密钥：ECDH + HKDF-SHA256（salt = macNonce ‖ phoneNonce，info = `termipad-m1-resume-v1`，与配对派生不同 info 域）
4. Mac 回**明文** `MacResumeHello { protocolVersion, macPublicKey, macNonce }`（公钥与 nonce 非机密）；手机验证 `SHA256(macPublicKey) == 存储的 Mac 指纹` 后才接受——**双向绑定缺一不可**
5. 之后所有帧 AEAD 加密

**请求通道**（G4 #4-6）：每连接一请求一响应，响应即断开（无长连接、无服务端状态）：
- `listTools` → `[MobileToolSummary]`（仅 `showInMobileEntry == true` 的工具，4 字段白名单不变）
- `requestLaunch` → Mac 按 `mobileLocalConfirmPolicy` 本地确认后经既有终端启动路径执行
- 白名单外操作一律拒绝并断开

### 3.3.2 requestLaunch 启动请求（2026-09-07 增补，G4 #5）

**手机侧**：工具卡点击 → 发 `requestLaunch { toolID }`（加密 resume 通道，与 listTools 同一握手）→ 收到三种结果之一：`accepted`（Mac 用户已确认并交给终端）/ `pendingLocalConfirm`（等待 Mac 用户在 Mac 上确认——手机显示"请在 Mac 上确认"）/ `rejected`（工具未开启 `allowMobileLaunchRequest`，或策略拒绝）。

**Mac 侧执行链**（顺序不可交换）：
1. **资格预检**（MainActor 读 SwiftData）：`showInMobileEntry == true` **且** `allowMobileLaunchRequest == true` **且** `revokeMobilePermissionAt == nil`——任一不满足即 `rejected`，不弹任何确认框
2. **本地确认**（按 `mobileLocalConfirmPolicy`）：
   - `.everyTime`（默认）：每次都弹确认
   - `.perSession` / `.lowRiskSessionOnly`：M1 阶段**一律降级为 everyTime**——会话缓存是后续优化，先收口到最严格
3. **确认 UI**：macOS alert（工具名 + "来自已配对设备 <设备名> 的启动请求"），用户点"启动"才继续；alert 60 秒无响应视为拒绝（防无人值守 Mac 上请求悬挂）
4. **执行**：确认后经既有 `TerminalLauncher` 交给用户所选终端——**不**新增执行路径，命令永远来自 Mac 已保存的 `commandTemplate`
5. **响应**：启动交接完成即回 `accepted`；用户点拒绝或超时回 `rejected`

**红线**：手机端永不收到命令正文/路径/变量/终端输出——只有三种结果枚举。Mac 无人在场（alert 超时）= 拒绝，这是"Mac 始终是唯一执行权威"的直接体现。

**撤销语义**：Mac 撤销设备后，其 `PhoneResumeHello` 在第 2 步被拒（记录 revokedAt 非空即不在活跃集合）——撤销立即对复用生效。

### 3.4 M1 数据模型（2026-09-06 修订）

`PairedDevice` **不再**建 SwiftData 实体——设备记录与配对身份**只存 Keychain**。理由：(a) Keychain 天然不进 JSON 备份，直接满足 §2.5 契约，免去新增备份排除守卫；(b) 公钥指纹与设备身份属于凭据域，与 API Key 同级；(c) 实现为 `Sources/PairedDeviceStore.swift`（`PairedDeviceRecord: Codable` + Keychain 索引账号），存储后端可注入，测试用内存实现不打真实 SecItem（与 `KeychainStoreTests` 纪律一致）。

```swift
struct PairedDeviceRecord: Codable, Sendable, Equatable {
    let id: UUID
    let displayName: String           // iPhone 配对时填的
    let publicKeyHash: String         // 配对时 iPhone 公钥的 SHA-256 指纹
    let pairedAt: Date
    var lastConnectedAt: Date?
    var revokedAt: Date?              // 撤销时间戳
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

**8 个 case 是 M1 引入的操作白名单——任何 iPhone 请求必须 match 这个 enum，否则拒绝**。这与 `Sources/TaskMCPBridge.swift` 的 `LocalMCPBridgeOperation` 受限 case 设计一致。

### 3.5 验证 M1

M1 的验证**不能**在 Mac 端单边完成——必须有真机 iPhone：

| 验证项 | 形式 | 闸门 |
|---|---|---|
| Bonjour 发现 | 同一 LAN iPhone + Mac 互发现 | G4（真机）|
| TLS 握手 | fingerprint 互验 | G4 |
| 配对成功 | `PairedDevice` 持久化 | G4 |
| 撤销路径 | 用户在 Mac 工作台撤销 → iPhone 立即无响应 | G4 |
| 启动请求 | iPhone 点图标 → Mac 工作台弹确认 → 用户确认 → `TerminalLauncher.launch` | G4 + `mobileLocalConfirmPolicy` |

**M1 实施必须在 G4 闸门具备后**——`docs/post-takeover-plan.md`（commit 2.2）会显式列出 G4 状态。双设备验收的操作步骤与证据要求见 `docs/m1-g4-verification-guide.md`。

## 4. M0 vs M1 实现路径

| 阶段 | 工作 | 分支 | 预计 commit | 阻塞 |
|---|---|---|---|---|
| M0 设计 | 本文 (commit 2.1) | `feature/m0-m1-design` | 1 | 无 |
| M0 实现 | 数据模型 + 枚举 + 工具编辑 UI + 备份守卫 + 单测 + UI 测试 | `feature/m0-mobile-entry-prototype` | 3-5 | 无（**不依赖 G4**）|
| M1 设计 | 选型 (Network/Bonjour/TLS) + 配对流程 + 数据模型 + 验证方案 | `feature/m0-m1-design`（本文档 §3）| 1 | 无 |
| M1 实现 | 配对核心 + 监听器 + PairedDeviceStore + iPhone app | `feature/m1-local-network-pairing`（2026-09-06 启动）| 5-10 | 开发验证无阻塞（免费 personal team 签名）；双设备实测待 iPhone + 局域网 |
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

## 6. G4 闸门现状（2026-09-06 更新）

**开发验证前提已具备；双设备实测未开始——G4 仍未通过。**

| G4 组成 | 状态 |
|---|---|
| 真机安装签名 | ✅ 免费 Apple ID（personal team）：Xcode 真机调试可用，限额 3 app/设备、App ID/设备注册 7 天过期、10 App ID/周、3 台设备；iPhone 需开启开发者模式 |
| 真实 iPhone | ⚠️ 待用户提供 |
| 局域网 | ⚠️ 待用户提供 |
| 双设备 Bonjour/TLS/配对/撤销实测 | ❌ 未开始——完成前不得宣称 G4 通过 |

**免费账号的边界**：只支撑开发验证。手机端 app 每 7 天必须回 Mac 重签一次，不能当长期工具用；TestFlight、长期安装、Developer ID 外部分发、iCloud 仍是付费会员专属。

**M1 启动决策树（已执行）**：
- ✅ 开发验证前提具备 → `feature/m1-local-network-pairing` 分支已启动，按 §3.2–§3.4 实现
- ⚠️ 双设备实测 → 等 iPhone + 局域网，按 §3.5 执行；结果记入 `docs/post-takeover-plan.md` 与 `product-roadmap.md` §8

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
