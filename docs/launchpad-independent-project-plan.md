# Launchpad：基于 TermiPad 架构的独立 macOS 应用启动器项目方案

**状态：** 产品孵化与架构决策稿。本文不会改动 TermiPad，也不会创建 Launchpad 仓库、拷贝用户数据、扫描应用或启动任何 App。

**澄清：** Launchpad 是一个**新的、独立的原生 macOS 项目**。它借鉴并选择性复用 TermiPad 已验证的工作区、图标、本地持久化和自动化验证方法；它不修改 macOS 系统功能，也不作为 TermiPad 的新页面或功能开关。

---

## 1. 建议结论

> **建议这样做。** 将 Launchpad 建立为 TermiPad 的 sibling project（兄弟项目），而不是在 TermiPad 中继续叠加“图形应用启动器”业务。两个项目可共享原生工作区体验与验证方法，但必须拥有独立产品名称、Bundle ID、本地数据容器、诊断包、测试目标和发布节奏。

TermiPad 的核心是用户确认的交互式 CLI 工具及其受控启动、任务审阅和本机 MCP 边界。一个应用启动器的核心则是图形应用目录、图标、个人分组、搜索、收藏与用户点击启动。如果两者混在同一个数据模型和导航中，TermiPad 的“固定命令 + 终端交接”风险说明会污染轻量应用启动体验；反过来，Launchpad 的大规模图标目录会稀释 TermiPad 的任务审阅和安全状态。因此，**共享架构，分离产品**是最稳健的设计。

| 决策 | 建议 | 原因 |
|---|---|---|
| 项目关系 | 新建独立私有仓库，而非继续改 TermiPad。 | 数据、测试、发行、用户心智和安全面可独立演进。 |
| 初始技术栈 | macOS 14+、Swift 5.9、SwiftUI、SwiftData、AppKit、XcodeGen、XCTest/XCUITest。 | 直接承接已在真实 Apple Silicon Mac 验证的构建和测试方法。 |
| 项目名称 | 产品暂称 **Launchpad**；代码仓库建议先使用不与系统名混淆的工作名，例如 `LaunchDeck`。 | “Launchpad”与 Apple 历史功能名称高度接近，面向公开发布前应做名称与商标清查；这是产品风险提示，不是法律意见。 |
| 初始范围 | 本地应用目录、用户点击启动、图标网格、搜索、收藏、最近使用、手动分组、浅/深/系统外观、中英文。 | 先覆盖旧 Launchpad 最核心的个人启动体验。 |
| 明确不做 | 不扫描全盘、不浏览文件、不执行 Shell、不含 CLI 命令、不接 MCP/手机/Telegram/网络、不自动启动。 | 保持一个轻量、可解释、可撤销的本地启动器。 |

---

## 2. Launchpad MVP：应做什么，不应做什么

### 2.1 L1 最小产品体验

Launchpad 首次运行应呈现一个符合 macOS 原生习惯的工作区：左侧是“全部应用、收藏、最近使用、分组”，顶部是搜索、显示方式和整理入口，主内容区为响应式图标网格。它可以视觉上让人联想到传统 Launchpad 的可浏览性，但不模拟 iPad 机身、Dock、状态栏或全局手势。

应用目录的来源应当清晰且可控。第一个版本建议从两个标准本地目录开始：`/Applications` 与用户自己的 Applications 目录；用户在设置中可以关闭任一目录，也可以手动通过系统文件选择器添加一个 `.app`。刷新必须由用户明确点击，不应后台持续扫描。对每一个可显示项目，只读取显示名、Bundle ID、本地图标、应用 URL 和本地存在状态，不读取应用文件内容、用户文档、窗口内容、钥匙串、命令行参数或使用记录。

用户单击图标时，Launchpad 通过 `NSWorkspace` 的正式应用启动 API 打开该 App，而不是用 Shell、AppleScript 或模拟键盘输入。`NSWorkspace` 是 AppKit 提供的工作区接口，支持按应用 URL 启动应用并观察工作区状态。[1] 每次启动必须由用户直接点击，不提供批量启动、规则触发、后台队列、快捷自动化或远程调用入口。

| L1 能力 | 行为契约 | 用户体验 |
|---|---|---|
| 标准目录收录 | 仅在用户点击“刷新应用目录”时读取受控目录内的 `.app` 条目。 | 类似传统 Launchpad 的“所有应用”入口，但不做隐蔽全盘扫描。 |
| 手动添加 | 只能由用户通过 `NSOpenPanel` 选择单个 `.app`。 | 支持放在非标准位置的个人 App。 |
| 本地图标 | 使用 App Bundle 或 `NSWorkspace` 返回的本地图标，允许用户本地自定义图标。 | 图标与真实应用对应，不依赖在线头像或 AI 推断。 |
| 收藏、最近、分组 | 只保存用户本机的显示排序和最小启动时间。 | 补回旧 Launchpad 的日常可用性。 |
| 搜索和键盘导航 | 在当前目录中本地筛选、支持 Tab/方向键/Return。 | 不需要记住 App 的完整名称或路径。 |
| 启动状态 | 只显示“已启动/应用不存在/需要重新收录”等最小结果。 | 保持反馈清晰，不窥视应用内部。 |

### 2.2 永久边界

| 不做事项 | 不做原因 |
|---|---|
| 修改 macOS Launchpad、Spotlight、Dock、系统数据库、全局热键或触控板手势。 | 新项目是独立 App，不替代系统组件，也不依赖未公开的系统内部实现。 |
| 递归扫描 Home、桌面、文稿、外接盘、网络卷或云盘。 | 这会把启动器扩展为文件浏览器，显著放大隐私面。 |
| 展示或启动系统命令、守护进程、包管理器、脚本、安装器或 Terminal。 | Launchpad 的对象是图形 `.app`，CLI 业务留在 TermiPad。 |
| 以 AI、远程元数据或网页自动补全应用信息/图标。 | 目录与图标必须来自用户 Mac 本地 Bundle 或用户的明确选择。 |
| 通过 MCP、手机、网页、Telegram、HTTP、WebSocket、通知或定时任务启动应用。 | 所有启动保持用户在本机窗口中的显式点击。 |
| 读取应用内容、进程输出、窗口标题、文档、浏览器历史或通信数据。 | Launchpad 只管理“可启动的 App 卡片”，不观察用户在 App 中做什么。 |

---

## 3. 从 TermiPad 复用什么，必须丢弃什么

### 3.1 高价值可复用层

TermiPad 不是应该“整库 fork 后改名字”的模板；它是一套已经经过真实 macOS 验证的原生工程骨架。Launchpad 应以**复制经筛选的基础层**开始，并在新的数据模型上重建应用启动业务。

| 资产组 | 建议处置 | 原因与迁移方式 |
|---|---|---|
| `project.yml` | **复制并重命名。** | 保留 macOS 14+、Swift、XcodeGen、测试目标和本地 ad hoc 测试签名；替换所有 target、产品名和 Bundle ID。 |
| `AppPresentation.swift` | **复制并泛化。** | 可直接承接中英文、浅色/深色/系统外观和集中短文案；删除 TermiPad 专属键名与安全提示。 |
| `SoftMacTheme.swift`、`TermiPadWorkspaceStyle.swift`、`WindowPlacementCoordinator.swift` | **复制并更名。** | 复用原生工作区留白、面板层级、窗口尺寸和适配方式；不复制“iPad 设备外框”类视觉。 |
| `LaunchpadView.swift` 的导航壳、工具栏、搜索、网格、空状态、悬停和 sheet 模式 | **拆分后复用。** | 应提炼出通用 `WorkspaceShell`、`IconGrid`、`EmptyState`、`AppearanceControl`；不带入 CLI 工具扫描/编辑/启动代码。 |
| `ToolIconView.swift`、`ToolIconStore.swift` | **复用机制，不复用目录。** | 本地受控 PNG、手动覆盖、稳定回退和渲染层值得保留；应用卡片默认要用真实 Bundle 图标，不沿用 CLI 工具的语义 symbol 表。 |
| `TermiPadUITests.swift` 的 `launchApp`、窗口恢复、附件导出辅助方法 | **复制并改 Bundle ID/identifier。** | 这是“少让用户手点”的关键资产：真实启动、等待、点击、断言、截图和 UI 层级诊断。 |
| `verify-macos.sh` | **复制为 Launchpad 版本并重新编写守卫。** | 保留一条命令的闭环；移除 T0/T1/T2/MCP 专属守卫，增加“无 Shell/无网络/无远程启动”等 Launchpad 守卫。 |

### 3.2 必须留在 TermiPad 的逻辑

以下文件或职责不应原样进入新项目，因为它们绑定 CLI、终端、AI/网络补充、受限任务或 MCP 设计。

| TermiPad 层 | Launchpad 处理方式 | 说明 |
|---|---|---|
| `TerminalTool.swift`、`CandidateTool`、`ToolScanner.swift` | 新建 `LaunchAppEntry`，不继承。 | 现有模型包含 executable path、命令模板、变量、工具来源和 CLI 分类。 |
| `TerminalLauncher.swift`、`CommandTemplate.swift`、`ToolLaunchContext.swift` | 完全不复制。 | Launchpad 只打开 `.app` Bundle，不构造命令，不调用 Terminal/iTerm/Warp。 |
| `TaskIntent*`、`TaskExecutionService.swift`、`TaskMCP*`、`MCPStdIORuntime.swift` | 完全不复制。 | 这些是 TermiPad 特有的任务与本机 MCP 安全链。 |
| `AIService.swift`、`GitHubService.swift`、`Discovery*`、`UpdateCheckService.swift` | 初始版本不复制。 | Launchpad MVP 不需要网络、API Key、远程发现或远程更新源。 |
| `ControlledInstallPlan.swift`、`InstallEnvironmentView.swift` | 完全不复制。 | 图形应用启动器不承担安装、包管理或环境审查职责。 |
| TermiPad 的备份 JSON 格式与恢复模型 | 不直接兼容；可另设 Launchpad 专属本地导出。 | 不应把 CLI 命令、工具变量或任何 TermiPad 数据迁入新项目。 |

### 3.3 Launchpad 新建的数据模型

新项目应在自己的 SwiftData 容器中定义 `LaunchAppEntry`、`LaunchGroup` 与 `LaunchSource`。最小记录只保存展示和启动所需字段；诊断导出不包含原始路径。

| 模型字段 | 用途 | 限制 |
|---|---|---|
| `id` | 本地不透明标识。 | 不上传。 |
| `displayName`、`bundleIdentifier` | 标题、去重与搜索。 | 允许用户本地别名；不用于网络查询。 |
| `appURL` 或安全范围 bookmark | 定位用户已收录的 `.app`。 | 原始 URL 不写入诊断或远程接口。 |
| `source` | `systemApplications`、`userApplications`、`userSelected`。 | 仅解释来源，不代表安全认证。 |
| `isFavorite`、`isHidden`、`groupID`、`sortIndex` | 本地个人整理。 | 不共享、不自动同步。 |
| `lastLaunchedAt` | 最近使用排序。 | 不记录使用时长、窗口内容或行为轨迹。 |
| `iconFilename`（仅自定义图标时） | 本地受控图标覆盖。 | 默认使用真实 Bundle 图标，不下载网络素材。 |

---

## 4. 新仓库、命名和验证策略

### 4.1 仓库创建方式

建议创建一个新的**私有** GitHub 仓库，而不是 fork TermiPad。fork 会把全部提交历史和 TermiPad 的 MCP/任务/CLI 代码带到新项目，既增加审计成本，也让产品边界模糊。新仓库应从一个干净的 XcodeGen 工程建立，然后选择性复制已审查的基础文件。README 首屏应声明“独立本地图形应用启动器；不含 CLI 终端、MCP、远程控制或网络服务”。

产品显示名可以在内部原型阶段暂称“Launchpad”，但计划公开分发、域名、商店上架或商标使用前，应检查其与 Apple 历史产品名称及同类软件名称的混淆风险。这是一般产品风险提醒，不构成法律意见；届时应由熟悉目标地区的知识产权专业人士审查。

| 项目身份项 | TermiPad | 新项目建议 |
|---|---|---|
| 仓库 | `AngryKiwiWithLegs/TermiPad` | 新建私有 `AngryKiwiWithLegs/LaunchDeck`（工作名，可在确认后调整）。 |
| 工程名 | `TermiPad` | `LaunchDeck` 或经最终命名确认后的独立名称。 |
| Bundle ID | `com.termipad.app` | 全新 ID，例如 `com.angrykiwi.launchdeck`；最终值应由仓库/发行主体统一决定。 |
| 本地数据 | TermiPad SwiftData 容器。 | 新容器、独立 Application Support 目录，不读取或迁移 TermiPad 数据。 |
| 图标目录 | TermiPad 受控工具图标目录。 | 独立图标目录，只缓存用户选定的应用卡片覆盖图。 |
| 诊断包 | TermiPad 固定隐私类别。 | 新的 Launchpad 事件类别，禁止输出原始应用路径和用户数据。 |

### 4.2 一次集中验证的迁移方式

Launchpad 从第一天起应拥有 `scripts/verify-macos.sh`，不是等 UI 做完后才补。它应检查 Xcode/XcodeGen、脚本语法、Swift 静态边界、单元测试、工程生成、macOS 构建和 UI 冒烟，并把日志、`summary.md` 与 `.xcresult` 附件保存在一个时间戳目录。

| Launchpad 验证组 | 需要覆盖的断言 |
|---|---|
| 静态边界 | Launchpad 不引用 `Process`、`NSTask`、`NSAppleScript`、`URLSession`、MCP stdio、WebSocket、HTTP listener 或 Shell 字符串。 |
| 单元测试 | Bundle 去重、用户分组、收藏/隐藏、排序、标准目录过滤、手动选择的书签恢复、丢失 App 提示。 |
| UI 冒烟 | 首次引导、全部应用、搜索、收藏、空状态、分组、设置、中英文、浅/深/系统外观，以及启动确认 UI。 |
| 启动隔离 | 使用独立内存容器或测试目录，绝不读取用户真实应用目录或改写用户实际收藏。 |
| 失败附件 | 自动导出截图、Accessibility/UI 层级和 `.xcresult`；用户只需发送末尾摘要。 |

---

## 5. 推荐推进顺序与需要确认的事项

目前建议只进入 **Launchpad L0：独立项目设计冻结**，而不是立即创建仓库。L0 的目标是以少量产品决定换取后续实现和验证稳定性。

| 需要你确认的问题 | 建议默认值 | 对后续的影响 |
|---|---|---|
| 是否使用新独立项目？ | 是，TermiPad 的 sibling project。 | 决定创建新私有仓库和新 Bundle ID。 |
| 产品/仓库工作名 | 仓库先用 `LaunchDeck`，界面文案可暂用“Launchpad”。 | 避免在工程、Bundle ID 和公开品牌之间过早锁死名称。 |
| 应用收录方式 | 默认标准目录的手动刷新 + 用户手动添加。 | 兼顾传统 Launchpad 覆盖度与本地隐私。 |
| 是否允许自动发现？ | 不后台自动；只允许用户在本机点击刷新。 | 决定是否需要标准目录访问与刷新说明。 |
| 是否与 TermiPad 工具同屏？ | 不同屏；两个 App 分别运行。 | 保持两个产品数据和安全模型清晰。 |
| 下一开发动作 | 完成 L0 设计后，再创建私有仓库并实施 L1 MVP。 | 不会触发 iPhone、MCP、网络、Shell 或现有 TermiPad 改动。 |

---

## 参考资料

[1]: https://developer.apple.com/documentation/appkit/nsworkspace "Apple Developer: NSWorkspace"
[2]: https://developer.apple.com/design/human-interface-guidelines/toolbars "Apple Human Interface Guidelines: Toolbars"
[3]: https://developer.apple.com/design/human-interface-guidelines/layout "Apple Human Interface Guidelines: Layout"
[4]: https://developer.apple.com/documentation/xcuiautomation/xcuiapplication "Apple Developer: XCUIApplication"
[5]: https://developer.apple.com/documentation/xctest "Apple Developer: XCTest"
