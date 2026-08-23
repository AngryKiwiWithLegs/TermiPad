import SwiftUI

/// 应用内语言：不依赖系统语言切换，修改后立即刷新当前界面。
enum AppLanguage: String, CaseIterable, Identifiable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .simplifiedChinese: return "简体中文"
        case .english: return "English"
        }
    }

    var compactName: String {
        switch self {
        case .simplifiedChinese: return "中"
        case .english: return "EN"
        }
    }
}

/// 遵循 macOS 的三档外观选择。
enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    func displayName(_ language: AppLanguage) -> String {
        switch (self, language) {
        case (.system, .simplifiedChinese): return "跟随系统"
        case (.light, .simplifiedChinese): return "浅色"
        case (.dark, .simplifiedChinese): return "深色"
        case (.system, .english): return "System"
        case (.light, .english): return "Light"
        case (.dark, .english): return "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon.stars"
        }
    }
}

/// 将常用界面词汇集中管理。领域数据（工具名、命令、README 说明）保持原样，不被翻译。
enum AppCopy {
    static func text(_ key: String, language: AppLanguage) -> String {
        let chinese: [String: String] = [
            "allTools": "所有工具", "inbox": "候选收件箱", "hidden": "已隐藏", "categories": "分类", "toolLibrary": "工具库",
            "discover": "发现工具", "discovering": "正在发现", "addTool": "手动添加", "searchTools": "搜索工具", "searchCandidates": "筛选候选工具",
            "noTools": "尚未收录工具", "noMatches": "未找到匹配工具", "noHidden": "没有已隐藏工具", "emptyInbox": "候选收件箱为空",
            "scanDescription": "使用“发现工具”扫描 PATH 中的交互式命令行工具；扫描结果会先进入候选收件箱。",
            "inboxDescription": "扫描后发现的新命令会先显示在这里；确认收录后才进入工具库。",
            "hiddenDescription": "在工具卡片的右键菜单中选择“隐藏”后，它会出现在这里。",
            "clearSearch": "清除搜索", "goToLibrary": "前往工具库", "tools": "个工具", "collect": "收录", "ignore": "忽略", "restore": "恢复",
            "launch": "启动", "launchByTemplate": "按模板启动", "editTool": "编辑工具", "hideTool": "隐藏工具", "unhideTool": "取消隐藏",
            "scanComplete": "工具发现完成", "ok": "好", "operationComplete": "操作完成", "operationResult": "操作结果", "cannotLaunch": "无法启动", "automationPermissionNeeded": "需要允许自动化",
            "noNewCandidates": "没有发现新的候选工具。", "foundCandidates": "发现 %@ 个候选工具。请在“候选收件箱”中确认要收录的项目。",
            "settingsAppearance": "外观", "settingsLanguage": "语言", "settingsTerminal": "终端启动", "defaultTerminal": "默认终端", "toolDiscovery": "工具发现", "dataPrivacy": "数据与隐私",
            "autoEnrich": "扫描后自动补充 GitHub / AI 信息", "showIgnored": "在候选收件箱显示已忽略项目",
            "scanPreferenceHint": "扫描到的命令会先进入候选收件箱，只有确认后才会出现在工具墙。",
            "privacyHint": "工具列表、分类、模板和变量值保存在这台 Mac 上。GitHub 与 AI 补充功能只会在您开启自动补充时访问网络。",
            "basicInfo": "基本信息", "toolName": "工具名称", "executablePath": "可执行文件路径", "launchCommand": "启动命令", "commandTemplate": "命令模板", "description": "说明（可选）",
            "save": "添加", "cancel": "取消", "done": "完成", "delete": "删除工具", "organize": "整理", "hideThisTool": "隐藏此工具", "toolDescription": "工具描述",
            "variables": "需要填写的参数", "commandPreview": "命令预览", "checkParameters": "请检查参数",
            "variableHint": "需要用户填写的内容可写为 `{{variable_name}}`，首次启动时会自动询问。",
            "variableSecurityHint": "参数会以 shell 安全转义方式写入本次命令，并保存在本机以便下次使用。",
            "editVariableHint": "可使用 `{{variable_name}}` 创建首次启动填写项。",
            "warpCopied": "已打开 Warp，并将命令复制到剪贴板。", "copied": "完整命令已复制到剪贴板。", "terminalLaunched": "已在 Terminal 中执行命令。", "itermLaunched": "已在 iTerm 中输入命令。"
        ]
        let english: [String: String] = [
            "allTools": "All Tools", "inbox": "Review Inbox", "hidden": "Hidden", "categories": "Categories", "toolLibrary": "Library",
            "discover": "Discover Tools", "discovering": "Discovering", "addTool": "Add Manually", "searchTools": "Search tools", "searchCandidates": "Filter candidates",
            "noTools": "No tools collected", "noMatches": "No matching tools", "noHidden": "No hidden tools", "emptyInbox": "Your review inbox is empty",
            "scanDescription": "Use Discover Tools to scan interactive CLI commands in PATH. New results are reviewed before entering your library.",
            "inboxDescription": "New commands found by scanning appear here first. Accept them to add them to your library.",
            "hiddenDescription": "Tools you hide from a card's context menu appear here.",
            "clearSearch": "Clear Search", "goToLibrary": "Open Library", "tools": "tools", "collect": "Accept", "ignore": "Ignore", "restore": "Restore",
            "launch": "Launch", "launchByTemplate": "Launch with Template", "editTool": "Edit Tool", "hideTool": "Hide Tool", "unhideTool": "Unhide Tool",
            "scanComplete": "Tool discovery complete", "ok": "OK", "operationComplete": "Done", "operationResult": "Result", "cannotLaunch": "Unable to launch", "automationPermissionNeeded": "Automation Permission Needed",
            "noNewCandidates": "No new tool candidates were found.", "foundCandidates": "Found %@ new tool candidates. Review them in the inbox.",
            "settingsAppearance": "Appearance", "settingsLanguage": "Language", "settingsTerminal": "Terminal Launching", "defaultTerminal": "Default Terminal", "toolDiscovery": "Tool Discovery", "dataPrivacy": "Data & Privacy",
            "autoEnrich": "Enrich discovered tools with GitHub / AI", "showIgnored": "Show ignored items in review inbox",
            "scanPreferenceHint": "New commands always enter the review inbox before appearing in your library.",
            "privacyHint": "Your tools, categories, templates, and variable values are stored on this Mac. GitHub and AI enrichment only access the network when enabled.",
            "basicInfo": "Basics", "toolName": "Tool name", "executablePath": "Executable path", "launchCommand": "Launch command", "commandTemplate": "Command template", "description": "Description (optional)",
            "save": "Add", "cancel": "Cancel", "done": "Done", "delete": "Delete Tool", "organize": "Organize", "hideThisTool": "Hide this tool", "toolDescription": "Tool description",
            "variables": "Required values", "commandPreview": "Command preview", "checkParameters": "Check your values",
            "variableHint": "Use `{{variable_name}}` for a value that TermiPad should ask for before the first launch.",
            "variableSecurityHint": "Values are shell-escaped for this command and stored on this Mac for next time.",
            "editVariableHint": "Use `{{variable_name}}` to create a first-launch input.",
            "warpCopied": "Warp was opened and the command was copied to the clipboard.", "copied": "The completed command was copied to the clipboard.", "terminalLaunched": "The command was sent to Terminal.", "itermLaunched": "The command was entered in iTerm."
        ]
        let table = language == .simplifiedChinese ? chinese : english
        return table[key] ?? key
    }

    static func format(_ key: String, _ value: Int, language: AppLanguage) -> String {
        let template = text(key, language: language)
        return template.replacingOccurrences(of: "%@", with: String(value))
    }
}
