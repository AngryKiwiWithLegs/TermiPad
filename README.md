# TermiPad

**TermiPad** 是一款原生 macOS 终端工具启动器：它把主动安装、需要直接交互使用的 CLI 工具整理为可搜索、可分类、可一键启动的工具库。

> 当前仓库为私有开发版。项目仍在公开发布前的完善阶段；请勿将 API Key 写入源码或提交到仓库。

## 当前可用能力

| 能力 | 当前行为 |
|---|---|
| 候选发现 | 扫描 `$PATH` 和常见第三方安装目录；新命令先进入**候选收件箱**，不会自动污染工具墙。 |
| 人工整理 | 可收录、忽略、恢复候选；支持手动添加、编辑、隐藏、恢复和删除已收录工具。 |
| 命令模板 | 支持 `{{variable_name}}` 占位符；首次启动时会要求填写变量、展示命令预览并保存本机默认值。 |
| 终端启动 | 可在设置中选择 Terminal.app、iTerm、Warp 或“仅复制命令”。Warp 采用打开应用并复制命令的保守方式。 |
| 信息补充 | 可选 GitHub README 搜索与 AI 提炼；失败时保留本地命令和手动编辑能力。 |
| 图标 | 常用工具有差异化语义图标；已识别 GitHub 仓库时优先显示组织头像，未知工具使用稳定的渐变回退图标。 |
| 本地存储 | 工具、候选、分类、隐藏状态、命令模板和变量值保存在本机 SwiftData 容器中。 |

## 本地运行

### 前置条件

- macOS 14 或更高版本。
- Xcode 15 或更高版本。
- 使用 **macOS / My Mac** 作为运行目标；请勿选择 iPhone 或 iPad 模拟器。

### 推荐方式：使用项目定义生成 Xcode 工程

项目包含 `project.yml`，用于生成带单元测试和 macOS UI 测试的原生工程。

```bash
brew install xcodegen
cd TermiPad
xcodegen generate
open TermiPad.xcodeproj
```

在 Xcode 顶部选择 **TermiPad > My Mac**，然后按 `Command + R`。首轮扫描后，请进入左侧 **候选收件箱**确认要收录的工具。

### Swift Package 方式

也可直接打开包定义：

```bash
cd TermiPad
open Package.swift
```

同样必须在 Xcode 中选择 **My Mac**。包方式适合源码浏览与基础构建；完整 UI 自动化测试以生成的 `.xcodeproj` 为准。

## 使用流程

```text
发现工具 → 候选收件箱确认收录 → （可选）GitHub / AI 补充 → 点击图标
→ 若模板含变量则填写表单 → 在偏好终端执行或复制命令
```

## 终端偏好

从 macOS 菜单栏打开 **TermiPad → Settings…**：

- **Terminal.app**：通过 AppleScript 在新标签或窗口中执行命令。
- **iTerm**：将命令写入当前会话；未打开窗口时会创建默认窗口。
- **Warp**：打开 Warp 并复制完整命令，用户可检查后粘贴执行。
- **仅复制命令**：不打开任何终端，只将最终命令复制到剪贴板。

### macOS 自动化权限

首次使用 **Terminal.app** 或 **iTerm** 一键启动时，macOS 可能会请求允许 TermiPad 控制所选终端。这是系统隐私保护机制，应用无法自行绕过。请在弹窗中选择允许；若此前已拒绝，请前往 **系统设置 → 隐私与安全性 → 自动化**，在 TermiPad 下启用对应的 Terminal.app 或 iTerm。

如果权限尚未授予，TermiPad 不会丢弃已填写或渲染好的命令：它会自动复制命令到剪贴板，并显示上述明确的授权路径。授权后再次点击工具即可继续一键启动。

## 命令模板

将必须由用户填写的内容写为 `{{variable_name}}`，例如：

```text
claude --model {{model}} {{prompt}}
```

TermiPad 会在启动前显示表单。变量值会使用 POSIX 单引号方式进行 shell 转义，以避免空格或引号意外改变命令结构；但用户仍应在执行前确认最终命令及其影响。

## 自动化验证

GitHub Actions 工作流包含：

1. Swift 单元测试：扫描过滤、分类、命令变量与图标回退。
2. `xcodebuild` macOS 构建。
3. macOS UI Smoke Test：启动应用、检查主要控件、归档 `.xcresult` 和截图。

当前 GitHub Actions 的云端运行受账户级账单/额度限制拦截；恢复后，工作流会自动继续执行上述验证。

## 项目结构

```text
TermiPad/
├── Sources/
│   ├── TerminalTool.swift       # SwiftData 工具与候选模型
│   ├── ToolScanner.swift        # PATH 与常见生态路径扫描
│   ├── CommandTemplate.swift    # {{variable}} 解析、渲染与转义
│   ├── TerminalLauncher.swift   # Terminal / iTerm / Warp / 剪贴板启动适配
│   ├── LaunchpadView.swift      # 原生侧边栏、候选收件箱、工具墙与表单
│   ├── PreferencesView.swift    # 应用偏好设置
│   └── ToolIconView.swift       # 差异化图标系统
├── Tests/                       # 核心逻辑单元测试
├── UITests/                     # macOS UI 自动化测试
├── project.yml                  # XcodeGen 原生工程定义
└── .github/workflows/           # 云端构建与截图归档
```

## 公开版前的开发路线

公开前仍需完成更可靠的 GitHub 匹配、Keychain 凭据存储、品牌图标缓存/替换、备份导出与更深的 UI 测试。详细优先级见私有开发文档 `termipad_development_backlog.md`。

## Language and appearance

TermiPad supports an immediate in-app language switch between **简体中文** and **English**. Use the compact **中 / EN** segmented control in the main toolbar, or open **TermiPad → Settings… → Language**. Tool names, commands, paths, and README-derived descriptions are deliberately left unchanged.

The compact three-segment appearance control in the main toolbar, and **Settings → Appearance**, provides one-click access to **System**, **Light**, and **Dark**. The preference is stored locally and applied to both the main window and the Settings window.

### 柔和 macOS 外观

浅色模式采用轻微蓝灰的窗口背景和近白内容表面，而非大面积纯白；深色模式采用石墨灰和分层卡片表面，而非纯黑。侧边栏、内容区和工具卡片使用统一的语义层级。切换“跟随系统 / 浅色 / 深色”时会以约 0.30 秒的缓入缓出过渡完成；若 macOS 启用了“减少动态效果”，应用会尊重该辅助功能并取消动画。

### 原生控件与初始窗口位置

工具卡片使用更紧凑的 `7pt` 连续圆角、轻描边和短阴影，以接近 macOS 内容表面的几何比例；候选操作与工具栏继续使用系统的 bordered / borderedProminent 控件样式。

首次启动时，TermiPad 会把主窗口放置到**主显示器可用区域的左半边**（会避开菜单栏和 Dock）。之后应用会尊重您手动调整的位置和尺寸，不会再次抢占窗口。若要重新体验首次定位，可执行：

```bash
defaults delete com.termipad.app TermiPad.hasPlacedInitialMainWindow
```

工程定义已更新 Xcode 升级检查标记。拉取更新后请务必重新运行 `xcodegen generate`，不要继续使用旧的 `.xcodeproj`。

### 工具格子提示与工具栏控件

主窗口的语言和外观分段控件使用常规 macOS 控件尺寸，并在两组控件之间保留额外留白。将鼠标停留在任一工具格子上，分类标签会切换为两段简洁说明：**用途**说明它能帮助完成什么，**如何开始**说明应在何处启动、需要做什么准备或如何继续操作。常见 CLI（如 Claude、GitHub CLI、Lazygit、FFmpeg、fzf 与 Terraform）使用更具体的本地说明；已有 README / AI 可靠摘要时会优先作为用途。旧版“正在尝试 AI 增强”等后台状态不会再作为悬停说明或辅助功能文本展示。

`project.yml` 已显式启用 Xcode 推荐的 Dead Code Stripping、User Script Sandboxing、String Catalog Symbol Generation 与 Asset Symbol Extensions。重新生成工程后，项目级“Update to recommended settings”清单应不再要求这些设置。
