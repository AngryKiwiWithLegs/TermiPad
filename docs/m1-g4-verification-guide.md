# M1 G4 双设备验证指引（免费 Apple ID 签名）

**适用阶段：** `feature/m1-local-network-pairing` 分支的 Mac 侧实现合入后、宣称 G4 通过之前。

**前提：** `docs/m0-m1-mobile-entry-design.md` §3.1/§6（2026-09-06 更新）——免费 Apple ID（personal team）支撑真机**开发验证**；长期安装/TestFlight/外部分发仍需付费会员。

## 1. 一次性准备（可提前做，与开发并行）

| 步骤 | 操作 | 说明 |
|---|---|---|
| 1 | Xcode → Settings → Accounts → 登录你的 Apple ID | 免费 personal team 自动创建；无需付款 |
| 2 | iPhone：设置 → 隐私与安全性 → 开发者模式 → 开启 | iOS 16+ 侧载必开，需重启手机 |
| 3 | iPhone 用数据线连 Mac，Xcode → Devices and Windows → 信任并启用 | 设备注册进 personal team |
| 4 | 确认 Mac 与 iPhone 在**同一 Wi-Fi**，且路由器未开启 AP 隔离 | AP 隔离会挡 Bonjour，是最常见的发现失败原因 |

**免费账号限额（务必知晓）：** 每台设备 ≤3 个 app 同时安装；App ID/设备注册 **7 天过期**；每周 10 个新 App ID。手机端 app 过期后图标变白打不开——Xcode 里重新 Run 一次即续期。**这不影响 Mac 端 TermiPad**（本地 ad hoc 签名，无 7 天限制）。

## 2. 验收清单（G4 完成条件，逐项记录证据）

| # | 验证项 | 通过标准 | 证据 |
|---|---|---|---|
| 1 | Bonjour 发现 | iPhone app 能在列表看到 `TermiPad`（`_termipad-m1._tcp`）| 截图 |
| 2 | 指纹人工比对 | iPhone 屏显示的 Mac 指纹与 Mac 设置页一致 | 截图 ×2 |
| 3 | 配对成功 | 输入配对码后，Mac `PairedDeviceStore` 出现该设备记录 | Mac 截图 |
| 4 | 会话加密 | 配对后手机能列出 `showInMobileEntry=true` 的工具目录（仅 4 字段）| 截图 |
| 5 | 启动请求 + 本地确认 | 手机点工具 → Mac 按 `mobileLocalConfirmPolicy` 弹确认 → 确认后经 `TerminalLauncher` 打开终端 | 截图 |
| 6 | 双重撤销 | Mac 撤销设备 / 撤销工具手机权限 → 手机端立即失效 | 截图 |
| 7 | 7 天重签 | 到期重装后重新配对流程可走通（配对凭据是否保留如实记录）| 记录 |

**红线复核（每一项不过即 G4 不通过）：** 手机端任意时刻不可见命令/路径/变量/环境变量/终端输出；Mac 无公网入站端口（监听仅 Bonjour 局域网广播）；白名单外的操作一律拒绝。

## 3. 结果归档

- 验收通过后：更新 `docs/post-takeover-plan.md` §2 行 1、`docs/product-roadmap.md` §8 G4 行为"已通过（日期 + 证据目录）"。
- 证据放 `.verification/<timestamp>-g4/`（与集中验证产物同一纪律）。
- 免费签名的 7 天特性意味着 G4 通过**不等于**"长期可用"——长期安装仍按 `product-roadmap.md` §6 第 2 行等付费会员。
