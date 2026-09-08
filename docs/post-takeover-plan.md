# TermiPad 接手后计划（post-takeover plan）

**来源：** 对齐 `docs/t0-development-preparation-checklist.md` §6 "后续阶段才需要的外部条件" 全表 5 行 + `docs/product-roadmap.md` §5 阶段 4-7。

**状态：** 阶段 2 接手 commit 2.2（2026-08-29，zcode）。**纯对照文档**——把原方案 §6 的 5 行 × 当前状态 × 接手进展画成一张表。

**作用范围：** 让任何接手者 / 用户能一眼看到"原方案剩下什么、谁在阻塞、我做到哪了"。

## 1. 接手点

- **上一个 AI（Manus AI）停下的 commit**：`8e73e76` "Document Launchpad handoff"（2026-08-28）
- **接手者**（zcode）的**第一个 commit**：`1189a30` "Mark TaskMCPBridge.serviceName as nonisolated"（2026-08-29，Swift 6 警告修 + todo 事实补全）
- **接手后阶段 1 完成**（6 commit，feature/track-protocol-materials 分支）：原方案 §4 "必须维护的材料与证据" 6 行材料全部补强
- **接手后阶段 2 进行中**（2 commit，feature/m0-m1-design 分支）：M0/M1 移动端入口设计文档
- **当前文档**：本文

## 2. 原方案 §6 全表交叉（"5 个待启动阶段"现状）

按 `docs/t0-development-preparation-checklist.md` §6 表格 5 行 × 当前状态 × 谁在阻塞：

| 原方案 §6 行 | 对应 `product-roadmap.md` 阶段 | 我能做的（无外部条件） | 阻塞在你（外部条件） | 下一个分支名 |
|---|---|---|---|---|
| 1. 原生 iPhone 同网配对 | 阶段 4: M0/M1 | ✅ **M0 已实现并合入 master**。**M1 Mac 侧 + iPhone 伴侣已实现**（`feature/m1-local-network-pairing`，8 commit）| ⚠️ **G4 实测进行中（3/7 通过，2026-09-06）**：Bonjour 发现 ✅ 指纹比对 ✅ 配对落库 ✅；会话加密/启动请求/撤销实测待请求通道实现；7 天重签待观察。长期安装/TestFlight 仍 ❌ 付费会员 | 下一批：会话复用协议 + listTools 通道 |
| 2. 原生 iPhone 长期安装/分发 | 阶段 7 | ❌（M1 完成后才有意义） | ❌ Apple Developer Program 账户 + App Store / TestFlight 资质 | 待 M1 完成后单独立项 |
| 3. 异地会话 / PWA | 阶段 5: M2 | ❌（M1 完成后才有意义） | ❌ **G5 闸门**：HTTPS origin + 设备身份 + 会话服务 + 撤销模型 | 待 M1 完成后：`feature/m2-remote-secure-session` |
| 4. Telegram Mini App | 阶段 4/5 备线（与 1 互斥） | ❌ | ❌ 私人 Bot + Bot token 的 Keychain 存储 + 固定 HTTPS origin + 服务端 `initData` 验证 | 待 M0 实现完成后，与 iPhone 主线对比，由用户拍板入口路线 |
| 5. macOS 外部分发（Developer ID / Hardened Runtime / 公证 / Gatekeeper 冷启动）| 阶段 7 | ✅ 脚本骨架与文档已就位（`scripts/release-build.sh` + `docs/release-build.md`）| ❌ 付费 Apple Developer 证书 + 真实旧 store 升级验证——实际签名/公证未执行 | 骨架已完成；执行等付费证书 |

**结论（2026-09-06 更新）**：M0 已实现并合入 master；M1 开发验证已解锁（免费 personal team 签名），实现分支 `feature/m1-local-network-pairing` 进行中。剩余阻塞收敛为：真实 iPhone + 局域网（G4 双设备实测）、付费 Apple Developer（长期分发/TestFlight/iCloud/G6）。

## 3. 阶段 1 完成的工作（commit `414a417` in `feature/track-protocol-materials`）

按原方案 §4 6 行材料，每行的 zcode 补强：

| 原方案 §4 行 | 文档 / 守卫 / 测试 commit | 改了什么 |
|---|---|---|
| 1. TaskIntent 数据字典 | `46fb263` `docs/task-intent-data-dictionary.md` | 158 行文档：5 实体 × 6 枚举 × 每字段"跨入口 / 备份 / 诊断" 三轴 |
| 2. 策略拒绝矩阵 | `47f2721` 改 `TaskIntentPolicyTests.swift` | 78 → 88 单测：保留 5 集成测试 + 新增 10 个独立命名测试（9 拒绝路径 + 1 scope ID mismatch）|
| 3. 进程树和取消证据 | `f166db3` 新增 `TaskExecutionServiceTests.swift` | 88 → 93 单测：5 个真实进程集成测试（exit 0 / exit 7 / stop / already started / unapproved）|
| 4. 最小结果规范 | `05ca7e4` `docs/task-result-minimal-spec.md` + 2 个新 `DiagnosticEventKind` + 1 行 bridge 双层审计 | 115 行文档：4 状态枚举 × 字段白名单 × 红线表 × 19 诊断事件映射 |
| 5. 迁移与备份决定 | `6b931c4` 新增 `BackupServiceTaskExclusionTests.swift` + `scripts/verify-macos.sh` 新增 `backup_code` 守卫 | 93 → 96 单测 + 23 → 24 静态守卫 |
| 6. 无害测试任务集 | `414a417` 改 `Sources/TaskIntent.swift` | FixedTaskCatalog 3 → 5（加 `swiftBuild` + `swiftPackageCheck`） |
| 7. 验证产物 | 维持现状 | 每次 commit 跑 `./scripts/verify-macos.sh`，归档到 `.verification/<时间戳>/` |

## 4. 阶段 2 进展（`feature/m0-m1-design` 分支）

| commit | 内容 | 状态 |
|---|---|---|
| `f3d5196` `docs/m0-m1-mobile-entry-design.md` | M0 数据模型 + 6 字段语义 + UI section 设计 + 备份隐私契约；M1 Network/Bonjour/TLS 选型 + 配对 7 步流程 + G4 闸门说明 | ✅ push 完成 |

`post-takeover-plan.md`（**本文**）对照 §6 全表（commit 2.2）

## 5. 接手进展总结图

```
8e73e76 (Manus AI 停下)
    │
    ├── 1189a30 (Swift 6 警告 + todo 事实补全) ←—— zcode 第一笔
    │
    ├── feature/track-protocol-materials (阶段 1, 6 commit)
    │     ├── 46fb263 §4.1 数据字典
    │     ├── 47f2721 §4.2 策略拒绝矩阵
    │     ├── f166db3 §4.3 进程树证据
    │     ├── 05ca7e4 §4.4 最小结果规范
    │     ├── 6b931c4 §4.5 迁移与备份决定
    │     └── 414a417 §4.6 无害测试任务集
    │
    └── feature/m0-m1-design (阶段 2, 2 commit)
          ├── f3d5196 M0/M1 设计文档
          └── (本文) 2.2 post-takeover plan ←—— 你正在读
```

## 6. 下一步决策树

按从"我现在能做的"到"阻塞在你的" 5 个原方案阶段：

```
                                ┌── (a) 我能做的：阶段 3 release-build 脚本骨架 (1 commit) ──┐
                                │                                                                │
                                │   ┌── (b) M0 实现 (3-5 commit, 无外部阻塞) ──┐                │
                                │   │                                          │                │
原方案 §6 5 行 ──               │   │                                          │                │
   1. iPhone 同网配对 ───────►   ─┤   │                                          │                │
   2. iPhone 长期分发 ──────►   阻塞 Apple Developer                           │                │
   3. 异地会话 / PWA ────────►   阻塞 G5 (HTTPS origin + 设备身份)          │                │
   4. Telegram Mini App ────►   阻塞 Bot + HTTPS + Apple Developer             │                │
   5. macOS 外部分发 ────────►   ─┘   ───────────────────────────────────┘                │
                                                                                          │
                                                                          ⬇︎                ⬇︎
                                                                feature/m0-mobile-entry-prototype
                                                                                          feature/release-build-skeleton
```

**5 个原方案阶段中，阶段 1 已完成 1/5（无外部阻塞的 §4 维护材料）**。**阶段 2 启动设计（commit 2.1/2.2）**。**M0 实质实现（commit 3.x）是我能立即推进的下一笔**——无 G4 阻塞。

## 7. 维护规则

- **任何 M0/M1/M2/M3 启动 commit**：必须**先**更新 §2 / §6 表格**后**写代码。表格是闸门状态真相。
- **任何新发现 G4/G5 闸门状态变化**：在 commit message 里**显式**说"G4 状态：✅ / ❌ / ⚠️"。
- **任何 post-takeover-plan 字段过期**：下一笔接手 commit 必须更新本文 + 在 commit message 引用。
- **本文不应删除任何历史分支引用**——保留完整接手路径作为审计证据。
