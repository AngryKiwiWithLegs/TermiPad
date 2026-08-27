# TermiPad 私有 Beta 发布前审计

**审计范围：** 私有开发与受控 beta 候选，不包含 Mac App Store 或外部分发。

**当前已验证功能基线：** `4fe6472`（`Fix local MCP test bridge return`），包含 T2 本机受限 MCP 协作 `3a60ffb` 及其 Swift 6/Core Foundation 兼容修复、T1 本机受限任务执行器 `5edeb8f`、T0 本地受限任务策略核心 `8750200`、此前的本地图标系统 `0265caf` 与 Mendocino 工作区视觉基线 `70d9d40`。

**审计日期：** 2026-08-26。

> 本文是发布闸门，而不是发布说明。它记录已完成的本地工程收口，以及任何外部测试者获得安装包前仍必须满足的独立条件。

## 1. 已完成并在真实 Mac 验证的基线

在用户的 Apple Silicon Mac（Xcode 26.6、Swift 6.3.3、XcodeGen 2.46.0）上，Mendocino 工作区基线 `70d9d40`、本地图标系统批次 `0265caf`、T0 本地受限任务策略核心 `8750200`/修复 `1cb82d3`、T1 本机受限任务执行器 `5edeb8f`/修复 `274d6ea` 与 T2 本机受限 MCP 协作 `3a60ffb`/兼容修复 `030b747`、`f5383d3`、`2564665`、`6569c3a`、`4fe6472` 均已通过 `./scripts/verify-macos.sh` 的完整集中验证。最近一次 T2 回归验证的结果目录为 `20260826-212137`，输出 `TEST EXECUTE SUCCEEDED` 与 `[通过] ui-smoke-test`。该流程还覆盖工具链与脚本语法检查、Swift 源码回归防护、Swift Package 清单检查、XcodeGen 工程生成、原生 macOS 构建、UI Runner 签名校验及单元测试。该批次以 11 英寸 iPad Pro 纵向工作区为首次窗口的视觉基准，并按 macOS 可见区域自适应；它仅强化原生工作区面板、工具卡片和辅助页面层级，不模拟 iPad 设备机身或改变功能/安全行为。UI 测试显式隔离内存数据容器，并在 macOS 仅恢复菜单栏而未恢复窗口时创建主窗口；失败时会自动导出启动状态、界面层级和截图附件。

| 已验证或已实现的控制项 | 当前结论 | 证据或实现位置 |
|---|---|---|
| 用户确认候选后才进入工具库 | 已实现 | `CandidateTool` 状态与 `LaunchpadView.accept` |
| AI 不可生成或覆盖启动命令 | 已实现并有回归测试 | `AIService.swift`、信任边界测试 |
| GitHub 仅接受官方映射或高置信匹配 | 已实现并有回归测试 | `GitHubService.swift` |
| GitHub owner 头像不作工具图标 | 已实现；旧 URL 不渲染、不导出、不恢复 | `ToolIconView.swift`、`BackupService.swift` |
| API Key 不进入备份 | 已实现 | Keychain 存储与 `BackupService.swift` |
| Terminal/iTerm 自动化被拒绝时复制命令 | 已实现；提示文字有单元测试 | `TerminalLauncher.swift` |
| 默认数据容器失败时不删除旧存储 | 已实现 | `TermiPadApp.swift`、`TermiPadDataStore.makeRecoveryContainer` |
| 用户主动导入 JSON 至隔离恢复库 | 已实现并有 UI 冒烟测试 | `DataStoreRecoveryView.swift`、`testRecoveryLaunchOffersBackupImport` |
| iCloud 隐式启用 | 明确禁止 | 所有本地容器显式 `cloudKitDatabase: .none` |
| Mendocino 项目发现预览 | 已实现并在真实 macOS 验证 | 默认关闭；仅用户手动刷新固定公开 GitHub CLI 查询；ETag 缓存、非 fork/非 archived 筛选、公开字段本地解释排序、限流提示与隐私化诊断均有覆盖。不会安装软件、生成命令、写入工具库或自动联网。 |
| P2-B 受控安装审查 | 已实现并在真实 macOS 验证 | 仅内置静态审核的 Homebrew core formula 目录；精确仓库映射；显示预期 CLI、审核修订、日期与固定命令；明确勾选和用户手动确认 Homebrew 后，才可交给已选终端或复制。不会应用内安装、读取 README 命令、支持 tap/cask 或自动收录。 |
| P2-C 只读环境报告 | 已实现并在真实 macOS 验证 | 仅用户点击后在固定绝对路径中以 `--version` 检查 Homebrew、Cargo、npm、pnpm、Bun、Python；不用 shell、不联网、不保存路径/版本；不会安装、升级、卸载或裁决冲突。 |
| Mendocino 工作区视觉强化 | 已实现并在真实 macOS 验证 | 11 英寸 iPad Pro 纵向工作区作为首次窗口视觉基准；macOS 可见区域自适应、原生侧边栏、柔和工作区面板、工具卡片与辅助页面统一层级；不模拟设备外壳或触控系统控件。 |
| 二期本地图标系统 | 已实现并在真实 macOS 验证 | 扩展本地 SF Symbol 目录；未知工具回退样式持久化、确定性分配与碰撞消解；用户手动选择/恢复自动图标；本地 PNG 最高优先级；备份恢复保留样式标识；验证脚本禁止网络图标资源。 |
| T0 本地受限任务策略核心 | 已实现并在真实 macOS 验证 | 固定任务目录、项目范围、短期本地审阅窗口、风险等级、nonce、过期、取消、撤销和固定诊断事件；任务范围与历史不进入 JSON 备份或隐私诊断。T0 仅审阅策略，不执行命令、不创建进程、不接网络、MCP、移动入口或 PTY；验证脚本禁止这些能力。 |
| T1 本机受限任务执行器 | 已实现并在真实 macOS 验证 | 仅消费 T0 已批准的固定任务；以项目范围为当前目录、固定可执行文件和参数、空 stdin/stdout/stderr 运行；支持停止和任务级超时，只保存状态、时间与退出码。无 Shell、PATH 搜索、网络、MCP、移动入口、PTY、终端交接或完整输出保留。 |
| T2 本机受限 MCP 协作 | 已实现并在真实 macOS 验证 | 用户在 Mac 本机明确开启且应用运行时，独立 `stdio` 服务端仅可经本机 CFMessagePort 桥接列出项目范围/固定任务、提出待本机审阅任务、读取最小状态或取消尚未开始任务。桥接不提供认证，但也不开放网络、HTTP/WebSocket、任意 Shell、路径、参数、环境变量、文件浏览、PTY、终端交接或完整输出；stdio 层不直接访问 SwiftData。 |

## 2. 当前阻塞项：不能直接公开或外部分发

当前 `project.yml` 明确使用 ad hoc 签名（`CODE_SIGN_IDENTITY: "-"`），并将 `ENABLE_HARDENED_RUNTIME` 设为 `NO`。这适合开发机上的构建与 UI 测试 Runner 验证，但**不是 Developer ID 分发配置**。因此，当前状态可作为受控开发与自测版本，不能宣称为已准备好供外部下载安装的 release build。

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

## 3. iCloud 同步：已完成设计闸门，未实施功能

iCloud 不是可以用本地开关伪造的功能。它仍需要有效的 Apple Developer 团队、CloudKit 容器与 capability 配置、同步范围和冲突规则确认、迁移策略以及至少两台设备的真实验证。当前版本的显式本地配置与设计文档只是防止未来 entitlement 或容器配置意外开启同步，并不代表 iCloud 已实现。

| 项目 | 当前结论 |
|---|---|
| 本地默认行为 | 已验证为 `cloudKitDatabase: .none` |
| iCloud 设计与验收条件 | 已记录于 `docs/icloud-sync-design-gate.md` |
| Apple Developer 团队与 CloudKit 容器 | 外部前置条件，当前未具备 |
| 多设备冲突、迁移与数据边界验证 | 未开始；不得以本地测试替代 |

## 4. 数据恢复与升级验证

备份 schema 版本为 `1`，并使用可选字段保持旧 JSON 的兼容性。单元测试确认旧 schema 1 JSON 在缺失新增信任字段时可解码，并根据本地可执行路径安全推导来源。旧 `iconURLString` 不会被渲染、导出或恢复；API Key 永不进入 JSON 备份。

默认 SwiftData store 无法创建时，应用不再删除或覆盖原 store，而是打开隔离的恢复库并要求用户主动选择 JSON 备份导入。自动测试已覆盖旧 schema 1 JSON 导入恢复库后保存并重开，以及恢复页面提供导入入口。

| 恢复场景 | 自动覆盖 | 发行前仍需人工、但仅一次的真实系统验证 |
|---|---|---|
| schema 1 JSON 缺少新增信任字段 | 是 | 否 |
| 旧 JSON 中远程头像 URL | 是 | 否 |
| 导出时 API Key 排除 | 是 | 否 |
| 导入合并后持久化并重启读取 | 是 | 否 |
| 默认 store 无法打开时显示安全恢复入口 | 是（受控强制恢复） | 否 |
| 既有 SwiftData store 升级到新版本 | 否 | 是 |
| 真实损坏或无法迁移 store 下的数据完整性与人工恢复 | 否 | 是 |

## 5. 推荐的受控私有 Beta 发行流程

发布负责人应先在干净工作树运行 `./scripts/verify-macos.sh`，并归档 `.verification/<timestamp>/summary.md`、完整日志、`.xcresult` 与 UI 附件。随后以 **Release** 配置归档，使用 Developer ID Application 证书签名，开启 Hardened Runtime。归档后的 app 必须先执行签名与 entitlement 审查，再打包为 DMG、PKG 或 ZIP 之一；打包格式一旦确定，应作为后续 beta 的固定通道，以便复现与回滚。

```bash
codesign --verify --deep --strict --verbose=4 "TermiPad.app"
codesign -dvvv "TermiPad.app"
codesign -d --entitlements :- "TermiPad.app"
spctl -a -vvv --type execute "TermiPad.app"
```

随后应通过 Xcode Organizer 的 Developer ID 分发流程，或用 `xcrun notarytool` 上传公证。Apple 已停止接受 `altool` 与 Xcode 13 或更早版本的公证上传；应使用 `notarytool` 或 Xcode 14 及更高版本。[2] 公证通过后，应将票据 staple 到最终工件，并在隔离属性存在的条件下测试。Apple 说明，票据会让 Gatekeeper 知道该软件已经公证；公证服务也会审查签名问题并返回日志。[2]

## 6. 私有 Beta 放行结论

**P0 已完成代码与真实 macOS 验证收口。P1 中不依赖账户的本地能力也已完成。TermiPad Mendocino 的 P2-A 项目发现、P2-B 受控安装审查、P2-C 只读环境报告，以及 T0/T1/T2 受限任务与本机 MCP 协作均已完成真实 macOS 验证。** 这包括安全的候选收件箱、保守发现、手动管理、命令模板、终端启动/复制回退、信任来源、备份/隔离恢复、收藏/最近使用、诊断、默认关闭的更新检查、本地图标、工具健康检查、每工具工作目录、默认关闭的公开项目发现、静态审核 Homebrew 安装计划、手动触发的本地版本环境报告，以及仅能提出待审阅任务或读取最小状态的本机 stdio MCP 服务端。

**暂不放行外部分发。** 这不是工程代码未完成，而是 Developer ID、Hardened Runtime、公证、Gatekeeper 冷启动和真实旧 store 升级验证尚未具备或尚未执行。iCloud 同步同样保留为真实的 Apple Developer/CloudKit/双设备外部闸门；不得因存在设计文档或本地禁用配置而宣称已实现。P2-B/P2-C 已实现的只是受控安装审查和只读环境报告；自动安装、npm/pip/Cargo 安装、第三方 tap/cask、升级、卸载、依赖求解与冲突裁决均不在当前产品承诺内。

## References

[1]: https://help.apple.com/xcode/mac/current/en.lproj/dev033e997ca.html "Apple: Distribute outside the Mac App Store (macOS)"
[2]: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution "Apple: Notarizing macOS software before distribution"
[3]: https://developer.apple.com/documentation/security/hardened-runtime "Apple: Hardened Runtime"
