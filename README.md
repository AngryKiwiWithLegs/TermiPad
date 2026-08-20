# TermiPad — 终端工具图标化启动器 (macOS 专用)

**TermiPad** 是一个专为 macOS 打造的终端命令行工具图标化启动器（仿经典 macOS Launchpad 效果）。它旨在解决开发者“记不住装过什么”和“记不住启动命令”两大核心痛点。

---

## 一、 核心功能特性

1. **一键自动发现**：自动扫描 `$PATH` 环境变量以及常见二进制目录（如 `/opt/homebrew/bin`, `~/.local/bin` 等），智能过滤系统自带命令与包管理器，一键收录所有已安装的 CLI 工具。
2. **仿 Launchpad 宫格界面**：采用现代 SwiftUI 毛玻璃（Glassmorphism）与响应式网格布局，支持按分类标签（AI/智能体、开发工具、效率工具、媒体处理、网络与系统等）筛选。
3. **一键终端唤起**：点击工具图标，自动调用 macOS 系统终端（Terminal.app / iTerm2）并执行预设的启动命令。
4. **个性化命令模板**：支持右键编辑每个工具的启动命令模板与分类。
5. **本地持久化**：基于 SwiftData 实现流畅的本地数据存储与状态管理。

---

## 二、 如何在 macOS 中运行本项目

如果您在本地 Mac 上已经拥有该项目的文件夹（或通过 Manus 桌面端绑定同步），请按以下步骤在 Xcode 中运行：

### 1. 创建 Xcode 项目
由于本项目为纯 Swift + SwiftUI 编写，您可以在 Xcode 中新建一个 **macOS App** 项目：
- **Product Name**: `TermiPad`
- **Team**: 您的开发者账号（或 None）
- **Organization Identifier**: `com.termpad`
- **Interface**: SwiftUI
- **Language**: Swift
- **Storage**: SwiftData

### 2. 导入源码
将本目录下的 `Sources/` 文件夹中的所有文件（`TermiPadApp.swift`, `TerminalTool.swift`, `ToolScanner.swift`, `LaunchpadView.swift`）拖入 Xcode 项目中，替换或合并默认文件。

### 3. 配置权限与编译
- 确保 Deployment Target 设置为 **macOS 14.0+**（因为使用了 SwiftData 与现代 SwiftUI 特性）。
- 点击 Xcode 左上角的 **Run**（▶ 按钮），即可编译并启动 **TermiPad**！

---

## 三、 代码架构

```
TermiPad/
├── Sources/
│   ├── TermiPadApp.swift      # 应用程序入口与 SwiftData 容器配置
│   ├── TerminalTool.swift     # 数据模型与分类定义
│   ├── ToolScanner.swift      # $PATH 扫描、过滤与智能分类引擎
│   └── LaunchpadView.swift    # 仿 Launchpad 界面、网格布局、搜索与终端唤起
└── README.md                  # 说明文档
```
