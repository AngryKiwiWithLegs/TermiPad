# M2 异地安全会话设计——内置隧道（M2a 批次）

**状态：** 设计评审稿（2026-09-08）。先评审后实现；本文不宣称任何能力已实现。

**上位文档：** `docs/product-roadmap.md` §5 阶段 5（M2——异地安全会话，含 2026-09-08 传输技术决策）；`docs/m0-m1-mobile-entry-design.md`（配对/加密/撤销层，M2 原样复用）。

**范围切分：** 本批次 = **M2a（固定工具的异地启动）**。M2b（手机提交临时任务建议，接 TaskIntent/T0/T1 策略核心）独立批次；M3（远程允许窗口）在 M2a 真机验证后另行设计。三者关系见 §8。

## 1. 北极星场景

用户人在外面（蜂窝网络），手机点 TermiPad 伴侣里的固定工具 → 命令在**家里 Mac** 上经既有终端交接执行 → 手机收到最小结果（accepted/rejected）。全程：公网零暴露、命令/路径/变量/输出永不下发、每权限可撤销。

**诚实声明（预期管理）：** M2a 完成后，异地 `requestLaunch` **仍需 Mac 端本机确认**（everyTime 默认不变；perSession 的 5 分钟进程内存窗在用户离开后大概率已过期）。"无人值守免确认"是 **M3** 的交付物。M2a 的价值是把"连不上"消掉，并为 M3 铺好管道；死锁问题的最终解除依赖 M3，这是既定顺序，不是本批次的缺陷。

## 2. 前提与已验证事实（2026-09-08 实查）

| 事实 | 证据 |
|---|---|
| 用户 Mac 已装 Tailscale 1.102.2（Homebrew） | `/opt/homebrew/bin/tailscale` |
| Mac 与 iPhone 已在同一 tailnet | `tailscale status`：`macbook-pro 100.114.69.20`、`iphone-14-plus 100.95.196.38` |
| 该版本 `tailscale serve --tcp` 支持**裸 TCP 转发**（非仅 HTTPS） | `tailscale serve --help` |
| 本机无遗留 serve 配置 | `tailscale serve status` = No serve config |

**集成模型选型（本设计的核心决策）：** 参照 OpenClaw 已验证的模式——**依赖用户自装的 Tailscale，TermiPad 只做编排**，不内嵌 tailscaled、不自造 WireGuard。

| 候选 | 结论 | 理由 |
|---|---|---|
| A. 用户自装 Tailscale + TermiPad 管理 serve 转发 | **采用** | 密码学/打洞/密钥轮换全交给专业组件；TermiPad 零新网络代码面；用户 tailnet 已就绪；OpenClaw 同款模式已在本机长期运行 |
| B. 内嵌 tailscaled（库形式） | 否决 | 工程量与权限面剧增；版本跟维护负担；免费账号 app 收益不成比例 |
| C. 自造 VPN/WireGuard | 否决 | 项目红线：不自造密码学 |
| D. Tailscale Funnel（公网入口） | **永久禁用** | 公网暴露违反产品红线；见 §6 守卫 |

## 3. 连接架构

```
[蜂窝] iPhone 伴侣 app
   │  ① 先试 LAN 直连（M1 路径，同网时最快）——失败/超时则
   ▼  ② 走 tailnet 兜底：hostPort(Mac 的 tailnet IP, 57147)
[Tailscale iOS app 提供的 VPN 通道 —— WireGuard 加密，用户账号双向认证]
   ▼
[家里 Mac] tailscaled 收 tailnet:57147 → serve 转发 → 127.0.0.1:57147
   ▼
[TermiPad] 回环监听器（仅绑 127.0.0.1:57147）→ 既有 M1 握手/加密/请求链
```

**为什么回环监听 + serve 转发，而不是让 NWListener 直接绑 tailnet 接口：**
- 回环监听 = **最小网络暴露面**。Mac 上该端口对局域网、对公网、对其他虚拟网卡都不可见，只有 tailscaled（以 root 跑的用户自己装的组件）能转发进来。这是红线"Mac 不开放公网端口"的最强形态。
- Network.framework 对 utun 接口的绑定能力不可靠（`requiredInterfaceType` 无 utun 分支），跨 Tailscale 版本脆弱；serve 是 Tailscale 官方支持的转发路径。
- OpenClaw 在本机同一模式已稳定运行（gateway 绑 loopback + `tailscale serve` worker，进程实证 2026-09-08）。

**为什么不复用 M1 的 57146 端口：** M1 监听器绑定 `.wifi` 且带 Bonjour 广播与 iOS 26 实例名绕过；隧道监听器语义完全不同（回环、无广播）。独立端口 57147 让两条路径互不干扰、可独立开关、故障域隔离。**57147 为固定端口**（写入协议常量，与 57146 并列）。

## 4. 协议与数据（增量最小化）

### 4.1 协议零破坏增量

M1 复用握手全链（`PhoneResumeHello` → `MacResumeHello` → 加密 `MobilePairingRequest`）**原样跑在隧道上**——加密层（X25519+HKDF+AES-GCM）、指纹绑定、操作白名单、资格预检、本地确认全部不变。

**唯一协议变更：** `MacResumeHello` 增加可选字段

```swift
struct MacResumeHello: Codable {
    let protocolVersion: Int
    let macPublicKey: Data
    let macNonce: Data
    /// M2a：异地端点 "100.114.69.20:57147"。仅当用户开启"异地访问"时非 nil。
    /// nil = 本批次功能未开/未检测到 Tailscale——手机端异地路径不可用（明确提示，不静默）。
    var tailnetEndpoint: String?
}
```

- **明文发送可接受**（与既有 MacResumeHello 同帧）：tailnet IP 的机密性由 tailnet 成员资格天然保障——非成员根本路由不到 100.64/10 网段；泄露它不降低任何一层安全（连接仍需 tailnet 成员 + 应用层配对双通过）。同网攻击者学到 IP 也无路可走。
- **向前向后兼容**：旧 Mac 不发（解码得 nil）；旧手机忽略新字段（JSONDecoder 默认忽略未知键）。**无需协议版本升级**。
- 手机端持久化：`CompanionPairingCredentials` 增加可选 `tailnetEndpoint` 字段，**Keychain-only**（M0-M1 设计 §3.4 同款纪律）。**必须用 `decodeIfPresent` 自定义解码**——旧凭据 JSON 无此键，合成解码会抛错；这是"新增字段必须 Optional + 旧数据兼容"红线的落实点，实现批次配单测。

### 4.2 地址学习流程（同网配对引导异地）

1. 用户开启 Mac 端"异地访问"开关 → TermiPad 检测 Tailscale → 读 tailnet IP（`tailscale ip -4`，固定路径固定参数）→ 配置 serve 转发 → 启动回环监听器
2. 之后每次同网 resume 成功，`MacResumeHello.tailnetEndpoint` 随帧下发
3. 手机端把端点写进凭据（Keychain）；此后异地时直接使用
4. 用户在异地**无需任何配对操作**——同网时早已完成引导

**端点失效自愈：** 手机每次异地连接若被拒/超时，下次同网 resume 会刷新端点（Mac 的 tailnet IP 仅在用户手动换 tailnet 时才变，常规稳定）。

## 5. Mac 端设计（Sources 内新增，守卫约束见 §6）

| 组件 | 职责 | 边界 |
|---|---|---|
| `TailnetTunnelService`（新文件，@MainActor ObservableObject） | 开关状态机 off/检测中/ready/failed；调 CLI；管理回环监听器生命周期 | 唯一允许调用 tailscale CLI 的文件 |
| CLI 调用 | `tailscale ip -4`（读）、`tailscale serve --bg --tcp=57147 tcp://127.0.0.1:57147`（开）、`tailscale serve --https=443 --tcp=57147 off`（关） | **固定绝对路径白名单**：`/opt/homebrew/bin/tailscale`、`/usr/local/bin/tailscale`（与 EnvironmentReport 同款纪律：固定路径+固定参数+无用户输入拼接，不经 shell） |
| 回环监听器 | `NWListener` + `requiredLocalEndpoint = 127.0.0.1:57147`（若框架不支持绑回环，降级全接口绑定 + 文档注明差异，应用层加密不受影响） | 复用 M1 的 `beginHandshake` 全链——`MobilePairingService` 握手代码抽公共入口，**不复制粘贴** |
| 状态与 UI | 设置 → 手机伴侣 下新增"异地访问（需要 Tailscale）"Section：开关 + 状态行（未检测到 Tailscale / 已就绪 `100.x.x.x:57147` / 已关闭） | **默认关闭**（与 M1 同网配对开关同级默认）；关闭时立即 `serve off` + 停监听 + `MobileLaunchSession.invalidateAll()` |
| 诊断 | `DiagnosticEventKind` 增加固定枚举 `remoteTunnelOpened` / `remoteTunnelClosed`（仅时间戳，无 IP/工具名——隐私纪律） | 不记 tailnet IP 进诊断 |

**握手入口重构注意：** M1 的 `beginHandshake` 目前从 `newConnectionHandler` 进来并自带 Bonjour 语义注释；抽取时保持行为逐字节不变（两个监听器只是连接来源不同），抽取批次跑全量集中验证 + 同网 G4 回归。

## 6. 安全分析与红线延续

| 层 | 保障 | M2a 变化 |
|---|---|---|
| 网络层 | WireGuard（tailnet 成员双向认证）+ 公网零暴露（出站隧道） | 新增层；Funnel 永久禁用 |
| 传输层 | 应用层 X25519+HKDF+AES-GCM、指纹人工比对 | 不变，原样复用 |
| 授权层 | 资格预检 + 本机确认（everyTime 默认）+ 撤销立即生效 | 不变；确认弹窗在异地请求时照常出现（设备名提示不变） |
| 数据层 | 手机只收 4 字段目录 + 结果枚举；tailnet 端点进 Keychain 不进备份 | 新增 1 个凭据字段（decodeIfPresent 兼容） |

**丢手机分析（tailnet 场景的新增面）：** 攻击者捡到手机需要同时拿到 (a) Tailscale iOS app 的 tailnet 成员资格（Tailscale 自身有 Keychain 保护/可选生物识别，属用户账号域）与 (b) 伴侣 app Keychain 里的配对凭据。任一缺失都进不来。**且** Mac 端用户可随时：关异地开关（serve 即撤）、撤销设备配对、撤销工具权限——三重即时收回。

**新增守卫（实现批次进入 verify-macos.sh）：**
1. `tailscale` CLI 调用只允许出现在 `TailnetTunnelService.swift`（静态 grep 白名单模式，同 NWListener 守卫）
2. 全仓禁用 `funnel` 子命令（出现即验证失败——公网暴露红线）
3. 端口常量 `tunnelListenerPort = 57147` 与 57146 并列声明
4. `CompanionPairingCredentials` 解码必须含 `decodeIfPresent`（测试锁）

## 7. G5 验收清单（异地真机，全部通过才宣称 M2a 完成）

| # | 验证项 | 通过标准 |
|---|---|---|
| 1 | 引导 | 同网配对 resume 后，手机凭据含 tailnetEndpoint；异地开关关闭时为 nil |
| 2 | 异地 resume | 手机走蜂窝（关 Wi-Fi），Mac 在家：resume 成功、工具目录可达 |
| 3 | 异地启动+确认 | 异地点工具 → Mac 弹确认 → 确认执行 → 手机绿✅；拒绝路径同样验证 |
| 4 | 双通道回退 | 回到同网后 LAN 路径自动恢复（无需重配对）；异地开关关闭时手机端明确提示"异地通道未开启"而非无限转圈 |
| 5 | 即时收回 | Mac 端撤销设备 → 异地 resume 立即被拒（与 G4 #6 同语义）；关异地开关 → 手机端连接失败且有明确文案 |
| 6 | 红线复核 | Mac 无公网入站（路由器 WAN 侧无映射）；`tailscale serve status` 仅 tailnet 内 tcp 转发；手机全程不可见命令/路径/变量/输出 |

## 8. 与 M2b / M3 的衔接（预告，不在本批次）

- **M2b（临时任务建议）**：在 M2a 管道上新增操作白名单 case（`proposeTask` 等），把 T0 TaskIntent 策略核验接到手机请求——协议框架已预留 `PairedDeviceOperation` 枚举扩展位，M2a 不预实现。
- **M3（远程允许窗口）**：管道就绪后，`MobileLaunchSession`（M1.1 的 5 分钟白名单）推广为用户显式授权的 `RemoteAllowWindow`（工具集合 + 用户设定时长 + 锁屏/休眠立即失效 + 速率限制 + 审计）。本设计不预定义其字段——等 M2a 异地体感出来再冻结契约。
