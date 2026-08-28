# TermiPad → Launchpad：独立项目 handoff 包

**状态：** 已准备，可供后续任何开发者接手 Launchpad 的 L0/L1；本文件不授权复制 TermiPad 的 CLI、任务执行、MCP 或网络功能。

**交接目标：** 以 TermiPad Mendocino 的已验证原生 macOS 工程经验为基础，孵化一个新的、独立的本地图形应用启动器项目 **Launchpad**。Launchpad 不修改 macOS 系统，也不作为 TermiPad 的附加页面；它拥有新的仓库、Bundle ID、SwiftData 容器、图标目录、测试目标、验证脚本和发布节奏。

---

## 1. TermiPad 冻结基线

| 项目 | 当前事实 |
|---|---|
| 产品 | TermiPad Mendocino，原生 macOS Swift/SwiftUI 应用。 |
| 已验证代码基线 | `0cdbc90`；后续 `d663b08`、`34fdb2f`、`49d7029`、`8e2013b` 为文档/规划提交。 |
| 最近真实 Mac 验证 | 2026-08-27，结果目录 `20260827-115315`，`TEST EXECUTE SUCCEEDED` 与 `[通过] ui-smoke-test`。 |
| 真实验证环境 | Apple Silicon Mac；Xcode 26.6、Swift 6.3.3、XcodeGen 2.46.0。 |
| 当前 T2 状态 | OpenCode 1.14.33 的隔离只读演练已完成并已关闭本机 MCP 与临时服务配置。 |
| 外部分发 | 未完成。无 Developer ID、公证、Gatekeeper 冷启动或真实旧 store 升级验证；不得宣称已发布。 |
| 移动端 | 未实施。原生 iPhone 伴侣、PWA、Telegram 与网络桥接均不得带入 Launchpad MVP。 |

TermiPad 自己仍应保持当前工作边界：面向用户确认的交互式 CLI 工具；T0/T1/T2 任务能力在同一台 Mac 本地、默认关闭并经过审阅。**不要为了 Launchpad 把 TermiPad 的稳定基线改造成图形应用启动器。**

---

## 2. 允许选择性复用的资产

| 资产 | 推荐交接方式 | 复用价值 | Launchpad 中需要调整的点 |
|---|---|---|---|
| `project.yml` | 新建工程后按结构重写。 | macOS 14+、Swift 5.9、XcodeGen、测试 target 和本地 ad hoc 测试签名已验证。 | 彻底替换产品名、target 名、Bundle ID、测试 host 与 Info.plist 文字。 |
| `AppPresentation.swift` | 复制架构，重写 Launchpad 文案。 | 中英文、System/Light/Dark 外观的集中表达模式。 | 移除所有 CLI、网络、密钥和终端文案。 |
| `SoftMacTheme.swift`、`TermiPadWorkspaceStyle.swift`、`WindowPlacementCoordinator.swift` | 复制并更名。 | 原生工作区层级、柔和 macOS 视觉、窗口/多屏适配。 | 调整 Launchpad 自己的初始窗口尺寸与应用网格密度。 |
| `LaunchpadView.swift` 的壳层 | 拆分后复用。 | `NavigationSplitView`、toolbar、搜索状态、图标网格、空状态、sheet、菜单和首次引导模式。 | 不得复制 CLI 扫描、候选收录、AI/GitHub 补充、终端启动或命令编辑部分。 |
| `ToolIconView.swift`、`ToolIconStore.swift` | 保留本地存储/渲染思想，改为 App icon 类型。 | 用户本地 PNG 覆盖、受控缓存、显示回退和无网络图标原则。 | 默认图标应来自真实 `.app` Bundle/`NSWorkspace`，不使用 CLI 工具 symbol 目录。 |
| `TermiPadDataStore.swift` 的工厂模式 | 复制设计，重建 schema。 | 明确本地容器、恢复容器与 CloudKit 禁用原则。 | 使用新的 `LaunchAppEntry`/`LaunchGroup` 模型及独立存储位置。 |
| `UITests/TermiPadUITests/TermiPadUITests.swift` 辅助方法 | 复制测试基础，重写每个用例。 | 真实 App 启动、窗口恢复、可访问元素等待、失败截图和文本层级附件。 | 新 Bundle ID、accessibility identifiers、应用收录数据和启动断言。 |
| `scripts/verify-macos.sh` | 复制工作流，逐条重写。 | 一次集中验证、时间戳结果目录、日志、summary、xcresult 与 UI 附件。 | 重做静态守卫，明确禁止 Shell/MCP/网络/远程启动。 |

---

## 3. 禁止复制的模块

| 模块/类型 | 为什么不能带入 Launchpad |
|---|---|
| `TerminalTool`、`CandidateTool`、`ToolScanner`、`CommandTemplate`、`ToolLaunchContext` | 属于 CLI、PATH 扫描、命令模板和变量输入模型，与 `.app` 启动器无关。 |
| `TerminalLauncher`、`TermiPadCommands`、`AppActions` | 涉及 Terminal/iTerm/Warp、Apple Events、命令复制和终端交接；Launchpad 禁止使用。 |
| `TaskIntent`、`TaskIntentPolicy`、`TaskExecutionService`、`TaskPolicyWorkbenchView` | 属于受限本机任务执行链；Launchpad MVP 不创建任务、不执行进程。 |
| `MCPStdIORuntime`、`TaskMCPBridge`、`TaskMCPSettings` | 属于 TermiPad T2 本机 MCP；Launchpad 不开放 MCP、stdio、IPC 或外部调用。 |
| `AIService`、`GitHubService`、`Discovery*`、`UpdateCheckService` | Launchpad MVP 不联网、不使用 API Key、不做远程元数据补充或远程更新检查。 |
| `ControlledInstallPlan`、`InstallEnvironmentView`、Homebrew/Cargo/npm 相关逻辑 | 图形应用启动器不负责安装、包管理或环境报告。 |
| TermiPad 备份、用户工具、图标、变量、诊断事件或任何 SwiftData store | Launchpad 必须拥有全新的本地数据容器；严禁导入、迁移或读取 TermiPad 用户数据。 |

---

## 4. Launchpad L0 产品契约

Launchpad 的 L0/L1 要解决的是“在一个原生、个人可整理的图标工作区中，浏览并由用户点击打开本机图形应用”。它不是旧 macOS Launchpad 的系统替代品，不管理系统 Dock/Spotlight/手势，也不是文件浏览器或自动化工具。

| 允许的 L1 能力 | 行为约束 |
|---|---|
| 本地 `.app` 目录 | 仅标准 Applications 目录的用户手动刷新，或用户通过系统文件选择器手动选择单个 `.app`。不全盘递归扫描。 |
| 本地图标与显示名 | 从 Bundle/`NSWorkspace` 获取真实本地图标和显示名；可由用户本地覆盖；不下载网络图标。 |
| 搜索、收藏、最近、分组、隐藏、排序 | 只保存用户的最小本地展示偏好和最近启动时间。 |
| 用户点击启动 | 只在用户显式点击卡片后使用正式 AppKit 应用启动接口；不使用 Shell、AppleScript 或自动化脚本。 |
| 最小运行反馈 | 仅显示“已启动、未找到、需要重新收录”等本地结果；不读取窗口内容、文档、进程输出或使用历史。 |

| 永久禁止能力 | 说明 |
|---|---|
| Shell、`Process`、`NSTask`、Terminal、AppleScript | Launchpad 不执行命令，也不模拟终端操作。 |
| HTTP、WebSocket、`URLSession`、网络 listener、MCP、stdio、CFMessagePort | 不存在网络或远程控制面。 |
| 手机、PWA、Telegram、通知触发、定时任务、批量/后台自动启动 | 所有启动均保留在用户本机的单次点击。 |
| 文件浏览、全盘扫描、读取应用内容、收集窗口/文档/输出 | 仅管理用户已选中的 `.app` 卡片。 |
| 任何 TermiPad 数据互通 | 两个项目独立运行、独立持久化、独立备份和独立诊断。 |

---

## 5. 接手规则：如何避免重复人工验证

每次有意义的修改都要先在仓库中完成静态审计、最小单元测试更新、XcodeGen 工程生成和提交推送，然后**只请求一次**用户 Mac 集中验证。用户的唯一标准命令应当从新项目根目录运行：

```bash
cd ~/Launchpad && git pull --ff-only origin master && ./scripts/verify-macos.sh
```

后续开发者必须向用户索取 `summary.md` 的末尾通过/失败摘要，而不是让用户逐个点击、粘贴完整日志或尝试未验证的临时命令。若 UI 失败，优先利用验证脚本导出的 `.xcresult`、截图和 accessibility/UI tree 附件定位共同根因，再进行最小修复。不要根据一张截图猜测实现状态，也不要因一次测试失败扩大产品范围。

| 验证层 | Launchpad 应有的断言 |
|---|---|
| 静态守卫 | 源码不得使用 Shell、进程、Terminal/AppleScript、MCP、网络客户端/监听器或远程启动。 |
| 单元测试 | 应用条目去重、标准目录过滤、用户分组、收藏/隐藏、排序、丢失 App 与本地书签恢复。 |
| UI 冒烟 | 首次引导、窗口恢复、目录空状态、搜索、收藏、设置、中英文、三档外观和用户点击启动确认。 |
| 失败附件 | 每次失败自动保存 summary、日志、xcresult、截图和 UI 层级，不依赖用户描述视觉细节。 |

---

## 6. 推荐的首个 Launchpad 提交顺序

1. 建立全新私有仓库与空的 XcodeGen macOS 工程；新建 Bundle ID、本地容器和测试 target。
2. 移植并更名展示层、窗口样式、空状态/侧边栏/工具栏框架、图标缓存和 UI 测试辅助方法。
3. 先写 `LaunchAppEntry`、`LaunchGroup`、`LaunchSource` 与明确的本地隐私契约，不实现目录扫描。
4. 在第一版 `verify-macos.sh` 写入禁止项，确保后续不会误带入 TermiPad 的 CLI/MCP/网络源文件。
5. 仅在结构验证通过后实现一个手动添加 `.app` 的概念验证；此时才开始真实 Mac 的一条集中验证。

这份 handoff 足以让熟悉 TermiPad 的开发者连续推进，也足以让新人或新协作会话在不读取用户私密数据的前提下接手。任何超出 L1 的能力，都必须先更新产品契约与静态守卫，再编写运行时代码。
