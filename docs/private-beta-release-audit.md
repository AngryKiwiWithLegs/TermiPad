# TermiPad 私有 Beta 发布前审计

**审计范围：** 私有分发版本，不包含 Mac App Store 发布。

**当前仓库基线：** `0f291a0` 之后的私有开发分支；正式发行仍未获准。

**审计日期：** 2026-08-24。

> 本文是发布闸门，而不是发布说明。任何外部测试者获得安装包前，必须满足本文的“必须完成”项，并保留对应证据。

## 1. 已完成并在真实 Mac 验证的基线

在用户的 Apple Silicon Mac（Xcode 26.6、Swift 6.3.3、XcodeGen 2.46.0）上，提交 `1abdb4d` 已完成全量一键验证。该次验证通过 Swift Package 清单检查、原生工程生成、macOS 构建、测试 Runner 签名校验、**30 个单元测试**以及**2 个 UI 冒烟测试**。随后代码继续增加了旧备份图标清理与候选收录边界测试；这些新增改动必须在同一真实 macOS 流程再次验证后才可并入私有 beta 候选版本。

| 已验证或已实现的控制项 | 当前结论 | 证据或实现位置 |
|---|---|---|
| 用户确认候选后才进入工具库 | 已实现 | `CandidateTool` 状态与 `LaunchpadView.accept` |
| AI 不可生成或覆盖启动命令 | 已实现并有回归测试 | `AIService.swift`、`AITrustBoundaryTests` |
| GitHub 仅接受官方映射或高置信匹配 | 已实现并有回归测试 | `GitHubService.swift` |
| GitHub owner 头像不作工具图标 | 已实现；旧 URL 不渲染、不导出、不恢复 | `ToolIconView.swift`、`BackupService.swift` |
| schema 1 旧备份缺失信任字段 | 已由单元测试覆盖 | `ToolWorkflowTests` |
| API Key 不进入备份 | 已实现 | Keychain 存储与 `BackupService.swift` |
| Terminal/iTerm 自动化被拒绝时复制命令 | 已实现；提示文字有单元测试 | `TerminalLauncher.swift` |

## 2. 当前阻塞项：不能直接公开或外部分发

当前 `project.yml` 明确使用 ad hoc 签名（`CODE_SIGN_IDENTITY: "-"`），并将 `ENABLE_HARDENED_RUNTIME` 设为 `NO`。这适合在开发机上让 UI Test Runner 通过 Gatekeeper 校验，但**不是 Developer ID 分发配置**。因此，当前状态可继续作为受控的开发与自测版本，不能宣称为已准备好供外部下载安装的 release build。

Apple 对 Mac App Store 外分发的建议是使用 **Developer ID** 签名，并在分发前用 Gatekeeper 已启用的 Mac 测试最终用户启动体验。[1] Apple 的公证要求包括：所有分发的可执行文件具有有效签名，使用 Developer ID 类型证书，启用 Hardened Runtime，使用安全时间戳，并避免在发行包中保留值为 `true` 的 `com.apple.security.get-task-allow` entitlement。[2] Hardened Runtime 的例外权限应按最小必要原则配置。[3]

| 发布闸门 | 当前状态 | 可接受完成标准 |
|---|---|---|
| Developer ID Application 证书与团队配置 | 未配置 | 仅在发行配置中使用 Developer ID Application 身份；不得用 ad hoc、开发证书或 Mac Distribution 代替。 |
| Hardened Runtime | 未配置 | 发行 App target 开启；仅在确有功能需要时添加最小例外 entitlement。 |
| Apple Events 权限 | 已声明用途文本 | 保留 `NSAppleEventsUsageDescription`，并在干净账户上验证 Terminal/iTerm 首次授权、拒绝和复制回退。 |
| 发行包 entitlement | 未审计 | 导出后确认没有 `get-task-allow=true`，并保存 `codesign -d --entitlements :-` 输出。 |
| 公证与票据 | 未执行 | 使用 `notarytool` 上传，等待接受结果，staple 票据，并保留请求 ID 与日志。 |
| Gatekeeper 冷启动 | 未执行 | 在未参与构建的 Gatekeeper 启用 Mac 上，对下载后带 quarantine 属性的最终包验证启动。 |
| 版本号与更新策略 | 未固定 | 固定 `CFBundleShortVersionString`/`CFBundleVersion`，并确定私有 beta 的回滚、过期和更新通知机制。 |

## 3. 推荐的受控私有 Beta 发行流程

发布负责人应先在干净工作树运行 `./scripts/verify-macos.sh`，并归档 `.verification/<timestamp>/summary.md`、完整日志、`.xcresult` 与 UI 截图。然后以 **Release** 配置归档，使用 Developer ID Application 证书签名，开启 Hardened Runtime。归档后的 app 必须先执行签名与 entitlement 审查，再打包为 DMG、PKG 或 ZIP 之一；打包格式一旦确定，应作为后续 beta 的固定通道，以便复现与回滚。

建议执行并保留如下本地检查。命令中的路径仅为示例，实际发行工件必须替换为归档导出的最终 App：

```bash
codesign --verify --deep --strict --verbose=4 "TermiPad.app"
codesign -dvvv "TermiPad.app"
codesign -d --entitlements :- "TermiPad.app"
spctl -a -vvv --type execute "TermiPad.app"
```

随后应通过 Xcode Organizer 的 Developer ID 分发流程，或用 `xcrun notarytool` 上传公证。Apple 已停止接受 `altool` 与 Xcode 13 或更早版本的公证上传；应使用 `notarytool` 或 Xcode 14 及更高版本。[2] 公证通过后，应将票据 staple 到最终工件，并在隔离属性存在的条件下测试。Apple 说明，票据会让 Gatekeeper 知道该软件已经公证；公证服务也会审查签名问题并返回日志。[2]

## 4. 数据恢复与升级验证

目前备份 schema 版本仍为 `1`，并以可选字段加入安装来源、元数据来源、匹配分数与更新时间。单元测试现已确认旧 schema 1 JSON 在缺失这些字段时可解码，并根据本地可执行路径安全推导来源。为了防止过去的 GitHub owner 头像进入新版本，旧 `iconURLString` 在工具格不再渲染，备份时被清除，导入创建与合并更新时也被忽略。

不过，SwiftData 存储模型的真实升级仍是发布闸门。正式私有 beta 前，必须在**保留旧版 App 容器**的测试账户中启动新版本，验证已有工具、候选、隐藏状态、变量值和历史启动时间均可读取；随后导出并导入备份，确认不存在崩溃、重复记录或数据丢失。若创建 `ModelContainer` 失败，当前版本没有面向用户的恢复向导，因此不得把未做真实升级测试的构建交给外部测试者。

| 恢复场景 | 自动覆盖 | 发行前仍需人工、但仅一次的真实系统验证 |
|---|---|---|
| schema 1 JSON 缺少新增信任字段 | 是 | 否 |
| 旧 JSON 中远程头像 URL | 是 | 否 |
| 导出时 API Key 排除 | 是 | 否 |
| 既有 SwiftData store 打开新版本 | 否 | 是 |
| 导入合并后持久化并重启读取 | 部分 | 是 |
| 旧数据库无法迁移后的用户恢复路径 | 否 | 是，或先实现恢复说明与导入通道 |

## 5. 隐私与使用告知最小内容

私有 beta 的安装说明或应用内隐私页必须清楚说明：工具、候选、命令模板和可选保存的变量值保存在本机；API Key 仅保存于 macOS Keychain 且不导出；GitHub README 搜索与 AI 说明提炼默认关闭、由用户启用后才向其配置的服务端发送必要文本；工具的启动命令只有在用户点击后才发送给所选终端。Terminal.app 或 iTerm 的一键启动会触发 macOS 自动化权限，拒绝授权时应用仅复制已渲染命令，不会绕过系统限制。

隐私告知还应避免把“安装来源”误称为“发行方认证”。Homebrew、Cargo、npm 等字段仅表明发现路径，GitHub 的官方映射或高置信匹配也仅用于元数据补充，不会改变用户本地的启动命令。

## 6. 私有 Beta 放行结论

**结论：暂不放行外部分发。** 目前的开发版本已具备较强的本地信任边界、备份兼容测试和真实 macOS 构建/测试基线，但正式签名、Hardened Runtime、公证、Gatekeeper 冷启动，以及真实 SwiftData 升级验证尚未完成。完成这些项目并通过下一次全量一键验证后，才能形成一个可控的私有 beta 候选；这不等同于公开发行就绪。

## References

[1]: https://help.apple.com/xcode/mac/current/en.lproj/dev033e997ca.html "Apple: Distribute outside the Mac App Store (macOS)"
[2]: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution "Apple: Notarizing macOS software before distribution"
[3]: https://developer.apple.com/documentation/security/hardened-runtime "Apple: Hardened Runtime"
