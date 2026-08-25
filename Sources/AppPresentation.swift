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
            "allTools": "所有工具", "inbox": "候选收件箱", "favorites": "收藏", "recent": "最近使用", "hidden": "已隐藏", "categories": "分类", "toolLibrary": "工具库", "settings": "设置",
            "discover": "发现工具", "discovering": "正在发现", "addTool": "手动添加", "searchTools": "搜索工具", "searchCandidates": "筛选候选工具", "toolsMenu": "工具", "openLibrary": "打开工具库", "showFavorites": "显示收藏", "showRecent": "显示最近使用",
            "noTools": "尚未收录工具", "noMatches": "未找到匹配工具", "noFavorites": "还没有收藏工具", "noRecent": "还没有最近使用的工具", "noHidden": "没有已隐藏工具", "emptyInbox": "候选收件箱为空",
            "scanDescription": "使用“发现工具”扫描 PATH 中的交互式命令行工具；扫描结果会先进入候选收件箱。",
            "inboxDescription": "扫描后发现的新命令会先显示在这里；确认收录后才进入工具库。",
            "hiddenDescription": "在工具卡片的右键菜单中选择“隐藏”后，它会出现在这里。", "favoritesDescription": "在工具卡片的右键菜单中选择“收藏”，即可在这里快速找到它。", "recentDescription": "成功启动过的工具会按最近时间显示在这里。",
            "clearSearch": "清除搜索", "goToLibrary": "前往工具库", "tools": "个工具", "collect": "收录", "ignore": "忽略", "restore": "恢复",
            "launch": "启动", "launchByTemplate": "按模板启动", "editTool": "编辑工具", "favoriteTool": "收藏工具", "unfavoriteTool": "取消收藏", "hideTool": "隐藏工具", "unhideTool": "取消隐藏",
            "scanComplete": "工具发现完成", "ok": "好", "operationComplete": "操作完成", "operationResult": "操作结果", "cannotLaunch": "无法启动", "automationPermissionNeeded": "需要允许自动化",
            "noNewCandidates": "没有发现新的候选工具。", "foundCandidates": "发现 %@ 个候选工具。请在“候选收件箱”中确认要收录的项目。",
            "settingsAppearance": "外观", "settingsLanguage": "语言", "settingsTerminal": "终端启动", "defaultTerminal": "默认终端", "toolDiscovery": "工具发现", "dataPrivacy": "数据与隐私", "dataManagement": "备份与恢复",
            "autoEnrich": "扫描后自动补充 GitHub / AI 信息", "showIgnored": "在候选收件箱显示已忽略项目", "updates": "更新检查", "enableUpdateChecks": "启用手动更新检查", "updateFeedURL": "更新源地址（HTTPS）", "checkForUpdates": "检查更新", "updateChecksHint": "默认关闭。TermiPad 仅在您手动检查时读取此 HTTPS JSON 更新源；它不会下载、安装或执行更新。", "updateAvailable": "发现版本 %@。请查看更新说明并自行决定是否获取。", "openReleaseNotes": "打开更新说明", "noUpdateAvailable": "当前已是最新版本。", "updateCheckFailed": "无法检查更新。请检查 HTTPS 更新源地址和网络连接。", "diagnostics": "诊断与支持", "exportDiagnostics": "导出诊断包", "clearDiagnostics": "清除本地诊断记录", "diagnosticsHint": "诊断仅记录固定事件类别、时间、终端名称和数量；不包含工具名称、路径、命令、变量值或 API Key。诊断包只在您主动导出后才会离开本机。", "diagnosticsExported": "诊断包已导出。", "diagnosticsCleared": "本地诊断记录已清除。", "diagnosticsExportFailed": "无法导出诊断包。",
            "scanPreferenceHint": "扫描到的命令会先进入候选收件箱，只有确认后才会出现在工具墙。",
            "privacyHint": "工具列表、分类、模板和变量值保存在这台 Mac 上。GitHub 与 AI 补充功能只会在您开启自动补充时访问网络。AI API Key 安全保存在 macOS 钥匙串中。",
            "aiConfiguration": "AI 服务", "aiConfigurationHint": "API Key 安全保存在这台 Mac 的钥匙串中。未配置时，TermiPad 仅使用本地说明回退。", "aiAPIKey": "API Key", "aiBaseURL": "服务地址", "aiModel": "模型", "saveToKeychain": "保存到钥匙串", "clearAPIKey": "移除 API Key", "apiKeyStored": "API Key 已安全保存在钥匙串中。", "apiKeyNotStored": "尚未配置 API Key。", "apiKeyCleared": "已从钥匙串移除 API Key。", "keychainOperationFailed": "无法更新钥匙串。",
            "exportBackup": "导出备份", "importBackup": "导入备份", "includeSavedValues": "包含已保存的变量值", "backupHint": "备份包含工具、候选收件箱、分类和命令模板。API Key 永不导出；变量值默认不包含。", "backupExported": "备份已导出。", "backupImportFailed": "无法读取备份。", "restorePreview": "恢复预览", "restoreBackup": "合并恢复", "cancelRestore": "暂不恢复", "restoreHint": "恢复会按工具或候选的 ID 与可执行路径合并记录；不会删除当前已有项目。", "restoreSummary": "新增 %@ 个工具，更新 %@ 个工具；新增 %@ 个候选，更新 %@ 个候选。",
            "basicInfo": "基本信息", "toolName": "工具名称", "executablePath": "可执行文件路径", "launchCommand": "启动命令", "commandTemplate": "命令模板", "description": "说明（可选）",
            "save": "添加", "cancel": "取消", "done": "完成", "delete": "删除工具", "organize": "整理", "hideThisTool": "隐藏此工具", "toolDescription": "工具描述", "toolTrust": "来源与可信度", "installationSource": "安装来源", "metadataSource": "信息来源", "matchConfidence": "匹配可信度", "repository": "关联仓库",
            "variables": "需要填写的参数", "commandPreview": "命令预览", "checkParameters": "请检查参数",
            "variableHint": "需要用户填写的内容可写为 `{{variable_name}}`，首次启动时会自动询问。",
            "variableSecurityHint": "参数会以 shell 安全转义方式写入本次命令，并保存在本机以便下次使用。",
            "editVariableHint": "可使用 `{{variable_name}}` 创建首次启动填写项。",
            "warpCopied": "已打开 Warp，并将命令复制到剪贴板。", "copied": "完整命令已复制到剪贴板。", "terminalLaunched": "已在 Terminal 中执行命令。", "itermLaunched": "已在 iTerm 中输入命令。"
        ]
        let english: [String: String] = [
            "allTools": "All Tools", "inbox": "Review Inbox", "favorites": "Favorites", "recent": "Recent", "hidden": "Hidden", "categories": "Categories", "toolLibrary": "Library", "settings": "Settings",
            "discover": "Discover Tools", "discovering": "Discovering", "addTool": "Add Manually", "searchTools": "Search tools", "searchCandidates": "Filter candidates", "toolsMenu": "Tools", "openLibrary": "Open Library", "showFavorites": "Show Favorites", "showRecent": "Show Recent",
            "noTools": "No tools collected", "noMatches": "No matching tools", "noFavorites": "No favorite tools yet", "noRecent": "No recently used tools yet", "noHidden": "No hidden tools", "emptyInbox": "Your review inbox is empty",
            "scanDescription": "Use Discover Tools to scan interactive CLI commands in PATH. New results are reviewed before entering your library.",
            "inboxDescription": "New commands found by scanning appear here first. Accept them to add them to your library.",
            "hiddenDescription": "Tools you hide from a card's context menu appear here.", "favoritesDescription": "Favorite a tool from its context menu to keep it easy to find here.", "recentDescription": "Successfully launched tools appear here in most-recent-first order.",
            "clearSearch": "Clear Search", "goToLibrary": "Open Library", "tools": "tools", "collect": "Accept", "ignore": "Ignore", "restore": "Restore",
            "launch": "Launch", "launchByTemplate": "Launch with Template", "editTool": "Edit Tool", "favoriteTool": "Favorite Tool", "unfavoriteTool": "Remove from Favorites", "hideTool": "Hide Tool", "unhideTool": "Unhide Tool",
            "scanComplete": "Tool discovery complete", "ok": "OK", "operationComplete": "Done", "operationResult": "Result", "cannotLaunch": "Unable to launch", "automationPermissionNeeded": "Automation Permission Needed",
            "noNewCandidates": "No new tool candidates were found.", "foundCandidates": "Found %@ new tool candidates. Review them in the inbox.",
            "settingsAppearance": "Appearance", "settingsLanguage": "Language", "settingsTerminal": "Terminal Launching", "defaultTerminal": "Default Terminal", "toolDiscovery": "Tool Discovery", "dataPrivacy": "Data & Privacy", "dataManagement": "Backup & Restore",
            "autoEnrich": "Enrich discovered tools with GitHub / AI", "showIgnored": "Show ignored items in review inbox", "updates": "Update Checks", "enableUpdateChecks": "Enable manual update checks", "updateFeedURL": "Update feed URL (HTTPS)", "checkForUpdates": "Check for Updates", "updateChecksHint": "Off by default. TermiPad reads this HTTPS JSON feed only when you check manually; it never downloads, installs, or executes an update.", "updateAvailable": "Version %@ is available. Review the release notes and decide whether to obtain it.", "openReleaseNotes": "Open Release Notes", "noUpdateAvailable": "You are already on the latest version.", "updateCheckFailed": "Unable to check for updates. Verify the HTTPS feed URL and your network connection.", "diagnostics": "Diagnostics & Support", "exportDiagnostics": "Export Diagnostic Package", "clearDiagnostics": "Clear Local Diagnostics", "diagnosticsHint": "Diagnostics record only fixed event categories, timestamps, terminal names, and counts. They never include tool names, paths, commands, variable values, or API keys. A package leaves this Mac only when you export it.", "diagnosticsExported": "Diagnostic package exported.", "diagnosticsCleared": "Local diagnostic records cleared.", "diagnosticsExportFailed": "The diagnostic package could not be exported.",
            "scanPreferenceHint": "New commands always enter the review inbox before appearing in your library.",
            "privacyHint": "Your tools, categories, templates, and variable values are stored on this Mac. GitHub and AI enrichment only access the network when enabled. AI API keys are securely stored in macOS Keychain.",
            "aiConfiguration": "AI Service", "aiConfigurationHint": "Your API key is securely stored in this Mac's Keychain. Without one, TermiPad uses local fallback descriptions only.", "aiAPIKey": "API Key", "aiBaseURL": "Service URL", "aiModel": "Model", "saveToKeychain": "Save to Keychain", "clearAPIKey": "Remove API Key", "apiKeyStored": "Your API key is securely stored in Keychain.", "apiKeyNotStored": "No API key is configured.", "apiKeyCleared": "The API key was removed from Keychain.", "keychainOperationFailed": "Keychain could not be updated.",
            "exportBackup": "Export Backup", "importBackup": "Import Backup", "includeSavedValues": "Include saved variable values", "backupHint": "Backups include tools, review candidates, categories, and command templates. API keys are never exported; saved values are excluded by default.", "backupExported": "Backup exported.", "backupImportFailed": "The backup could not be read.", "restorePreview": "Restore Preview", "restoreBackup": "Merge & Restore", "cancelRestore": "Not Now", "restoreHint": "Restore merges records by tool or candidate ID and executable path; it never deletes your current items.", "restoreSummary": "%@ tools added, %@ tools updated; %@ candidates added, %@ candidates updated.",
            "basicInfo": "Basics", "toolName": "Tool name", "executablePath": "Executable path", "launchCommand": "Launch command", "commandTemplate": "Command template", "description": "Description (optional)",
            "save": "Add", "cancel": "Cancel", "done": "Done", "delete": "Delete Tool", "organize": "Organize", "hideThisTool": "Hide this tool", "toolDescription": "Tool description", "toolTrust": "Source & Trust", "installationSource": "Installation source", "metadataSource": "Metadata source", "matchConfidence": "Match confidence", "repository": "Linked repository",
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
