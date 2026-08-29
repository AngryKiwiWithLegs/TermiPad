import Foundation
import SwiftData

/// 终端工具分类。
enum ToolCategory: String, Codable, CaseIterable, Identifiable {
    case ai = "AI/智能体"
    case development = "开发工具"
    case efficiency = "效率工具"
    case media = "媒体处理"
    case system = "网络与系统"
    case other = "其他/未分类"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .ai: return "sparkles"
        case .development: return "hammer"
        case .efficiency: return "bolt"
        case .media: return "film"
        case .system: return "network"
        case .other: return "square.grid.2x2"
        }
    }

    func displayName(_ language: AppLanguage) -> String {
        switch (self, language) {
        case (.ai, .simplifiedChinese): return "AI/智能体"
        case (.development, .simplifiedChinese): return "开发工具"
        case (.efficiency, .simplifiedChinese): return "效率工具"
        case (.media, .simplifiedChinese): return "媒体处理"
        case (.system, .simplifiedChinese): return "网络与系统"
        case (.other, .simplifiedChinese): return "其他/未分类"
        case (.ai, .english): return "AI & Agents"
        case (.development, .english): return "Development"
        case (.efficiency, .english): return "Productivity"
        case (.media, .english): return "Media"
        case (.system, .english): return "Network & System"
        case (.other, .english): return "Other"
        }
    }
}

/// 安装来源只表示可执行文件的发现位置，不代表发行方已经过验证。
enum ToolInstallationSource: String, Codable, CaseIterable, Sendable {
    case homebrew
    case cargo
    case npm
    case pnpm
    case bun
    case userLocal
    case manual
    case other

    static func detect(for executablePath: String) -> ToolInstallationSource {
        let path = (executablePath as NSString).standardizingPath
        if path.hasPrefix("/opt/homebrew/") || path.hasPrefix("/usr/local/Homebrew/") { return .homebrew }
        if path.contains("/.cargo/") { return .cargo }
        if path.contains("/.npm-") || path.contains("/npm/") { return .npm }
        if path.contains("/pnpm/") { return .pnpm }
        if path.contains("/.bun/") { return .bun }
        if path.hasPrefix(NSHomeDirectory() + "/") { return .userLocal }
        return .other
    }

    func displayName(_ language: AppLanguage) -> String {
        switch (self, language) {
        case (.homebrew, .simplifiedChinese): return "Homebrew"
        case (.cargo, .simplifiedChinese): return "Cargo"
        case (.npm, .simplifiedChinese): return "npm"
        case (.pnpm, .simplifiedChinese): return "pnpm"
        case (.bun, .simplifiedChinese): return "Bun"
        case (.userLocal, .simplifiedChinese): return "用户本地目录"
        case (.manual, .simplifiedChinese): return "手动添加"
        case (.other, .simplifiedChinese): return "其他位置"
        case (.homebrew, .english): return "Homebrew"
        case (.cargo, .english): return "Cargo"
        case (.npm, .english): return "npm"
        case (.pnpm, .english): return "pnpm"
        case (.bun, .english): return "Bun"
        case (.userLocal, .english): return "User-local directory"
        case (.manual, .english): return "Added manually"
        case (.other, .english): return "Other location"
        }
    }
}

/// 描述工具信息来自何处。用户自行编辑后始终优先于远程补充。
enum ToolMetadataProvenance: String, Codable, CaseIterable, Sendable {
    case local
    case manual
    case githubOfficial
    case githubMatched

    func displayName(_ language: AppLanguage) -> String {
        switch (self, language) {
        case (.local, .simplifiedChinese): return "本地扫描"
        case (.manual, .simplifiedChinese): return "手动填写"
        case (.githubOfficial, .simplifiedChinese): return "GitHub 官方映射"
        case (.githubMatched, .simplifiedChinese): return "GitHub 高置信匹配"
        case (.local, .english): return "Local scan"
        case (.manual, .english): return "Entered manually"
        case (.githubOfficial, .english): return "Official GitHub mapping"
        case (.githubMatched, .english): return "High-confidence GitHub match"
        }
    }
}

/// 发现候选的处理状态。候选不再自动进入工具墙，用户必须明确收录。
enum CandidateStatus: String, Codable, CaseIterable {
    case pending
    case accepted
    case ignored
}

/// 工具格悬停时的面向使用者说明。
struct ToolHoverContent: Equatable {
    let purpose: String
    let gettingStarted: String

    func accessibilitySummary(language: AppLanguage) -> String {
        switch language {
        case .simplifiedChinese:
            return "用途：\(purpose)。如何开始：\(gettingStarted)"
        case .english:
            return "Purpose: \(purpose). Getting started: \(gettingStarted)"
        }
    }
}

/// 将原始工具元数据转化为友好的“用途 + 如何开始”说明。
///
/// AI 或 GitHub 补充是异步操作；其进度文本不应被写成用户看到的工具功能说明。
enum ToolDescriptionPresentation {
    private struct ToolUsageProfile {
        let chinesePurpose: String
        let chineseGettingStarted: String
        let englishPurpose: String
        let englishGettingStarted: String

        func content(language: AppLanguage) -> ToolHoverContent {
            switch language {
            case .simplifiedChinese:
                return ToolHoverContent(purpose: chinesePurpose, gettingStarted: chineseGettingStarted)
            case .english:
                return ToolHoverContent(purpose: englishPurpose, gettingStarted: englishGettingStarted)
            }
        }
    }

    private static let placeholderDescriptions: Set<String> = [
        "正在尝试 ai 增强",
        "正在通过 ai 深度解析中",
        "由本机扫描发现，等待补充说明",
        "本地发现的终端工具",
        "已发现本地工具；配置 ai 服务后可自动提炼命令说明",
        "discovered locally; details are pending enrichment",
        "attempting ai enrichment",
        "ai enrichment in progress",
        "local terminal tool"
    ]

    private static let knownToolProfiles: [String: ToolUsageProfile] = [
        "claude": .init(
            chinesePurpose: "在终端中与 Claude 协作完成分析、写作或编程任务。",
            chineseGettingStarted: "点击启动后，直接描述你想完成的任务；需要参数时 TermiPad 会先询问。",
            englishPurpose: "Work with Claude from the terminal for analysis, writing, or coding tasks.",
            englishGettingStarted: "Launch it, then describe the task you want to complete. TermiPad asks for required values first."
        ),
        "codex": .init(
            chinesePurpose: "在终端中使用 Codex 协助完成代码理解、修改与开发任务。",
            chineseGettingStarted: "点击启动后，说明要处理的代码任务；建议先在目标项目目录中启动。",
            englishPurpose: "Use Codex in the terminal for code understanding, changes, and development tasks.",
            englishGettingStarted: "Launch it from the project you want to work on, then describe the coding task."
        ),
        "gemini": .init(
            chinesePurpose: "在终端中使用 Gemini 协助处理问答、分析与开发任务。",
            chineseGettingStarted: "点击启动后，直接输入你的问题或任务说明。",
            englishPurpose: "Use Gemini in the terminal for questions, analysis, and development tasks.",
            englishGettingStarted: "Launch it, then enter the question or task you want help with."
        ),
        "ollama": .init(
            chinesePurpose: "用于在本机管理和运行 Ollama 模型。",
            chineseGettingStarted: "点击启动后按终端提示操作；如要直接对话，可在“编辑工具”中设置常用模型启动命令。",
            englishPurpose: "Manage and run Ollama models locally.",
            englishGettingStarted: "Launch it and follow the terminal prompts. You can set a preferred model command in Edit Tool."
        ),
        "aider": .init(
            chinesePurpose: "让 AI 在当前代码仓库中协助阅读、修改和生成代码。",
            chineseGettingStarted: "建议在项目目录中点击启动，然后描述需要修改的代码。",
            englishPurpose: "Use AI to read, change, and generate code in the current repository.",
            englishGettingStarted: "Launch it from your project directory, then describe the code change you need."
        ),
        "gh": .init(
            chinesePurpose: "通过终端管理 GitHub 仓库、议题、拉取请求与发布流程。",
            chineseGettingStarted: "点击启动后按终端提示选择操作；首次使用可先完成 GitHub 登录。",
            englishPurpose: "Manage GitHub repositories, issues, pull requests, and releases from the terminal.",
            englishGettingStarted: "Launch it and follow the prompts. Sign in to GitHub first if this is your first use."
        ),
        "lazygit": .init(
            chinesePurpose: "以交互式界面查看改动并管理当前项目的 Git 提交与分支。",
            chineseGettingStarted: "建议在 Git 项目目录中点击启动；使用方向键和界面快捷键完成操作。",
            englishPurpose: "Inspect changes and manage Git commits and branches through an interactive interface.",
            englishGettingStarted: "Launch it from a Git repository, then use the on-screen shortcuts to work."
        ),
        "gitui": .init(
            chinesePurpose: "以终端交互界面查看并管理当前项目的 Git 状态与提交。",
            chineseGettingStarted: "建议在 Git 项目目录中点击启动，并按界面提示操作。",
            englishPurpose: "Inspect and manage the current project's Git state and commits in a terminal interface.",
            englishGettingStarted: "Launch it from a Git repository and follow the on-screen guidance."
        ),
        "ffmpeg": .init(
            chinesePurpose: "用于转换、压缩、剪辑和检查音视频文件。",
            chineseGettingStarted: "点击启动后使用已保存的命令；常用转换任务可在“编辑工具”中预设参数。",
            englishPurpose: "Convert, compress, trim, and inspect audio or video files.",
            englishGettingStarted: "Launch it with the saved command. Set preferred conversion options in Edit Tool for recurring work."
        ),
        "yt-dlp": .init(
            chinesePurpose: "用于按你指定的地址下载可访问的视频或音频内容。",
            chineseGettingStarted: "在“编辑工具”中设置链接参数模板；启动时 TermiPad 会请求你填写链接。",
            englishPurpose: "Download accessible video or audio from an address you provide.",
            englishGettingStarted: "Set a URL template in Edit Tool; TermiPad will ask for the address at launch."
        ),
        "imagemagick": .init(
            chinesePurpose: "用于转换、调整和批量处理图像文件。",
            chineseGettingStarted: "在“编辑工具”中预设输入与输出参数；启动前会让你填写需要的内容。",
            englishPurpose: "Convert, resize, and batch-process image files.",
            englishGettingStarted: "Set input and output values in Edit Tool; TermiPad asks for required values before launch."
        ),
        "magick": .init(
            chinesePurpose: "用于转换、调整和批量处理图像文件。",
            chineseGettingStarted: "在“编辑工具”中预设输入与输出参数；启动前会让你填写需要的内容。",
            englishPurpose: "Convert, resize, and batch-process image files.",
            englishGettingStarted: "Set input and output values in Edit Tool; TermiPad asks for required values before launch."
        ),
        "fzf": .init(
            chinesePurpose: "在终端中用模糊搜索快速筛选文件、目录或命令结果。",
            chineseGettingStarted: "点击启动后输入关键词筛选，使用方向键选择，按回车确认。",
            englishPurpose: "Quickly filter files, directories, or command results with fuzzy search in the terminal.",
            englishGettingStarted: "Launch it, type to filter, use the arrow keys to choose, and press Return to confirm."
        ),
        "ripgrep": .init(
            chinesePurpose: "快速在项目或文件夹中搜索文本内容。",
            chineseGettingStarted: "在“编辑工具”中设置关键词与搜索路径模板，再点击启动。",
            englishPurpose: "Search text quickly across a project or folder.",
            englishGettingStarted: "Set keyword and search-path templates in Edit Tool, then launch it."
        ),
        "rg": .init(
            chinesePurpose: "快速在项目或文件夹中搜索文本内容。",
            chineseGettingStarted: "在“编辑工具”中设置关键词与搜索路径模板，再点击启动。",
            englishPurpose: "Search text quickly across a project or folder.",
            englishGettingStarted: "Set keyword and search-path templates in Edit Tool, then launch it."
        ),
        "eza": .init(
            chinesePurpose: "以更易读的列表查看文件夹内容、文件属性和 Git 状态。",
            chineseGettingStarted: "点击启动查看当前目录；可在“编辑工具”中设置常用路径或显示选项。",
            englishPurpose: "Browse folders with a more readable listing, file metadata, and Git status.",
            englishGettingStarted: "Launch it to inspect the current folder. Set a preferred path or display options in Edit Tool."
        ),
        "bat": .init(
            chinesePurpose: "以带语法高亮和行号的方式在终端中阅读文本文件。",
            chineseGettingStarted: "在“编辑工具”中设置文件路径参数模板，再点击启动。",
            englishPurpose: "Read text files in the terminal with syntax highlighting and line numbers.",
            englishGettingStarted: "Set a file-path parameter template in Edit Tool, then launch it."
        ),
        "aws": .init(
            chinesePurpose: "通过终端查看和管理 AWS 资源与服务。",
            chineseGettingStarted: "启动前确认当前 AWS 登录、配置文件和区域是否正确，再执行命令。",
            englishPurpose: "Inspect and manage AWS resources and services from the terminal.",
            englishGettingStarted: "Confirm the current AWS sign-in, profile, and region before running the command."
        ),
        "vercel": .init(
            chinesePurpose: "连接、预览和部署 Web 项目到 Vercel。",
            chineseGettingStarted: "建议在项目根目录中启动；首次使用请按终端提示完成登录与项目关联。",
            englishPurpose: "Link, preview, and deploy web projects to Vercel.",
            englishGettingStarted: "Launch it from a project root. Follow the prompts to sign in and link the project on first use."
        ),
        "netlify": .init(
            chinesePurpose: "连接、预览和部署 Web 项目到 Netlify。",
            chineseGettingStarted: "建议在项目根目录中启动；首次使用请按终端提示完成登录与站点关联。",
            englishPurpose: "Link, preview, and deploy web projects to Netlify.",
            englishGettingStarted: "Launch it from a project root. Follow the prompts to sign in and link the site on first use."
        ),
        "btop": .init(
            chinesePurpose: "以交互式面板查看本机 CPU、内存、进程和资源占用。",
            chineseGettingStarted: "点击启动后浏览面板；可按界面底部快捷键筛选或结束进程。",
            englishPurpose: "Monitor CPU, memory, processes, and resource use in an interactive dashboard.",
            englishGettingStarted: "Launch it and use the shortcuts shown at the bottom to inspect or manage processes."
        ),
        "htop": .init(
            chinesePurpose: "以交互式列表查看本机进程和资源占用。",
            chineseGettingStarted: "点击启动后使用方向键浏览；按界面提示筛选或管理进程。",
            englishPurpose: "Inspect local processes and resource use in an interactive list.",
            englishGettingStarted: "Launch it, navigate with the arrow keys, and follow the on-screen shortcuts."
        ),
        "tmux": .init(
            chinesePurpose: "在一个终端窗口中组织多个可持续保留的命令会话。",
            chineseGettingStarted: "点击启动后创建或连接会话；可在“编辑工具”中预设常用会话名称。",
            englishPurpose: "Organize multiple persistent command sessions inside one terminal window.",
            englishGettingStarted: "Launch it to create or attach to a session. Set a preferred session name in Edit Tool if useful."
        ),
        "kubectl": .init(
            chinesePurpose: "查看和管理 Kubernetes 集群中的资源与工作负载。",
            chineseGettingStarted: "确认当前终端配置指向目标集群后，再使用已保存的命令启动。",
            englishPurpose: "Inspect and manage resources and workloads in a Kubernetes cluster.",
            englishGettingStarted: "Confirm that your terminal is configured for the intended cluster before launching the saved command."
        ),
        "terraform": .init(
            chinesePurpose: "根据配置查看、规划和管理基础设施资源。",
            chineseGettingStarted: "建议在包含 Terraform 配置的项目目录中启动，并先检查计划输出。",
            englishPurpose: "Inspect, plan, and manage infrastructure resources from configuration files.",
            englishGettingStarted: "Launch it from a Terraform project and review the plan output before applying changes."
        )
    ]

    static func hoverContent(for tool: TerminalTool, language: AppLanguage) -> ToolHoverContent {
        let savedDescription = tool.toolDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !isPlaceholder(savedDescription) {
            return ToolHoverContent(
                purpose: concise(savedDescription),
                gettingStarted: genericGettingStarted(for: tool.category, language: language)
            )
        }

        if let profile = profile(for: tool.name) {
            return profile.content(language: language)
        }

        return ToolHoverContent(
            purpose: categoryPurpose(for: tool.category, language: language),
            gettingStarted: genericGettingStarted(for: tool.category, language: language)
        )
    }

    static func displayDescription(for tool: TerminalTool, language: AppLanguage) -> String {
        hoverContent(for: tool, language: language).purpose
    }

    static func isPlaceholder(_ description: String) -> Bool {
        let normalized = description
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return normalized.isEmpty
            || placeholderDescriptions.contains(normalized)
            || normalized.hasPrefix("正在尝试 ai")
            || normalized.hasPrefix("正在通过 ai")
            || normalized.hasPrefix("discovered locally")
    }

    private static func profile(for toolName: String) -> ToolUsageProfile? {
        let normalizedName = toolName.lowercased()
        if let directMatch = knownToolProfiles[normalizedName] { return directMatch }
        return knownToolProfiles.first { normalizedName.contains($0.key) }?.value
    }

    private static func concise(_ value: String) -> String {
        let oneLine = value
            .components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? value
        return String(oneLine.prefix(120))
    }

    private static func categoryPurpose(for category: ToolCategory, language: AppLanguage) -> String {
        switch (category, language) {
        case (.ai, .simplifiedChinese): return "用于在终端中进入 AI 助手或智能体工作流。"
        case (.development, .simplifiedChinese): return "用于代码、构建、版本控制或部署相关的开发任务。"
        case (.efficiency, .simplifiedChinese): return "用于搜索、浏览或加速常用的终端工作。"
        case (.media, .simplifiedChinese): return "用于下载、转换或处理音视频与图像文件。"
        case (.system, .simplifiedChinese): return "用于查看、配置或维护网络与本机系统。"
        case (.other, .simplifiedChinese): return "用于启动你本机安装的命令行工具。"
        case (.ai, .english): return "Use an AI assistant or agent workflow from the terminal."
        case (.development, .english): return "Handle coding, building, version-control, or deployment tasks."
        case (.efficiency, .english): return "Search, browse, or speed up everyday terminal work."
        case (.media, .english): return "Download, convert, or process audio, video, and image files."
        case (.system, .english): return "Inspect, configure, or maintain networking and the local system."
        case (.other, .english): return "Launch a command-line tool installed on this Mac."
        }
    }

    private static func genericGettingStarted(for category: ToolCategory, language: AppLanguage) -> String {
        switch language {
        case .simplifiedChinese:
            switch category {
            case .ai:
                return "点击启动后，直接说明你想完成的任务；需要参数时 TermiPad 会先询问。"
            case .development:
                return "建议在目标项目目录中启动；可通过右键“编辑工具”查看或调整启动命令。"
            case .efficiency:
                return "点击启动后按终端或交互界面的提示继续操作。"
            case .media:
                return "可通过右键“编辑工具”设置文件路径和常用参数模板，再点击启动。"
            case .system:
                return "启动前请确认目标环境；可通过右键“编辑工具”检查将要执行的命令。"
            case .other:
                return "点击启动后按终端提示继续；不确定用途时，可通过右键“编辑工具”查看命令。"
            }
        case .english:
            switch category {
            case .ai:
                return "Launch it, then describe the task you want to complete. TermiPad asks for required values first."
            case .development:
                return "Launch it from the relevant project when possible. Use Edit Tool to review or adjust the command."
            case .efficiency:
                return "Launch it, then follow the terminal or interactive interface prompts."
            case .media:
                return "Use Edit Tool to set file paths and reusable option templates before launching."
            case .system:
                return "Confirm the intended environment first, then use Edit Tool to review the command before launching."
            case .other:
                return "Launch it and follow the terminal prompts. Use Edit Tool to inspect the command if its purpose is unclear."
            }
        }
    }
}

/// 用户已收录的可交互终端工具。
@Model
final class TerminalTool {
    var id: UUID
    var name: String
    var executablePath: String
    /// 用户明确选择的本地工作目录；旧记录缺失时为 nil，不改变原有启动行为。
    var workingDirectoryPath: String?
    var commandTemplate: String
    var toolDescription: String
    var categoryRawValue: String
    var iconSymbol: String
    /// 内置图标的持久化样式标识；nil 兼容旧记录并表示按工具名自动派生。
    var iconStyleIdentifier: String?
    /// 仅保存由 ToolIconStore 创建的受控本地 PNG 文件名；旧记录缺失该字段时为 nil。
    var customIconFilename: String?
    var iconURLString: String?
    var repositoryFullName: String?
    var installationSourceRawValue: String?
    var metadataProvenanceRawValue: String?
    var metadataMatchConfidence: Int?
    var metadataUpdatedAt: Date?
    /// 旧版存储没有该字段时为 nil，并安全视为未收藏。
    var isFavorite: Bool?
    var isUserCustomized: Bool
    var isHidden: Bool = false
    var variableValuesJSON: String?
    var lastLaunchedAt: Date?
    var createdAt: Date

    // MARK: - M0 移动端入口（track-protocol stage 4）

    /// 手机端显示名；nil = 用本地 `name`（避免展示冗余）。
    /// 永不出本机（仅在 iPhone/Telegram/PWA 入口收到时回传）。
    var mobileDisplayName: String?
    /// 手机端用途说明；**严禁**含命令/路径/变量，由客户端在展示前脱敏。
    /// 永不出本机。
    var mobileDescription: String
    /// 是否进入手机端最小化目录。默认 false——用户必须明确开启。
    /// 永不出本机（除 iPhone/Telegram/PWA 入口收到外）。
    var showInMobileEntry: Bool
    /// 允许手机端对**已批准图标**发起启动请求。默认 false。
    /// 即便 showInMobileEntry=true，此项为 false 时手机只能看不能启动。
    var allowMobileLaunchRequest: Bool
    /// 手机端启动请求的本地确认策略。默认 .everyTime（最严格）。
    var mobileLocalConfirmPolicy: MobileLocalConfirmPolicy
    /// 用户点"撤销"按钮时写入的当前时间戳。
    /// 双撤销机制：撤销时间戳 + 把 showInMobileEntry/allowMobileLaunchRequest 都设回 false。
    /// 写入后 iPhone 端该工具立即失效（客户端会查询新值）。
    var revokeMobilePermissionAt: Date?

    var category: ToolCategory {
        get { ToolCategory(rawValue: categoryRawValue) ?? .other }
        set { categoryRawValue = newValue.rawValue }
    }

    var installationSource: ToolInstallationSource {
        get { ToolInstallationSource(rawValue: installationSourceRawValue ?? "") ?? .other }
        set { installationSourceRawValue = newValue.rawValue }
    }

    var metadataProvenance: ToolMetadataProvenance {
        get { ToolMetadataProvenance(rawValue: metadataProvenanceRawValue ?? "") ?? .local }
        set { metadataProvenanceRawValue = newValue.rawValue }
    }

    var favorite: Bool {
        get { isFavorite ?? false }
        set { isFavorite = newValue }
    }

    init(
        name: String,
        executablePath: String,
        commandTemplate: String,
        toolDescription: String = "",
        category: ToolCategory = .other,
        iconSymbol: String = "terminal",
        installationSource: ToolInstallationSource? = nil,
        isUserCustomized: Bool = false
    ) {
        id = UUID()
        self.name = name
        self.executablePath = executablePath
        workingDirectoryPath = nil
        self.commandTemplate = commandTemplate.isEmpty ? name : commandTemplate
        self.toolDescription = toolDescription
        categoryRawValue = category.rawValue
        self.iconSymbol = iconSymbol
        // 新记录由工具库归一化流程分配空闲回退组合，避免新增工具改变已有未知工具的图标。
        iconStyleIdentifier = nil
        customIconFilename = nil
        iconURLString = nil
        repositoryFullName = nil
        installationSourceRawValue = (installationSource ?? ToolInstallationSource.detect(for: executablePath)).rawValue
        metadataProvenanceRawValue = isUserCustomized ? ToolMetadataProvenance.manual.rawValue : ToolMetadataProvenance.local.rawValue
        metadataMatchConfidence = 0
        metadataUpdatedAt = nil
        isFavorite = false
        self.isUserCustomized = isUserCustomized
        isHidden = false
        variableValuesJSON = nil
        lastLaunchedAt = nil
        createdAt = Date()
        // M0 默认值：所有移动端入口字段默认关闭/最严策略。
        // 新增工具绝不自动暴露在手机端——用户必须主动去"手机入口"section 开启。
        mobileDisplayName = nil
        mobileDescription = ""
        showInMobileEntry = false
        allowMobileLaunchRequest = false
        mobileLocalConfirmPolicy = .everyTime
        revokeMobilePermissionAt = nil
    }
}

/// 工具库的本地展示排序规则。最近使用列表不访问网络，也不改变持久化数据。
enum ToolLibraryOrdering {
    static func recentFirst(_ tools: [TerminalTool]) -> [TerminalTool] {
        tools.sorted {
            let leftDate = $0.lastLaunchedAt ?? .distantPast
            let rightDate = $1.lastLaunchedAt ?? .distantPast
            if leftDate == rightDate {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return leftDate > rightDate
        }
    }
}

/// M0 移动端入口：手机端启动请求的本地确认策略。详见
/// `docs/m0-m1-mobile-entry-design.md` §2.3。
enum MobileLocalConfirmPolicy: String, Codable, CaseIterable, Sendable {
    /// 每次手机请求都要求 Mac 本机用户在工作台点击确认
    case everyTime
    /// 同一会话内（≤5min）不重复确认；新会话或超时会话必须重确认
    case perSession
    /// 仅 5min 内的会话，且任务风险为 .low；其他情况要求重确认
    case lowRiskSessionOnly
}

/// 扫描到但尚未由用户确认收录的命令。
@Model
final class CandidateTool {
    var id: UUID
    var name: String
    var executablePath: String
    var categoryRawValue: String
    var statusRawValue: String
    var installationSourceRawValue: String?
    var discoveredAt: Date

    var category: ToolCategory {
        get { ToolCategory(rawValue: categoryRawValue) ?? .other }
        set { categoryRawValue = newValue.rawValue }
    }

    var status: CandidateStatus {
        get { CandidateStatus(rawValue: statusRawValue) ?? .pending }
        set { statusRawValue = newValue.rawValue }
    }

    var installationSource: ToolInstallationSource {
        get { ToolInstallationSource(rawValue: installationSourceRawValue ?? "") ?? .other }
        set { installationSourceRawValue = newValue.rawValue }
    }

    init(
        name: String,
        executablePath: String,
        category: ToolCategory,
        installationSource: ToolInstallationSource? = nil,
        status: CandidateStatus = .pending
    ) {
        id = UUID()
        self.name = name
        self.executablePath = executablePath
        categoryRawValue = category.rawValue
        statusRawValue = status.rawValue
        installationSourceRawValue = (installationSource ?? ToolInstallationSource.detect(for: executablePath)).rawValue
        discoveredAt = Date()
    }

    /// 将用户确认收录的候选转换为本地工具。命令仅来自候选名称，不采纳网络补充内容。
    func makeToolForAcceptance() -> TerminalTool {
        TerminalTool(
            name: name,
            executablePath: executablePath,
            commandTemplate: name,
            toolDescription: "",
            category: category,
            iconSymbol: ToolIconCatalog.definition(for: name, category: category).symbol,
            installationSource: installationSource
        )
    }
}
