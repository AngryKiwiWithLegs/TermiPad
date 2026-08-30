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
            "discover": "发现工具", "discovering": "正在发现", "addTool": "手动添加", "searchTools": "搜索工具", "searchCandidates": "筛选候选工具", "toolsMenu": "工具", "openLibrary": "打开工具库", "showFavorites": "显示收藏", "showRecent": "显示最近使用", "discoverySection": "发现预览", "discoveryPreview": "项目发现预览", "enableDiscoveryPreview": "启用发现预览", "refreshDiscovery": "手动刷新", "discoveryDisabledDescription": "默认关闭。启用后，TermiPad 仍只会在您点击“手动刷新”时读取 GitHub 的公开仓库元数据。", "discoveryEmptyDescription": "尚无本地发现缓存。手动刷新会读取固定的公开 CLI 仓库查询；不会上传工具、命令、路径或 API Key。", "discoveryPreviewHint": "按公开仓库字段进行本地可解释排序，不是 GitHub 官方热门榜，也不是安全评级。", "discoveryNoInstallHint": "此预览只供浏览；不会安装软件、生成命令或将项目加入工具库。", "discoveryResults": "公开项目候选", "discoveryIncomplete": "GitHub 标记本轮搜索结果可能不完整；请不要将当前排序视为完整榜单。", "discoveryRefreshed": "发现缓存已手动更新。", "discoveryCacheCurrent": "GitHub 返回未修改结果；正在使用当前本地缓存。", "discoveryFailed": "无法刷新项目发现。请检查网络后稍后手动重试。", "discoveryNoSummary": "仓库未提供公开简介。", "discoveryNoLicense": "未提供许可信息", "openRepository": "打开仓库", "clearDiscoveryCache": "清除本地发现缓存", "discoverySettingsHint": "默认关闭。启用只允许您在“项目发现预览”中手动刷新公开 GitHub 元数据；不会自动联网，缓存也不会进入工具库、备份或诊断包。", "installAndEnvironment": "安装审查与环境报告", "environmentReport": "只读环境报告", "environmentReportHint": "仅在您点击检查时，TermiPad 才会对固定的本机包管理器路径运行 `--version`。不会使用 shell、联网、安装、升级、卸载或保存路径/结果。", "checkEnvironment": "检查本机环境", "environmentReportResults": "当前环境", "installReview": "受控安装审查", "installReviewHint": "只展示随应用发布、已审核的 Homebrew core formula 计划。网络项目、README 和 AI 均不能生成或修改安装命令。", "reviewedInstallPlans": "已审核安装计划", "reviewInstallPlan": "查看安装计划", "installResultNotCollected": "即使您选择把计划交给终端，TermiPad 也不会在应用内执行安装、等待结果或自动将任何内容加入工具库。安装后请自行扫描并在候选收件箱确认。", "installChannel": "安装渠道", "expectedExecutables": "预期 CLI", "catalogRevision": "目录审核修订", "catalogAuditedAt": "审核日期", "installCommandPreview": "完整命令预览", "installReviewAcknowledgement": "我已审查完整命令、渠道、仓库与影响说明", "installExplicitConsent": "只有在此窗口中明确选择“复制”或“发送到终端”后，固定命令才会离开 TermiPad。请先检查命令、渠道和仓库。", "installRequiresHomebrewCheck": "如要发送到终端，请先手动运行本页的环境检查，并确认已在受控路径中检测到 Homebrew。", "copyInstallPlan": "复制安装计划", "sendInstallPlan": "发送到 %@", "installHandoffFailed": "无法将安装计划交给所选终端。请改用“仅复制命令”或检查终端权限。",
            // M0 移动端入口：详见 docs/m0-m1-mobile-entry-design.md §2.4
            "mobileEntrySection": "手机入口", "mobileEntryHint": "每个字段默认关闭。仅在确认要在手机端使用此工具时才打开。",
            "mobileEntryDisplayName": "手机显示名", "mobileEntryDisplayNameHint": "可选；用手机显示的短标签，覆盖本地工具名。",
            "mobileEntryDescription": "手机说明", "mobileEntryDescriptionHint": "一行用途说明。绝不含命令、路径、变量值。",
            "mobileEntryShowInApp": "在手机入口显示", "mobileEntryShowInAppHint": "允许此工具出现在手机端的最小化目录中。",
            "mobileEntryAllowLaunch": "允许手机发起启动请求", "mobileEntryAllowLaunchHint": "手机可向 Mac 请求启动此工具。Mac 仍按你选定的策略做本地确认。",
            "mobileEntryConfirmPolicy": "本地确认策略", "mobileEntryConfirmPolicyEveryTime": "每次请求都确认",
            "mobileEntryConfirmPolicyPerSession": "5 分钟会话内确认一次",
            "mobileEntryConfirmPolicyLowRiskSessionOnly": "按会话确认，仅限低风险任务",
            "mobileEntryRevoke": "撤销手机权限", "mobileEntryRevokeConfirm": "确认撤销此工具的手机权限？手机端将不再能看到或启动它。", "mobileEntryRevokedNotice": "已撤销手机权限。",
            "noTools": "尚未收录工具", "noMatches": "未找到匹配工具", "noFavorites": "还没有收藏工具", "noRecent": "还没有最近使用的工具", "noHidden": "没有已隐藏工具", "emptyInbox": "候选收件箱为空",
            "acceptAll": "一键收录全部（%@ 个）",
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
            "exportBackup": "导出备份", "importBackup": "导入备份", "includeSavedValues": "包含已保存的变量值", "backupHint": "备份包含工具、候选收件箱、分类和命令模板。API Key 永不导出；变量值默认不包含。", "backupExported": "备份已导出。", "backupImportFailed": "无法读取备份。", "dataRecoveryTitle": "需要恢复本地工具库", "dataRecoveryDetail": "TermiPad 无法打开原有的本地数据。为避免自动删除任何记录，应用已打开一个独立的恢复工具库。", "dataRecoveryStore": "恢复模式", "dataRecoveryFallback": "您仍可手动新增工具，或主动导入此前导出的 JSON 备份。", "dataRecoveryHint": "原有数据不会被自动修改或删除。请先保留现有文件，再决定是否重置或迁移。", "restorePreview": "恢复预览", "restoreBackup": "合并恢复", "cancelRestore": "暂不恢复", "restoreHint": "恢复会按工具或候选的 ID 与可执行路径合并记录；不会删除当前已有项目。", "restoreSummary": "新增 %@ 个工具，更新 %@ 个工具；新增 %@ 个候选，更新 %@ 个候选。",
            "basicInfo": "基本信息", "toolName": "工具名称", "executablePath": "可执行文件路径", "launchCommand": "启动命令", "commandTemplate": "命令模板", "description": "说明（可选）",
            "save": "添加", "cancel": "取消", "done": "完成", "delete": "删除工具", "organize": "整理", "hideThisTool": "隐藏此工具", "toolHealth": "工具状态", "executablePathHint": "TermiPad 只检查绝对路径的存在性和可执行权限；不会运行检查命令。", "workingDirectory": "工作目录", "chooseWorkingDirectory": "选择本机目录", "clearWorkingDirectory": "清除工作目录", "workingDirectoryHint": "工作目录仅在您点击启动时以安全的 cd 前缀使用；它不会被写入 JSON 备份或诊断包。", "workingDirectoryReady": "已更新工作目录。", "workingDirectoryUpdateFailed": "无法使用所选目录。", "customIcon": "自定义图标", "replaceCustomIcon": "从本机选择图标", "removeCustomIcon": "移除自定义图标", "customIconHint": "所选图像会复制到 TermiPad 的受控本地目录并规范化为 PNG；它不会从网络加载，也不会通过 JSON 备份传递路径。", "customIconReady": "已更新本地图标。", "customIconImportFailed": "无法保存所选图像。", "toolDescription": "工具描述", "toolTrust": "来源与可信度", "installationSource": "安装来源", "metadataSource": "信息来源", "matchConfidence": "匹配可信度", "repository": "关联仓库",
            "variables": "需要填写的参数", "commandPreview": "命令预览", "checkParameters": "请检查参数",
            "variableHint": "需要用户填写的内容可写为 `{{variable_name}}`，首次启动时会自动询问。",
            "variableSecurityHint": "参数会以 shell 安全转义方式写入本次命令，并保存在本机以便下次使用。",
            "editVariableHint": "可使用 `{{variable_name}}` 创建首次启动填写项。",
            "warpCopied": "已打开 Warp，并将命令复制到剪贴板。", "copied": "完整命令已复制到剪贴板。", "terminalLaunched": "已在 Terminal 中执行命令。", "itermLaunched": "已在 iTerm 中输入命令。"
        ]
        let english: [String: String] = [
            "allTools": "All Tools", "inbox": "Review Inbox", "favorites": "Favorites", "recent": "Recent", "hidden": "Hidden", "categories": "Categories", "toolLibrary": "Library", "settings": "Settings",
            // M0 移动端入口：详见 docs/m0-m1-mobile-entry-design.md §2.4
            "mobileEntrySection": "Mobile Entry", "mobileEntryHint": "Each field is off by default. Turn them on only when you intend to use a mobile client for this tool. Removing a field is safe; revoking permission takes effect immediately.",
            "mobileEntryDisplayName": "Mobile Display Name", "mobileEntryDisplayNameHint": "Optional short label shown on the phone instead of the local tool name.",
            "mobileEntryDescription": "Mobile Description", "mobileEntryDescriptionHint": "One-line purpose. Never include commands, paths, or variable values.",
            "mobileEntryShowInApp": "Show in Mobile Entry", "mobileEntryShowInAppHint": "Allow this tool to appear in the minimal phone-side list.",
            "mobileEntryAllowLaunch": "Allow Mobile Launch Requests", "mobileEntryAllowLaunchHint": "Phone may ask the Mac to launch this tool. The Mac still requires a local confirmation by your chosen policy.",
            "mobileEntryConfirmPolicy": "Local Confirmation Policy", "mobileEntryConfirmPolicyEveryTime": "Confirm every request",
            "mobileEntryConfirmPolicyPerSession": "Confirm once per 5-minute session",
            "mobileEntryConfirmPolicyLowRiskSessionOnly": "Confirm per session, only for low-risk tasks",
            "mobileEntryRevoke": "Revoke Mobile Permission", "mobileEntryRevokeConfirm": "Revoke mobile permission for this tool? Phone clients will no longer be able to see or launch it.", "mobileEntryRevokedNotice": "Mobile permission revoked.",
            "discover": "Discover Tools", "discovering": "Discovering", "addTool": "Add Manually", "searchTools": "Search tools", "searchCandidates": "Filter candidates", "toolsMenu": "Tools", "openLibrary": "Open Library", "showFavorites": "Show Favorites", "showRecent": "Show Recent", "discoverySection": "Discovery Preview", "discoveryPreview": "Project Discovery Preview", "enableDiscoveryPreview": "Enable Discovery Preview", "refreshDiscovery": "Refresh Manually", "discoveryDisabledDescription": "Off by default. After enabling it, TermiPad still reads public GitHub repository metadata only when you select Refresh Manually.", "discoveryEmptyDescription": "There is no local discovery cache yet. A manual refresh uses a fixed public CLI repository query; it never uploads your tools, commands, paths, or API key.", "discoveryPreviewHint": "Sorted locally from public repository fields for explanation. This is neither an official GitHub trending list nor a security rating.", "discoveryNoInstallHint": "This preview is browse-only. It does not install software, create commands, or add projects to your library.", "discoveryResults": "Public Project Candidates", "discoveryIncomplete": "GitHub marked this search result as possibly incomplete. Do not treat this order as a complete ranking.", "discoveryRefreshed": "The discovery cache was updated manually.", "discoveryCacheCurrent": "GitHub returned an unchanged result; the current local cache is in use.", "discoveryFailed": "Project discovery could not be refreshed. Check your connection and retry manually later.", "discoveryNoSummary": "This repository has no public summary.", "discoveryNoLicense": "No license metadata", "openRepository": "Open Repository", "clearDiscoveryCache": "Clear Local Discovery Cache", "discoverySettingsHint": "Off by default. Enabling it only allows you to manually refresh public GitHub metadata from Project Discovery Preview; it never connects automatically, and the cache never enters your library, backup, or diagnostic package.", "installAndEnvironment": "Install Review & Environment", "environmentReport": "Read-only Environment Report", "environmentReportHint": "Only when you select Check does TermiPad run `--version` at fixed local package-manager paths. It does not use a shell, connect to the network, install, upgrade, uninstall, or save paths/results.", "checkEnvironment": "Check Local Environment", "environmentReportResults": "Current Environment", "installReview": "Controlled Install Review", "installReviewHint": "Only reviewed Homebrew core formula plans shipped with the app are shown. Network projects, READMEs, and AI cannot create or alter an install command.", "reviewedInstallPlans": "Reviewed Install Plans", "reviewInstallPlan": "Review Install Plan", "installResultNotCollected": "Even if you hand a plan to a terminal, TermiPad does not install in-app, wait for a result, or add anything to your library automatically. Scan afterward and review any candidate yourself.", "installChannel": "Install Channel", "expectedExecutables": "Expected CLI", "catalogRevision": "Catalog Review Revision", "catalogAuditedAt": "Audited On", "installCommandPreview": "Full Command Preview", "installReviewAcknowledgement": "I reviewed the full command, channel, repository, and impact notice", "installExplicitConsent": "A fixed command leaves TermiPad only when you explicitly choose Copy or Send to Terminal in this window. Review the command, channel, and repository first.", "installRequiresHomebrewCheck": "To send this plan to a terminal, first run this page’s environment check and confirm that Homebrew is detected at a controlled path.", "copyInstallPlan": "Copy Install Plan", "sendInstallPlan": "Send to %@", "installHandoffFailed": "The install plan could not be handed to the selected terminal. Use Copy Command Only or check terminal permission.",
            "noTools": "No tools collected", "noMatches": "No matching tools", "noFavorites": "No favorite tools yet", "noRecent": "No recently used tools yet", "noHidden": "No hidden tools", "emptyInbox": "Your review inbox is empty",
            "acceptAll": "Accept All (%@)",
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
            "exportBackup": "Export Backup", "importBackup": "Import Backup", "includeSavedValues": "Include saved variable values", "backupHint": "Backups include tools, review candidates, categories, and command templates. API keys are never exported; saved values are excluded by default.", "backupExported": "Backup exported.", "backupImportFailed": "The backup could not be read.", "dataRecoveryTitle": "Your local tool library needs recovery", "dataRecoveryDetail": "TermiPad could not open the original local data. To avoid deleting anything automatically, it opened an isolated recovery library.", "dataRecoveryStore": "Recovery Mode", "dataRecoveryFallback": "You can still add tools manually or choose to import a JSON backup you previously exported.", "dataRecoveryHint": "Your original data is not modified or deleted automatically. Keep the existing files before deciding whether to reset or migrate them.", "restorePreview": "Restore Preview", "restoreBackup": "Merge & Restore", "cancelRestore": "Not Now", "restoreHint": "Restore merges records by tool or candidate ID and executable path; it never deletes your current items.", "restoreSummary": "%@ tools added, %@ tools updated; %@ candidates added, %@ candidates updated.",
            "basicInfo": "Basics", "toolName": "Tool name", "executablePath": "Executable path", "launchCommand": "Launch command", "commandTemplate": "Command template", "description": "Description (optional)",
            "save": "Add", "cancel": "Cancel", "done": "Done", "delete": "Delete Tool", "organize": "Organize", "hideThisTool": "Hide this tool", "toolHealth": "Tool Status", "executablePathHint": "TermiPad checks only whether an absolute path exists and is executable; it never runs a check command.", "workingDirectory": "Working Directory", "chooseWorkingDirectory": "Choose Local Folder", "clearWorkingDirectory": "Clear Working Directory", "workingDirectoryHint": "A working directory is used only as a safely escaped cd prefix when you launch. It is never written to JSON backups or diagnostic bundles.", "workingDirectoryReady": "Working directory updated.", "workingDirectoryUpdateFailed": "The selected folder could not be used.", "customIcon": "Custom Icon", "replaceCustomIcon": "Choose Local Icon", "removeCustomIcon": "Remove Custom Icon", "customIconHint": "The selected image is copied into TermiPad's controlled local directory and normalized as PNG. It is never loaded from the network or carried as a path in JSON backups.", "customIconReady": "Local icon updated.", "customIconImportFailed": "The selected image could not be saved.", "toolDescription": "Tool description", "toolTrust": "Source & Trust", "installationSource": "Installation source", "metadataSource": "Metadata source", "matchConfidence": "Match confidence", "repository": "Linked repository",
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
        format(key, String(value), language: language)
    }

    static func format(_ key: String, _ value: String, language: AppLanguage) -> String {
        let template = text(key, language: language)
        return template.replacingOccurrences(of: "%@", with: value)
    }
}
