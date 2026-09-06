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

## 4. 验收记录

**2026-09-06 首轮（iPhone 14 Plus, iOS 26.6.1 ↔ MacBook Pro, 192.168.2.81/en0）：**

| # | 验证项 | 结果 | 备注 |
|---|---|---|---|
| 1 | Bonjour 发现 | ✅ 通过 | `_termipad-m1._tcp`；iOS 端本地网络权限声明由 project.yml info.properties 生成（手写 plist 曾被 XcodeGen 覆盖，见 commit 278b9a7） |
| 2 | 指纹人工比对 | ✅ 通过 | 手机屏显 MacHello.fingerprint 与 Mac 屏一致后人工确认 |
| 3 | 配对成功 | ✅ 通过 | 钥匙串 `mobile-pairing.device-index=["BE0172EB-…"]` + `mobile-pairing.identity` 均确认存在 |
| 4 | 会话加密（工具目录） | ⏳ 未测 | 请求通道（listTools）未实现——需设备长期身份持久化 + 会话复用协议（下一批次） |
| 5 | 启动请求 + 本地确认 | ⏳ 未测 | 依赖 #4 |
| 6 | 双重撤销实测 | ⏳ 未测 | Mac 撤销 UI 已实现；手机端失效效果待请求通道接通后验证 |
| 7 | 7 天重签 | ⏳ 未测 | 时间依赖；重签后凭据保留情况待记录 |

**结论：G4 进行中（3/7）。** 免费签名（team 7LTPLQKWWD，Apple 于 2026-09-06 重登录时轮换）+ 开发者模式 + 同网 mDNS 均已实证可用。
