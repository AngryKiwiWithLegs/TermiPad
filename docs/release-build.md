# TermiPad 外部分发构建（release build）

**来源：** 对齐 `docs/t0-development-preparation-checklist.md` §6 第 5 行 "macOS 外部分发：Developer ID、Hardened Runtime、公证、Gatekeeper 冷启动测试 — 当前仍是外部发布闸门" + `docs/product-roadmap.md` 阶段 7 + `docs/private-beta-release-audit.md` §2 "当前阻塞项"。

**状态：** 阶段 3 接手 commit 3.1（2026-08-29，zcode）。**文档 + 脚本骨架**——`scripts/release-build.sh` 已就位（占位签名/公证/staple 步骤，无外部条件时降级为打印）；**完整流程不**可在当前环境跑通（依赖 Apple Developer Program 账户 + 证书 + notary profile）。

**作用范围：** 当前 `project.yml` 显式用 ad hoc 签名（`CODE_SIGN_IDENTITY: "-"`）和 `ENABLE_HARDENED_RUNTIME: NO`（`project.yml:18-20`），**适合开发机本地构建与 UI Runner 验证**。**不**是 Developer ID 分发配置。本文档 + `scripts/release-build.sh` 提供**切换到 Developer ID 分发**的完整流程，但**实际签名/公证**依赖本文 §1 的外部条件。

## 1. 外部条件（必须具备才能跑完整流程）

| 条件 | 用途 | 当前状态 | 来源 |
|---|---|---|---|
| Apple Developer Program 账户（$99/年） | 注册证书身份 + 公证身份 | ❌ 未具备 | 用户决定 |
| Developer ID Application 证书 | macOS 外部分发签名身份 | ❌ 未具备 | 来自 Apple Developer Program 账户 |
| 钥匙串导出 Developer ID 私钥 | 让 xcodebuild / codesign 使用 | ❌ 未具备 | 上面签发后从 Xcode → Accounts → Manage Certificates 导出 |
| App Store Connect API key（p8 文件） | notarytool 公证 | ❌ 未具备 | App Store Connect → Users → Keys → 生成 |
| 钥匙串 profile 存 API key | `xcrun notarytool store-credentials` | ❌ 未具备 | 上面 API key 生成后 |
| 真实 Mac（已具备） | 跑 build / 签名 / 公证 | ✅ 当前开发机即可 | — |
| Xcode 完整版 | 工具链 | ✅ | — |
| notarytool（xcrun 子命令） | 公证 | ✅ | macOS 13+ 自带 |

**完整流程依赖** 上面前 5 项**全部具备**。当前（commit 3.1）= 0/5 具备。

## 2. 完整流程（Developer ID 签名 → 公证 → Gatekeeper 通过）

```
   ┌──────────────────────────────────────────────────────┐
   │ 1. 准备：注册 Apple Developer + 导出 Developer ID 私钥 │
   │    到 login keychain。                                  │
   └──────────────────────────────────────────────────────┘
                              ↓
   ┌──────────────────────────────────────────────────────┐
   │ 2. 准备：xcrun notarytool store-credentials 存 API key  │
   │    进 keychain（如 profile 名 "notaryprofile"）。       │
   └──────────────────────────────────────────────────────┘
                              ↓
   ┌──────────────────────────────────────────────────────┐
   │ 3. 改 project.yml: 去掉 ad hoc 签名和                   │
   │    ENABLE_HARDENED_RUNTIME: NO；改用发布配置           │
   │    （待 phase 7 实施；本骨架不直接改）                  │
   └──────────────────────────────────────────────────────┘
                              ↓
   ┌──────────────────────────────────────────────────────┐
   │ 4. 跑 ./scripts/release-build.sh --dmg                 │
   │    - archive  Release 配置                              │
   │    - codesign 用 Developer ID + entitlements           │
   │    - hdiutil 打 DMG                                    │
   │    - notarytool submit + wait                          │
   │    - stapler staple                                    │
   │    - 自动跑 verify-release-artifact.sh 自检            │
   └──────────────────────────────────────────────────────┘
                              ↓
   ┌──────────────────────────────────────────────────────┐
   │ 5. 拿干净的 Mac（Gatekeeper enabled, 隔离环境）测：     │
   │    下载 DMG → 双击 → 是否 Gatekeeper 放行              │
   │    证据写 release-evidence/<时间戳>/                    │
   └──────────────────────────────────────────────────────┘
                              ↓
   ┌──────────────────────────────────────────────────────┐
   │ 6. 在干净 Mac 上测旧 store 升级路径：                   │
   │    已装 v0.x 的 Mac 安装 v0.x+1 → 升级路径不挂        │
   │    SwiftData 迁移正确（Sources/TermiPadDataStore.swift   │
   │    已有 recovery container fallback；详见                 │
   │    private-beta-release-audit.md §4）                  │
   └──────────────────────────────────────────────────────┘
```

## 3. 骨架脚本做了什么

`scripts/release-build.sh` 是上面流程第 4 步的脚本化。**当前可执行**（commit 3.1 已 `chmod +x`），**完整功能依赖** §1 外部条件。

### 3.1 脚本参数

```bash
./scripts/release-build.sh [--skip-notarization] [--skip-staple] \
                           [--output-dir <dir>] [--dmg]
```

| 参数 | 含义 |
|---|---|
| `--skip-notarization` | 跳过公证步骤（**不推荐**——未公证的 .app 在 Gatekeeper 启用 Mac 上会被拒）|
| `--skip-staple` | 跳过 staple 票据附加（不推荐）|
| `--output-dir <dir>` | 自定义输出目录（默认 `./release-build/<时间戳>/`）|
| `--dmg` | 创建 .dmg 镜像（默认只产 .xcarchive + .app）|
| `-h` / `--help` | 显示帮助（脚本内 head -30）|

### 3.2 环境变量

| 变量 | 用途 | 不设置时行为 |
|---|---|---|
| `DEVELOPER_ID_APPLICATION` | 完整签名身份，如 `"Developer ID Application: Foo (TEAMID)"` | 降级为 ad hoc 签名（`-`），**不可分发** |
| `NOTARYTOOL_KEYCHAIN_PROFILE` | notarytool keychain profile 名（如 `"notaryprofile"`）| 公证步骤降级为打印"将要执行什么"|
| `BUNDLE_ID` | TermiPad Bundle ID（默认 `com.termipad.app`，匹配 `project.yml:34`）| 用默认 |
| `APPLE_TEAM_ID` | 10 字符 Apple Team ID | 当前不强制使用（公证 profile 含 Team ID）|

### 3.3 输出目录结构

```
release-build/<时间戳>/
├── summary.md                          # 每个步骤的输出日志汇总
├── TermiPad.entitlements               # 脚本写入的 Hardened Runtime 必需 entitlement
├── TermiPad.xcarchive/                 # xcodebuild archive 产物
│   └── Products/Applications/TermiPad.app
├── TermiPad.dmg                        # （仅 --dmg 时）hdiutil 产物
└── （self-test 跑 verify-release-artifact.sh 时还会创建 release-evidence/<时间戳>/）
```

### 3.4 当前骨架的"降级"行为

骨架在缺环境变量时**不报错退出**——而是显式打印"⚠️ XXX 未设置——降级为 ad hoc" 并继续走完 pipeline。**为什么**：
- 接手者（zcode）当前没证书，**必须**能在自己 Mac 上跑通骨架验证语法
- 降级行为**显式可见**——`summary.md` 会记录每一步降级原因
- 未来用户拿到证书后**不需要**改脚本——只需设环境变量重跑

## 4. `verify-release-artifact.sh` 是它的搭档

- `release-build.sh` = **做** archive + 签名 + 公证 + staple
- `verify-release-artifact.sh` = **审** 已签名的 .app 完整性

完整 pipeline = `release-build.sh` 跑完 → 立即 `verify-release-artifact.sh --require-notarization` 自检 → 证据写入 `release-evidence/<时间戳>/`。

`verify-release-artifact.sh` 已经在 `commit 1.5 之前`就存在（pre-takeover 代码），**不**是 zcode 接手 commit 3.1 的一部分。**但**接手 commit 3.1 的脚本会**自动**调用它作为自检。

## 5. 完整 pipeline 调用样例（外部条件具备后）

```bash
# 一次性：导出 Developer ID 私钥到 login keychain（Xcode 流程）
# 一次性：xcrun notarytool store-credentials 存 API key

# 每次发布
export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAM1234567)"
export NOTARYTOOL_KEYCHAIN_PROFILE="notaryprofile"

cd ~/TermiPad
./scripts/release-build.sh --dmg

# 检查 release-build/<时间戳>/summary.md + release-evidence/<时间戳>/summary.md
```

## 6. Gatekeeper 冷启动验收（**真实旧 Mac 隔离测试**）

Apple 官方要求：分发 .app **必须** 在 Gatekeeper 启用的干净 Mac 上验证。这是 §1 第 5 项的真实含义。

| 步骤 | 怎么验 |
|---|---|
| 1. 找一台**未参与构建**的 Mac（家里、朋友、同事的）| — |
| 2. 系统设置 → 隐私与安全性 → 确保 Gatekeeper = "仅允许 App Store 与已确认开发者" | — |
| 3. 复制 release-build/.../TermiPad.dmg 到该 Mac | 用 AirDrop / U 盘 / scp |
| 4. 双击 .dmg → 弹出 → 拖到 /Applications | — |
| 5. 双击 .app → Gatekeeper 应弹"无法打开，因为来自身份不明的开发者" | **如果没弹** = 签名错 |
| 6. 系统设置 → 隐私与安全性 → "仍要打开" | 应能正常启动 |
| 7. 测所有功能：扫描、收件箱、工具启动、备份导出/导入、任务工作台、MCP 开关 | — |
| 8. 证据写 release-evidence/<时间戳>/gatekeeper-cold-start.md | — |

**只有这一步过了**才能说"v0.x+1 可外部分发"。

## 7. 与原方案 §1 红线的关系

`docs/product-roadmap.md` §7 红线继承到发行流程：

| 红线 | release-build 体现 |
|---|---|
| Mac 不开放公网终端 | release-build **不**监听任何端口；公证是出站调用 Apple notary 服务（单向）|
| 无任意远程 Shell | 发行版二进制与开发版同 source（仅改 `project.yml` 签名配置）|
| 命令不可被 AI 改写 | Hardened Runtime entitlement 严格按 `TermiPad.entitlements` 走（无 `com.apple.security.cs.disable-library-validation`）|
| 最小数据回传 | notarytool 上传只含 .app 二进制 + DMG 体积元数据，**不**含用户工具库、命令、API Key |
| 本地优先 | 发行版开启 Hardened Runtime 沙箱子集（**不**全开——保留 Apple Events 权限以驱动 Terminal/iTerm/Warp）|

## 8. 维护规则

- 任何 §1 外部条件状态变化（用户注册了 Developer Program / 拿到证书）→ **先**更新本文 §1 表格，**后**执行新 build。`summary.md` 里记录的"降级原因"对后续审计是关键证据。
- 任何 release-build.sh 改动 → 必须**仍然**在 §1 第 5/5 未具备时跑得通（语法正确、所有降级路径都触发、最终 summary.md 完整记录）。
- 任何新增签名 / 公证步骤 → 必须在本文 §2 流程图加节点。
- 任何 release-evidence/<时间戳>/ 内的证据**永不**删除——是未来发行事故回查的关键。
