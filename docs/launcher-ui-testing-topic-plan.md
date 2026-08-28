# TermiPad 启动器扩展、原生 UI 体系与自动化验证专题方案

**状态：** 研究与产品决策稿；尚未实现 Launchpad 扩展，亦不改变现有 T0/T1/T2 安全边界。

**适用基线：** TermiPad Mendocino，T2 已在用户的 Apple Silicon Mac 上完成集中验证和 OpenCode 隔离只读演练。本文不重新打开本机 MCP，不引入移动端、Telegram、PWA、网络监听或远程执行。

---

## 1. 结论摘要

> **可以做，但不应尝试“恢复或篡改 macOS 原来的 Launchpad”。** 正确产品方向是：TermiPad 在现有“用户确认的直接交互式 CLI 工具启动器”之外，提供一个单独开启、独立命名的 **Launch Deck（应用启动甲板）**。它在自己的窗口中提供传统 Launchpad 擅长的可视图标浏览、搜索、收藏、最近使用与手工分组，并在用户点击后调用 macOS 的正式应用启动接口。

macOS Tahoe 26 的官方使用路径仍是 Spotlight：用户可以通过 `Command-Space`、菜单栏图标或功能键启动 Spotlight，搜索并打开应用、文件和动作。[1] 第三方应用不能恢复旧 Launchpad 的系统数据库、Dock 行为、系统手势或 Apple 的 Spotlight 应用浏览界面；这些都是操作系统拥有的体验。TermiPad 能做的是提供一个**不替换系统、但可成为个人偏好启动入口**的独立原生应用窗口。

这项扩展有现实价值，但应被定义为 **L 系列启动器工作流**，不应混入 TermiPad 的核心安全职责。它可以服务“我需要从一个舒适的图标空间快速启动个人常用 App 和已审核 CLI 工具”的需求；它不能变成全盘文件浏览器、自动化平台、系统命令中心或远程控制面。

| 问题 | 专题结论 |
|---|---|
| 能否恢复 Apple 旧 Launchpad？ | **不能，也不应尝试。** 不能更改系统 Launchpad、Dock 内建项目、系统数据库、手势或 Spotlight。 |
| 能否做更好用的图标启动器？ | **能。** 做 TermiPad 自己的原生 Launch Deck，使用用户点击发起的 `NSWorkspace` 应用启动。 |
| UI 质量是否来自一个“神秘模块”？ | **不是。** 它来自可审计的设计约束、原生组件选择、集中复制文案、图标规则、可访问性标识和反复验证的组合。 |
| 能否交给其他人复用？ | **能，但不能只复制一个 View。** 应交接设计规则、相关组件组、数据模型、UI 测试和验证脚本。 |
| 为什么能少让人手点？ | 因为项目把“能自动的验证”写入可重复脚本，并用 UI 自动化实际启动 App、点击控件、等待状态、断言结果、导出截图和诊断。 |

---

## 2. L 系列：TermiPad Launch Deck 的产品定义

### 2.1 产品定位

**Launch Deck 是 TermiPad 的可选本地应用启动层，不是系统 Launchpad 的替身，也不是终端。** 它在同一个原生 macOS 工作区里，提供两种显式、视觉上可辨别的对象：已审核的 CLI 工具卡片与用户选择纳入的图形应用卡片。前者延续既有 TermiPad 工具库边界；后者只启动应用 Bundle，不生成、重写或执行命令。

推荐将其作为侧边栏中的一个新一级入口，例如“应用启动甲板 / Launch Deck”。不建议覆盖当前“工具库 / Library”首页，也不建议使用“Launchpad”作为产品名，避免暗示与 Apple 系统功能存在替换关系。

### 2.2 可实现能力

Apple 的 `NSWorkspace` 是 macOS 官方的工作区接口，可按应用 URL 启动 App，获得运行中应用状态、应用图标和部分工作区通知。[2] 因此 Launch Deck 可以受控地提供如下能力。

| 功能 | 用户价值 | 实现边界 |
|---|---|---|
| 标准位置应用收录 | 从常见应用目录中构建个人启动卡片。 | 仅检查预定义的应用目录，或让用户在文件选择器中明确选取 `.app`；不做全盘递归扫描。 |
| 原生图标 | 让图标与真实 App 对应，而非 AI 临时指定。 | 使用 Bundle/`NSWorkspace` 提供的本地图标；不下载头像、品牌图片或网络图标。 |
| 搜索、收藏、最近使用、手动分组 | 补回传统 Launchpad 的高频浏览效率。 | 数据仅保存本机；分类与排序由用户控制，不使用远程元数据或 AI 自动更改。 |
| 用户点击启动 | 直接打开一个用户已安装的图形应用。 | 只允许由用户的显式点击触发 `NSWorkspace.openApplication`；不使用 Shell、AppleScript、终端交接或后台队列。 |
| 运行状态提示 | 让卡片在“已打开”时具有可见反馈。 | 只显示 Bundle ID/显示名级别的本地状态；不采集窗口内容、文件、命令行或应用数据。 |
| 可选菜单栏入口 | 对高频使用者提供一个进入 Launch Deck 的入口。 | 仅显示/隐藏 TermiPad 自己的窗口；不模拟系统菜单栏或全局监听键盘。 |

### 2.3 明确不做的事项

以下内容是 L 系列的否决项，不因“更像旧 Launchpad”而重新开放。

| 不做事项 | 原因 |
|---|---|
| 修改、读取或恢复 Apple 旧 Launchpad 数据库和文件夹。 | 不稳定、非公开、易随系统升级失效，且不属于 TermiPad 的授权边界。 |
| 替代 Spotlight、劫持 `Command-Space`、Dock 项或系统手势。 | 会与系统级导航冲突，并需要不必要的全局权限与常驻行为。 |
| 递归浏览用户 Home、外接盘、工作文件夹或网络卷。 | 会把启动器变成文件浏览器，扩大隐私和安全面。 |
| 扫描或展示系统工具、后台服务、守护进程、脚本、包管理器或安装器。 | 违反 TermiPad 只面向用户直接交互工具的既定范围。 |
| 自动启动、批量启动、定时启动或由 MCP/手机/网络触发启动应用。 | 破坏“用户本机显式点击”控制原则。 |
| 把图形应用与 CLI 命令混合成可由 AI/MCP 重写的动作。 | AI、远程元数据和 MCP 都不得改写用户固定工具命令或启动目标。 |

### 2.4 建议数据模型

为避免污染既有 `TerminalTool` 模型，新增独立、最小的 `LaunchDeckApp` 持久化记录。它应只记录足以恢复用户界面的字段。

| 字段 | 用途 | 隐私与安全约束 |
|---|---|---|
| `id` | 本地不透明主键。 | 不上传。 |
| `bundleIdentifier` | 去重、检测 App 是否仍存在。 | 不把它用于网络查询。 |
| `displayName` | 卡片标题。 | 取本地 Bundle 显示名，允许用户本地别名。 |
| `bookmarkData` 或受控 URL 引用 | 为用户明确选择的非标准应用保留授权。 | 只在必要时保存安全范围书签；不显示原始路径给 MCP/移动端/诊断。 |
| `sourceKind` | `standardDirectory` 或 `userSelected`。 | 用于界面解释，不引入可信度承诺。 |
| `isFavorite`、`isHidden`、`groupID`、`lastLaunchedAt` | 本地排序与组织。 | 不收集应用使用时长或窗口内容。 |
| `iconFingerprint`（可选） | 判断本地图标缓存是否需刷新。 | 图标只缓存于受控本地目录；不联网。 |

不要把 `.app` 的可执行文件路径、Info.plist 全量、签名信息、用户文件或运行输出复制到诊断包。发布前如需增强来源说明，应另行设计、用户可见且可关闭，而不是暗中扩大采集。

---

## 3. L0–L3 分阶段实施建议

> 本方案建议先做 L0 和 L1；L2/L3 只有在前两阶段获得真实使用反馈、并再次确认不扩大安全面时才进入排期。

| 阶段 | 范围 | 验收条件 | 典型风险 |
|---|---|---|---|
| **L0：设计与安全契约** | 数据模型、收录范围、明确禁区、文案和 UI 信息架构。 | 方案评审通过；不改现有运行时代码。 | 误把系统 Launchpad 替换承诺写进产品。 |
| **L1：本地启动甲板 MVP** | 用户主动收录、标准目录轻量发现、本地图标、搜索/收藏/分组、单击启动、原生设置页。 | 每次启动均由用户点击；单元测试和 UI 冒烟覆盖。 | Bundle 变化、重复收录、窗口尺寸适配。 |
| **L2：可靠性与可发现性** | 丢失 App 提示、图标刷新、运行状态、菜单栏“显示甲板”入口、快捷键提示。 | 所有观察均为本机最小状态；无全局键盘监听。 | 把便利性演化成后台常驻自动化。 |
| **L3：跨设备产品设计（仅设计）** | 明确未来 iPhone 伴侣可见的只读目录与本机审批边界。 | 不启动网络配对，不传输路径/命令/输出。 | 过早把 Launcher 接入远程控制。 |

**建议当前只批准 L0。** 原因不是技术难度，而是产品中心需要先回答：Launch Deck 是“个人 App 收藏入口”，还是“TermiPad 统一工作空间”的一部分；两者的数据边界、默认入口、侧边栏优先级和发布叙事不同。

---

## 4. TermiPad UI 为什么能接近原生标准

### 4.1 不是独立魔法模块，而是一组可复用约束

当前 UI 的质量并非由某个封闭组件自动产生。它来自一套可追踪的工程组合：用 SwiftUI/AppKit 的系统布局承载交互，用 `AppPresentation.swift` 集中语言和外观，用图标、工具卡片、侧边栏、工具栏和空状态建立信息层级；再用稳定 accessibility identifier 和 UI 测试让关键路径持续可验证。

Apple 的 HIG 明确建议工具栏只放高频命令、将项目按逻辑分组、优先使用系统组件和无边框系统符号，并让 macOS 的菜单栏始终保留工具栏命令的替代入口。[3] 布局则应通过 SwiftUI 或 Auto Layout 适应窗口大小、文本长度和系统外观，使用清晰分组、留白、对齐和渐进披露建立层级。[4]

| 设计层 | 当前 TermiPad 资产 | 可迁移原则 |
|---|---|---|
| 信息架构 | 原生侧边栏入口：工具库、收件箱、发现、安装与环境、任务工作台、设置。 | 先划分稳定工作区，再在工作区内放具体控件；不要用一张大卡片包裹所有功能。 |
| 系统导航 | `NavigationSplitView`、窗口标题、`toolbar`、菜单栏命令。 | 在 macOS 使用侧边栏 + 工具栏 + 菜单命令，不模拟 iPad 机身、状态栏或 Home 指示条。 |
| 外观与文字 | `Sources/AppPresentation.swift` 中的 `AppLanguage`、`AppAppearance`、`AppCopy`。 | 将语言、外观和 UI 短文案集中，不在每个 View 内散落条件字符串。 |
| 图标语言 | `Sources/ToolIconView.swift`、`Sources/ToolIconStore.swift` 与本地受控 PNG。 | SF Symbols 负责通用动作，真实工具/App 的本地图标负责识别；不使用网络头像和重复装饰图。 |
| 交互节奏 | 系统控件、悬停帮助、右键菜单、原生 sheet、分段选择。 | 少量明确主操作；重要操作留给用户点击；避免过大圆角、过度渐变和自定义仿移动端控件。 |
| 本地状态 | 即时保存、可见状态说明、失败时提示、恢复模式。 | 对用户必须知道的“已保存/已关闭/待审核”给出简洁、持续的本地反馈，不增加多余全局保存按钮。 |
| 可访问性 | 语义名称与稳定 identifier；避免依赖 SwiftUI 合并层级的脆弱断言。 | identifier 用在稳定的可访问控件上，UI 测试验证用户实际能看见/操作的边界，而不是框架内部结构。 |

### 4.2 可直接交接的代码资产，而非只交付截图

其他开发者要复用 TermiPad 的原生体验，应从下列资产组开始，而不是只复制 `LaunchpadView.swift` 的一段布局。文件之间有数据模型、文案、图标存储和测试依赖；孤立复制一个 View 通常会得到“像图、但不稳定”的结果。

| 交接层级 | 建议交接文件或目录 | 交接目的 | 不能照搬的部分 |
|---|---|---|---|
| 视觉基础 | `Sources/AppPresentation.swift` | 中英文、三档外观、统一 UI 文案。 | 具体产品词汇、敏感操作文案。 |
| 启动器界面 | `Sources/LaunchpadView.swift` | 侧边栏、工具栏、搜索、图标墙、悬停说明、空状态的组织方法。 | 现有 CLI 数据模型和启动逻辑。 |
| 图标体系 | `Sources/ToolIconView.swift`、`Sources/ToolIconStore.swift` | 本地图标优先、可控自定义图标、回退规则。 | 不应改造成远程头像或 AI 生成图标的自动下载器。 |
| 状态和安全界面 | `Sources/TaskPolicyWorkbenchView.swift` | 长期安全状态如何在不造成噪声的前提下可见。 | T0/T1/T2 的策略内容只能在同等安全模型下复用。 |
| 交互测试 | `UITests/TermiPadUITests/TermiPadUITests.swift` | 启动、首启引导、侧边栏、页面可见性、失败截图和生命周期恢复。 | Bundle ID、测试环境开关、产品专属 identifier。 |
| 集中验证 | `scripts/verify-macos.sh` | 一次命令汇总语法、守卫、单测、构建、UI 测试和 `.xcresult` 附件。 | 现有安全关键词清单需按新产品重新审计。 |

### 4.3 “照抄”应采用的交接包结构

建议在未来将当前代码整理为一个**内部复用包**，而不是现在就把所有业务源文件公开复制。推荐交接包由下列四件组成：一份设计契约、一组可移植 View、一个小型 design token/文案层和一套 UI 自动化骨架。

```text
NativeWorkspaceKit/                 # 未来内部复用包，当前尚未创建
  DesignContract.md                 # 平台、布局、颜色、动效、可访问性规则
  Presentation/                     # 外观、语言、文案、symbol 选择约定
  Components/                       # SidebarShell、WorkspaceToolbar、IconGrid、StatusRow
  Testing/                          # UI test helpers、attachment helpers、launch isolation
  Examples/                         # 不含用户工具、命令、路径、凭据或真实数据的示例
```

这不是“把 UI 变成一键生成器”。代码能复用组件，**无法替代信息架构、产品词汇、状态机和安全审计**。其他人若要做金融、医疗、企业管理或远程控制类 App，必须重新定义数据和权限边界，不能拿 TermiPad 的视图来暗示自己同样安全。

---

## 5. 自动化 UI 测试：如何做到少让用户重复手点

### 5.1 当前工程的实际机制

TermiPad 并不是让测试“看截图猜对错”。它使用 Apple 的 `XCTest` 和 `XCUIAutomation` 来启动 App、传递隔离环境、查找可访问元素、点击侧边栏和首次引导控件、等待异步状态、断言页面边界，然后在结束时终止 App 并导出诊断附件。Apple 将 `XCUIApplication` 定义为用于启动、监视和终止测试 App 的代理，并提供启动参数、启动环境、状态等待、激活、终止与 accessibility audit 等 API。[5] `XCTest` 则明确支持用 XCUIAutomation 复现交互序列，并保存附件作为失败诊断。[6]

当前 `UITests/TermiPadUITests/TermiPadUITests.swift` 的结构可概括为：

1. 每个场景用 `XCUIApplication(bundleIdentifier: "com.termipad.app")` 启动真正的 macOS App。
2. 通过 `-ApplePersistenceIgnoreState`、`TERMIPAD_UI_TEST_MODE` 和特定环境变量获得可重复的首启、设置或恢复模式，而不触及用户真实工具库。
3. 如 macOS 恢复了菜单栏却没有恢复窗口，测试通过应用菜单中的 **New Window** 建立可访问主窗口；这处理了真实 Mac 的窗口恢复差异。
4. 使用稳定的可访问性 identifier 查找控件，先 `waitForExistence` 再点击，减少“界面还没来得及出现”的伪失败。
5. 对每个工作区同时检查“应出现的关键控件”和“不应出现的越界控件”。例如任务工作台必须有本机 MCP 许可说明，而不应出现工具发现按钮。
6. 测试结束后保存屏幕截图和文本层级；脚本会从 `.xcresult` 导出附件，使问题可定位而不是只得到红色失败行。

### 5.2 一条命令为什么比反复手动测试可靠

`scripts/verify-macos.sh` 是目前的“本机 CI 替身”。它不是只跑一次构建，而是按固定顺序执行工具链检查、Shell 语法检查、Swift 源码安全守卫、Swift Package 清单检查、单元测试、XcodeGen 工程生成、原生构建、UI Runner 签名校验和 UI 冒烟测试；任一步失败都会写入同一时间戳目录的日志和 `summary.md`。UI 失败时还会从 `.xcresult` 自动导出文本、截图和视频附件。

| 验证层 | 自动验证的问题 | 人工验证仍不可替代的部分 |
|---|---|---|
| 静态安全守卫 | 禁止网络、任意 Shell、PTY、输出管道、直接 SwiftData 竞争等回归。 | 新功能的产品意图和安全模型是否合理。 |
| 单元测试 | 数据模型、策略状态机、拒绝路径、固定任务目录、MCP 协议。 | 真实用户是否理解风险提示。 |
| 构建/签名 | Xcode/Swift 版本兼容、工程生成、测试 Runner 完整性。 | 外部分发的 Developer ID、公证和 Gatekeeper。 |
| UI 冒烟 | 启动、窗口恢复、首次引导、点击导航、页面边界、可访问控件。 | 微妙的视觉节奏、长期使用体验、辅助技术完整审计。 |
| 失败附件 | 截图、UI 层级、日志，便于最小化复现。 | 用户机器独有权限、第三方 App、硬件与网络环境。 |

### 5.3 可复制的测试闭环模板

其他开发者若希望减少“请你再点一下、再截图”的协作摩擦，应建立以下闭环：

```text
明确验收语句
    ↓
稳定 accessibility identifier
    ↓
单元测试（策略与数据） + UI 测试（真实点击路径）
    ↓
一条集中验证命令
    ↓
失败时自动产出 summary + 日志 + xcresult 附件
    ↓
只向用户索取最短失败摘要；开发者做最小修复
```

这里的关键不是“自动点击”本身，而是**把可观察的产品契约编码为测试**。若产品只写“界面高级一点”，任何自动化都无法可靠判断；若写成“首次启动必须出现边界说明；工作台必须有本机开关；远程终端入口不得出现”，测试就能在真实操作系统中给出稳定的通过或失败结果。

### 5.4 为什么不同项目或不同协作体验差异很大

不能依据单次对话判断其他工具或其他协作实例的能力高低；更常见的差异来自项目是否具备可运行的工程、是否有 UI 测试目标、是否定义了稳定 identifier、是否能够在真实目标 OS 上构建、是否有集中脚本，以及需求是否被表述成可验收条件。

TermiPad 之所以能把用户重复操作压缩到“拉取后运行一条集中脚本，并返回末尾摘要”，是因为前期专门投入了测试基础设施、失败附件和安全守卫。它并不意味着所有改动都无需人工确认：涉及授权、真实账户、外部分发、远程连接、付款或真实任务执行时，仍然必须由用户看到并明确决定。

---

## 6. 建议的后续决策顺序

在进入原生 iPhone 伴侣之前，建议按下列顺序讨论，而不是立即实现全部内容。

| 决策点 | 推荐选择 | 需要你的确认 |
|---|---|---|
| 是否做 Launch Deck | 做 **L0 设计**，再判断是否进 L1 MVP。 | 你希望它只收录图形 App，还是和现有 CLI 工具同屏但明确分区？ |
| 默认收录范围 | 先采用“用户手动添加 + 可选标准应用目录轻量发现”。 | 是否允许列出 `/Applications` 与用户 Applications 目录中的 `.app`，仍需你确认。 |
| 快捷入口 | 先使用侧边栏与可选菜单栏“显示 Launch Deck”。 | 暂不抢占 `Command-Space` 或旧 Launchpad 手势。 |
| UI 复用 | 先出内部 `NativeWorkspaceKit` 提取计划。 | 是否需要把复用包交付给某个指定开发者/团队？ |
| iPhone 伴侣 | 继续保持在下一阶段。 | 在 L0 结论后再做 M0/M1 信息架构与配对安全设计。 |

---

## 参考资料

[1]: https://support.apple.com/en-gb/guide/mac-help/mchlp1008/mac "Apple Support: Search for anything with Spotlight on Mac"
[2]: https://developer.apple.com/documentation/appkit/nsworkspace "Apple Developer: NSWorkspace"
[3]: https://developer.apple.com/design/human-interface-guidelines/toolbars "Apple Human Interface Guidelines: Toolbars"
[4]: https://developer.apple.com/design/human-interface-guidelines/layout "Apple Human Interface Guidelines: Layout"
[5]: https://developer.apple.com/documentation/xcuiautomation/xcuiapplication "Apple Developer: XCUIApplication"
[6]: https://developer.apple.com/documentation/xctest "Apple Developer: XCTest"
