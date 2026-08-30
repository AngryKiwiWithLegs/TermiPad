import SwiftUI
import SwiftData
import Combine
import UniformTypeIdentifiers

/// macOS 原生风格的终端工具启动器主界面。
struct LaunchpadView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \TerminalTool.name) private var tools: [TerminalTool]
    @Query(sort: \CandidateTool.discoveredAt, order: .reverse) private var candidates: [CandidateTool]

    @AppStorage("TermiPad.language") private var languageRawValue = AppLanguage.simplifiedChinese.rawValue
    @AppStorage("TermiPad.appearance") private var appearanceRawValue = AppAppearance.system.rawValue
    @AppStorage("TermiPad.terminalTarget") private var terminalTargetRawValue = TerminalTarget.systemTerminal.rawValue
    @AppStorage("TermiPad.autoEnrich") private var autoEnrich = false
    @AppStorage("TermiPad.showIgnoredCandidates") private var showIgnoredCandidates = false
    @AppStorage("TermiPad.hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var searchText = ""
    @State private var selectedSidebarItem = SidebarItem.all.rawValue
    @State private var isScanning = false
    @State private var selectedToolForEdit: TerminalTool?
    @State private var toolForVariables: TerminalTool?
    @State private var isPresentingManualTool = false
    @State private var isPresentingOnboarding = false
    @State private var scanMessage: String?
    @State private var launchNotice: LaunchNotice?

    private let columns = [GridItem(.adaptive(minimum: 142, maximum: 180), spacing: 18)]

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRawValue) ?? .simplifiedChinese
    }

    private var terminalTarget: TerminalTarget {
        TerminalTarget(rawValue: terminalTargetRawValue) ?? .systemTerminal
    }

    private var theme: SoftMacTheme { SoftMacTheme(colorScheme: colorScheme) }

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRawValue) ?? .system
    }

    private var appearanceSelection: Binding<String> {
        Binding(
            get: { appearanceRawValue },
            set: { newValue in
                if reduceMotion {
                    appearanceRawValue = newValue
                } else {
                    withAnimation(.easeInOut(duration: 0.30)) {
                        appearanceRawValue = newValue
                    }
                }
            }
        )
    }

    private var isInbox: Bool { selectedSidebarItem == SidebarItem.inbox.rawValue }
    private var isFavorites: Bool { selectedSidebarItem == SidebarItem.favorites.rawValue }
    private var isRecent: Bool { selectedSidebarItem == SidebarItem.recent.rawValue }
    private var isHiddenLibrary: Bool { selectedSidebarItem == SidebarItem.hidden.rawValue }
    private var isDiscoveryPreview: Bool { selectedSidebarItem == SidebarItem.discovery.rawValue }
    private var isInstallEnvironment: Bool { selectedSidebarItem == SidebarItem.installEnvironment.rawValue }
    private var isTaskWorkbench: Bool { selectedSidebarItem == SidebarItem.taskWorkbench.rawValue }
    private var isSettings: Bool { selectedSidebarItem == SidebarItem.settings.rawValue }

    private var selectedCategory: ToolCategory? {
        ToolCategory(rawValue: selectedSidebarItem)
    }

    private var pendingCandidates: [CandidateTool] {
        candidates.filter { candidate in
            candidate.status == .pending || (showIgnoredCandidates && candidate.status == .ignored)
        }
    }

    private var filteredTools: [TerminalTool] {
        let matchingTools = tools.filter { tool in
            let visibilityMatches = isHiddenLibrary ? tool.isHidden : !tool.isHidden
            let favoriteMatches = !isFavorites || tool.favorite
            let recentMatches = !isRecent || tool.lastLaunchedAt != nil
            let searchMatches = searchText.isEmpty
                || tool.name.localizedCaseInsensitiveContains(searchText)
                || ToolDescriptionPresentation.displayDescription(for: tool, language: language)
                    .localizedCaseInsensitiveContains(searchText)
            let categoryMatches = selectedCategory == nil || tool.category == selectedCategory
            return visibilityMatches && favoriteMatches && recentMatches && searchMatches && categoryMatches
        }
        guard isRecent else { return matchingTools }
        return ToolLibraryOrdering.recentFirst(matchingTools)
    }

    private var contentTitle: String {
        if isInbox { return AppCopy.text("inbox", language: language) }
        if isFavorites { return AppCopy.text("favorites", language: language) }
        if isRecent { return AppCopy.text("recent", language: language) }
        if isHiddenLibrary { return AppCopy.text("hidden", language: language) }
        return selectedCategory?.displayName(language) ?? AppCopy.text("allTools", language: language)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailContent
                .termiPadWorkspacePanel()
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            normalizeIconAssignments()
            if ProcessInfo.processInfo.environment["TERMIPAD_UI_TEST_OPEN_SETTINGS"] == "1" {
                selectedSidebarItem = SidebarItem.settings.rawValue
            }
            if !hasCompletedOnboarding {
                isPresentingOnboarding = true
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: isInbox ? AppCopy.text("searchCandidates", language: language) : AppCopy.text("searchTools", language: language))
        .onReceive(NotificationCenter.default.publisher(for: .termiPadAppAction)) { notification in
            guard let action = TermiPadAppAction.from(notification) else { return }
            switch action {
            case .openLibrary:
                selectedSidebarItem = SidebarItem.all.rawValue
            case .showFavorites:
                selectedSidebarItem = SidebarItem.favorites.rawValue
            case .showRecent:
                selectedSidebarItem = SidebarItem.recent.rawValue
            case .discoverTools:
                performScan()
            case .addManualTool:
                isPresentingManualTool = true
            }
        }
        .toolbar {
            if !isSettings && !isTaskWorkbench {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: performScan) {
                        Label(isScanning ? AppCopy.text("discovering", language: language) : AppCopy.text("discover", language: language), systemImage: isScanning ? "arrow.triangle.2.circlepath" : "plus.viewfinder")
                    }
                    .disabled(isScanning)
                    .accessibilityIdentifier("discover-tools-button")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { isPresentingManualTool = true } label: {
                        Label(AppCopy.text("addTool", language: language), systemImage: "plus")
                    }
                }
            }
            ToolbarItemGroup(placement: .automatic) {
                Picker(AppCopy.text("settingsLanguage", language: language), selection: $languageRawValue) {
                    Text("中").tag(AppLanguage.simplifiedChinese.rawValue)
                    Text("EN").tag(AppLanguage.english.rawValue)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.regular)
                .frame(width: 82)
                .padding(.trailing, 8)
                .help(AppCopy.text("settingsLanguage", language: language))
                .accessibilityIdentifier("language-segmented-control")

                Picker(AppCopy.text("settingsAppearance", language: language), selection: appearanceSelection) {
                    ForEach(AppAppearance.allCases) { option in
                        Image(systemName: option.symbol).tag(option.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.regular)
                .frame(width: 126)
                .help("\(AppCopy.text("settingsAppearance", language: language)): \(appearance.displayName(language))")
                .accessibilityIdentifier("appearance-segmented-control")
            }
        }
        .alert(AppCopy.text("scanComplete", language: language), isPresented: Binding(
            get: { scanMessage != nil },
            set: { if !$0 { scanMessage = nil } }
        )) {
            Button(AppCopy.text("ok", language: language), role: .cancel) { scanMessage = nil }
        } message: {
            Text(scanMessage ?? "")
        }
        .alert(launchNotice?.title ?? AppCopy.text("operationResult", language: language), isPresented: Binding(
            get: { launchNotice != nil },
            set: { if !$0 { launchNotice = nil } }
        )) {
            if let repairTool = launchNotice?.repairTool {
                Button(AppCopy.text("editTool", language: language)) {
                    launchNotice = nil
                    selectedToolForEdit = repairTool
                }
            }
            Button(AppCopy.text("ok", language: language), role: .cancel) { launchNotice = nil }
        } message: {
            Text(launchNotice?.message ?? "")
        }
        .sheet(item: $selectedToolForEdit) { tool in
            ToolEditView(language: language, tool: tool, onDeleted: { selectedToolForEdit = nil })
        }
        .sheet(item: $toolForVariables) { tool in
            VariableInputSheet(tool: tool, language: language) { command in
                execute(command: command, for: tool)
            }
        }
        .sheet(isPresented: $isPresentingManualTool) {
            ManualToolSheet(language: language) { tool in
                modelContext.insert(tool)
                normalizeIconAssignments(in: tools + [tool])
                try? modelContext.save()
            }
        }
        .sheet(isPresented: $isPresentingOnboarding) {
            OnboardingSheet(language: language, autoEnrich: $autoEnrich) {
                hasCompletedOnboarding = true
                isPresentingOnboarding = false
            }
            .interactiveDismissDisabled()
        }
    }

    private var sidebar: some View {
        List(selection: $selectedSidebarItem) {
            Section(AppCopy.text("toolLibrary", language: language)) {
                Label(AppCopy.text("allTools", language: language), systemImage: "square.grid.2x2")
                    .tag(SidebarItem.all.rawValue)
                Label(AppCopy.text("inbox", language: language), systemImage: "tray.full")
                    .badge(pendingCandidates.filter { $0.status == .pending }.count)
                    .tag(SidebarItem.inbox.rawValue)
                Label(AppCopy.text("favorites", language: language), systemImage: "star")
                    .tag(SidebarItem.favorites.rawValue)
                    .accessibilityIdentifier("sidebar-favorites")
                Label(AppCopy.text("recent", language: language), systemImage: "clock")
                    .tag(SidebarItem.recent.rawValue)
                    .accessibilityIdentifier("sidebar-recent")
                Label(AppCopy.text("hidden", language: language), systemImage: "eye.slash")
                    .tag(SidebarItem.hidden.rawValue)
            }

            Section(AppCopy.text("discoverySection", language: language)) {
                Label(AppCopy.text("discoveryPreview", language: language), systemImage: "safari")
                    .tag(SidebarItem.discovery.rawValue)
                    .accessibilityIdentifier("sidebar-discovery-preview")
                Label(AppCopy.text("installAndEnvironment", language: language), systemImage: "checklist")
                    .tag(SidebarItem.installEnvironment.rawValue)
                    .accessibilityIdentifier("sidebar-install-environment")
                Label(AppCopy.text("sidebarTaskWorkbench", language: language), systemImage: "checkmark.shield")
                    .tag(SidebarItem.taskWorkbench.rawValue)
                    .accessibilityIdentifier("sidebar-task-workbench")
            }

            Section(AppCopy.text("categories", language: language)) {
                ForEach(ToolCategory.allCases) { category in
                    Label(category.displayName(language), systemImage: category.iconName)
                        .tag(category.rawValue)
                }
            }

            Section {
                Label(AppCopy.text("settings", language: language), systemImage: "gearshape")
                    .tag(SidebarItem.settings.rawValue)
                    .accessibilityIdentifier("sidebar-settings")
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(theme.sidebarTint)
        .navigationTitle("TermiPad")
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 270)
    }

    @ViewBuilder
    private var detailContent: some View {
        if isSettings {
            PreferencesView(embeddedInNavigation: true)
                .navigationTitle(AppCopy.text("settings", language: language))
                .accessibilityIdentifier("sidebar-settings-detail")
        } else if isDiscoveryPreview {
            DiscoveryPreviewView(language: language)
        } else if isInstallEnvironment {
            InstallEnvironmentView(language: language)
        } else if isTaskWorkbench {
            TaskPolicyWorkbenchView(language: language)
                .accessibilityIdentifier("task-policy-workbench")
        } else if isInbox {
            CandidateInboxView(
                candidates: filteredCandidates,
                language: language,
                onAccept: accept,
                onIgnore: ignore,
                onRestore: restoreCandidate,
                onAcceptAll: acceptAllPending
            )
            .navigationTitle(contentTitle)
        } else {
            toolLibrary
        }
    }

    private var filteredCandidates: [CandidateTool] {
        pendingCandidates.filter { candidate in
            searchText.isEmpty
                || candidate.name.localizedCaseInsensitiveContains(searchText)
                || candidate.executablePath.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var toolLibrary: some View {
        Group {
            if filteredTools.isEmpty {
                ContentUnavailableView {
                    Label(emptyLibraryTitle, systemImage: emptyLibrarySymbol)
                } description: {
                    Text(emptyLibraryDescription)
                } actions: {
                    if isHiddenLibrary {
                        Button(AppCopy.text("goToLibrary", language: language)) { selectedSidebarItem = SidebarItem.all.rawValue }
                    } else {
                        Button(AppCopy.text("discover", language: language), action: performScan)
                            .buttonStyle(.borderedProminent)
                    }
                }
                .accessibilityIdentifier("empty-state-title")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(filteredTools) { tool in
                            ToolTile(
                                tool: tool,
                                language: language,
                                action: { requestLaunch(for: tool) },
                                onEdit: { selectedToolForEdit = tool },
                                onToggleFavorite: { toggleFavorite(for: tool) },
                                onToggleVisibility: { toggleVisibility(for: tool) }
                            )
                        }
                    }
                    .padding(20)
                }
                .background(theme.contentSurface)
            }
        }
        .navigationTitle(contentTitle)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Text("\(filteredTools.count) \(AppCopy.text("tools", language: language))")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .accessibilityIdentifier("tool-library")
    }

    private var emptyLibraryTitle: String {
        if isFavorites { return AppCopy.text("noFavorites", language: language) }
        if isRecent { return AppCopy.text("noRecent", language: language) }
        if isHiddenLibrary { return AppCopy.text("noHidden", language: language) }
        return searchText.isEmpty ? AppCopy.text("noTools", language: language) : AppCopy.text("noMatches", language: language)
    }

    private var emptyLibrarySymbol: String {
        if isFavorites { return "star" }
        if isRecent { return "clock" }
        return isHiddenLibrary ? "eye" : "terminal"
    }

    private var emptyLibraryDescription: String {
        if isFavorites { return AppCopy.text("favoritesDescription", language: language) }
        if isRecent { return AppCopy.text("recentDescription", language: language) }
        if isHiddenLibrary { return AppCopy.text("hiddenDescription", language: language) }
        return AppCopy.text("scanDescription", language: language)
    }

    private func performScan() {
        guard hasCompletedOnboarding else { return }
        guard !isScanning else { return }
        isScanning = true
        let knownNames = Set(tools.map { $0.name.lowercased() })
            .union(candidates.map { $0.name.lowercased() })

        DispatchQueue.global(qos: .userInitiated).async {
            let discovered = ToolScanner.scanInstalledTools()
            let freshItems = discovered.filter { !knownNames.contains($0.name.lowercased()) }

            DispatchQueue.main.async {
                for item in freshItems {
                    let category = ToolScanner.guessCategory(for: item.name)
                    modelContext.insert(CandidateTool(name: item.name, executablePath: item.path, category: category))
                }
                try? modelContext.save()
                DiagnosticsStore.shared.record(.scanCompleted, itemCount: freshItems.count)
                isScanning = false
                scanMessage = freshItems.isEmpty
                    ? AppCopy.text("noNewCandidates", language: language)
                    : AppCopy.format("foundCandidates", freshItems.count, language: language)
                if !freshItems.isEmpty { selectedSidebarItem = SidebarItem.inbox.rawValue }
            }
        }
    }

    private func accept(_ candidate: CandidateTool) {
        let category = candidate.category
        let tool = candidate.makeToolForAcceptance()
        modelContext.insert(tool)
        candidate.status = .accepted
        normalizeIconAssignments(in: tools + [tool])
        try? modelContext.save()

        if autoEnrich {
            Task { await enrich(tool: tool, toolName: candidate.name, fallbackCategory: category) }
        }
    }

    /// 一键收录收件箱中所有"待收录"候选。仍由用户显式点击触发（不是后台自动跑），
    /// 每个候选走与单个收录完全相同的 makeToolForAcceptance + 图标归一化路径。
    private func acceptAllPending() {
        let pending = candidates.filter { $0.status == .pending }
        guard !pending.isEmpty else { return }
        var newTools: [TerminalTool] = []
        for candidate in pending {
            let tool = candidate.makeToolForAcceptance()
            modelContext.insert(tool)
            candidate.status = .accepted
            newTools.append(tool)
        }
        normalizeIconAssignments(in: tools + newTools)
        try? modelContext.save()
        DiagnosticsStore.shared.record(.scanCompleted, itemCount: newTools.count)

        if autoEnrich {
            for (candidate, tool) in zip(pending, newTools) {
                let category = candidate.category
                Task { await enrich(tool: tool, toolName: candidate.name, fallbackCategory: category) }
            }
        }
        selectedSidebarItem = SidebarItem.all.rawValue
    }

    private func ignore(_ candidate: CandidateTool) {
        candidate.status = .ignored
        try? modelContext.save()
    }

    private func restoreCandidate(_ candidate: CandidateTool) {
        candidate.status = .pending
        try? modelContext.save()
    }

    private func toggleFavorite(for tool: TerminalTool) {
        tool.favorite.toggle()
        try? modelContext.save()
    }

    private func toggleVisibility(for tool: TerminalTool) {
        tool.isHidden.toggle()
        try? modelContext.save()
    }

    private func normalizeIconAssignments(in library: [TerminalTool]? = nil) {
        if ToolIconCatalog.normalizeFallbackAssignments(for: library ?? tools) {
            try? modelContext.save()
        }
    }

    @MainActor
    private func enrich(tool: TerminalTool, toolName: String, fallbackCategory: ToolCategory) async {
        guard let repository = try? await GitHubService.findRepository(for: toolName) else { return }
        tool.repositoryFullName = repository.repoFullName
        // GitHub owner 头像并不等同于工具官方图标；保留本地图标目录以避免错误品牌归属。
        tool.iconURLString = nil
        tool.metadataProvenance = repository.metadataProvenance
        tool.metadataMatchConfidence = repository.matchConfidence
        tool.metadataUpdatedAt = Date()

        if !tool.isUserCustomized,
           let intelligence = try? await AIService.analyzeTool(name: toolName, readme: repository.readmeContent) {
            tool.toolDescription = intelligence.description
            tool.category = ToolCategory(rawValue: intelligence.suggestedCategory) ?? fallbackCategory
        }
        try? modelContext.save()
    }

    private func requestLaunch(for tool: TerminalTool) {
        let health = ToolHealthChecker.check(executablePath: tool.executablePath)
        guard health.permitsLaunch else {
            DiagnosticsStore.shared.record(.toolHealthBlocked)
            launchNotice = LaunchNotice(
                title: "\(AppCopy.text("cannotLaunch", language: language)) \(tool.name)",
                message: health.recoveryMessage(language),
                repairTool: tool
            )
            return
        }
        let workingDirectoryHealth = ToolLaunchContext.workingDirectoryHealth(for: tool.workingDirectoryPath)
        guard workingDirectoryHealth != .unavailable else {
            DiagnosticsStore.shared.record(.workingDirectoryUnavailable)
            launchNotice = LaunchNotice(
                title: "\(AppCopy.text("cannotLaunch", language: language)) \(tool.name)",
                message: workingDirectoryHealth.recoveryMessage(language),
                repairTool: tool
            )
            return
        }
        if CommandTemplate.variables(in: tool.commandTemplate).isEmpty {
            execute(command: tool.commandTemplate, for: tool)
        } else {
            toolForVariables = tool
        }
    }

    private func execute(command: String, for tool: TerminalTool) {
        let contextualCommand = ToolLaunchContext.command(command, inWorkingDirectory: tool.workingDirectoryPath)
        do {
            let result = try TerminalLauncher.launch(command: contextualCommand, target: terminalTarget)
            switch result {
            case .launched(let target):
                DiagnosticsStore.shared.record(.launchSucceeded, terminalTarget: target)
                tool.lastLaunchedAt = Date()
                try? modelContext.save()
                let message = target == .iTerm
                    ? AppCopy.text("itermLaunched", language: language)
                    : AppCopy.text("terminalLaunched", language: language)
                launchNotice = LaunchNotice(title: AppCopy.text("operationComplete", language: language), message: message)
            case .copied(let target):
                DiagnosticsStore.shared.record(.commandCopied, terminalTarget: target)
                let message = target == .warp
                    ? AppCopy.text("warpCopied", language: language)
                    : AppCopy.text("copied", language: language)
                launchNotice = LaunchNotice(title: AppCopy.text("operationComplete", language: language), message: message)
            case .copiedAfterAutomationPermissionDenied(let target):
                DiagnosticsStore.shared.record(.automationFallback, terminalTarget: target)
                launchNotice = LaunchNotice(
                    title: AppCopy.text("automationPermissionNeeded", language: language),
                    message: automationPermissionCopiedMessage(for: target)
                )
            }
        } catch {
            DiagnosticsStore.shared.record(.launchFailed, terminalTarget: terminalTarget)
            let message = (error as? TerminalLauncherError)?.message(language: language) ?? error.localizedDescription
            launchNotice = LaunchNotice(title: "\(AppCopy.text("cannotLaunch", language: language)) \(tool.name)", message: message)
        }
    }

    private func automationPermissionCopiedMessage(for target: TerminalTarget) -> String {
        let targetName = target.displayName(language)
        switch language {
        case .simplifiedChinese:
            return "命令已复制到剪贴板。要启用一键启动，请前往“系统设置 → 隐私与安全性 → 自动化”，允许 TermiPad 控制 \(targetName)，然后再次点击此工具。"
        case .english:
            return "The command was copied to the clipboard. To enable one-click launch, go to System Settings → Privacy & Security → Automation, allow TermiPad to control \(targetName), then select this tool again."
        }
    }
}

private enum SidebarItem: String {
    case all = "__all_tools__"
    case inbox = "__candidate_inbox__"
    case favorites = "__favorite_tools__"
    case recent = "__recent_tools__"
    case hidden = "__hidden_tools__"
    case discovery = "__discovery_preview__"
    case installEnvironment = "__install_environment__"
    case taskWorkbench = "__task_workbench__"
    case settings = "__settings__"
}

private struct LaunchNotice {
    let title: String
    let message: String
    let repairTool: TerminalTool?

    init(title: String, message: String, repairTool: TerminalTool? = nil) {
        self.title = title
        self.message = message
        self.repairTool = repairTool
    }
}

struct CandidateInboxView: View {
    @Environment(\.colorScheme) private var colorScheme
    let candidates: [CandidateTool]
    let language: AppLanguage
    let onAccept: (CandidateTool) -> Void
    let onIgnore: (CandidateTool) -> Void
    let onRestore: (CandidateTool) -> Void
    var onAcceptAll: (() -> Void)? = nil

    /// 只有"待收录"的候选可被批量收录；已忽略的保持原状。
    private var pendingCount: Int {
        candidates.filter { $0.status == .pending }.count
    }

    var body: some View {
        Group {
            if candidates.isEmpty {
                ContentUnavailableView(
                    AppCopy.text("emptyInbox", language: language),
                    systemImage: "tray",
                    description: Text(AppCopy.text("inboxDescription", language: language))
                )
            } else {
                List(candidates) { candidate in
                    HStack(spacing: 12) {
                        Image(systemName: ToolIconCatalog.definition(for: candidate.name, category: candidate.category).symbol)
                            .frame(width: 26)
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(candidate.name).fontWeight(.medium)
                            Text(candidate.executablePath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(candidate.category.displayName(language))
                            Text(candidate.installationSource.displayName(language))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        if candidate.status == .ignored {
                            Button(AppCopy.text("restore", language: language)) { onRestore(candidate) }
                                .buttonStyle(.bordered)
                        } else {
                            Button(AppCopy.text("ignore", language: language)) { onIgnore(candidate) }
                                .buttonStyle(.bordered)
                            Button(AppCopy.text("collect", language: language)) { onAccept(candidate) }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollContentBackground(.hidden)
                .background(SoftMacTheme(colorScheme: colorScheme).contentSurface)
                .safeAreaInset(edge: .bottom) {
                    if pendingCount > 0, let onAcceptAll {
                        HStack {
                            Spacer()
                            Button {
                                onAcceptAll()
                            } label: {
                                Label(
                                    AppCopy.format("acceptAll", pendingCount, language: language),
                                    systemImage: "checkmark.circle.fill"
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .accessibilityIdentifier("inbox-accept-all")
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .background(.bar)
                    }
                }
            }
        }
        .accessibilityIdentifier("candidate-inbox")
    }
}

/// 单个工具卡片：保持 macOS 控件的克制密度，并允许右键管理。
struct ToolTile: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    let tool: TerminalTool
    let language: AppLanguage
    let action: () -> Void
    let onEdit: () -> Void
    let onToggleFavorite: () -> Void
    let onToggleVisibility: () -> Void

    private var hoverContent: ToolHoverContent {
        ToolDescriptionPresentation.hoverContent(for: tool, language: language)
    }

    private var theme: SoftMacTheme { SoftMacTheme(colorScheme: colorScheme) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ToolIconView(tool: tool, size: 68)
                Text(tool.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 128)
            .background(isHovering ? theme.workspacePanelSurface : theme.cardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isHovering ? theme.workspacePanelStroke : theme.cardStroke, lineWidth: 1)
            }
            .shadow(color: theme.cardShadow, radius: isHovering ? 8 : 4, y: isHovering ? 4 : 2)
            .scaleEffect(isHovering && !reduceMotion ? 1.015 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if reduceMotion {
                isHovering = hovering
            } else {
                withAnimation(.easeInOut(duration: 0.14)) {
                    isHovering = hovering
                }
            }
        }
        .popover(isPresented: $isHovering, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            ToolHoverTooltip(content: hoverContent, language: language)
                .presentationBackground(.clear)
        }
        .contextMenu {
            Button(action: action) { Label(AppCopy.text("launchByTemplate", language: language), systemImage: "play") }
            Divider()
            Button(action: onEdit) { Label(AppCopy.text("editTool", language: language), systemImage: "slider.horizontal.3") }
            Button(action: onToggleFavorite) {
                Label(tool.favorite ? AppCopy.text("unfavoriteTool", language: language) : AppCopy.text("favoriteTool", language: language), systemImage: tool.favorite ? "star.slash" : "star")
            }
            Button(action: onToggleVisibility) {
                Label(tool.isHidden ? AppCopy.text("unhideTool", language: language) : AppCopy.text("hideTool", language: language), systemImage: tool.isHidden ? "eye" : "eye.slash")
            }
        }
        .accessibilityIdentifier("tool-tile-\(tool.name)")
        .accessibilityLabel("\(tool.name), \(hoverContent.accessibilitySummary(language: language))")
        .accessibilityHint(AppCopy.text("launchByTemplate", language: language))
    }
}

/// 使用中性浅灰连续圆角，避免系统默认黑色 Help 气泡与应用配色脱节。
private struct ToolHoverTooltip: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: ToolHoverContent
    let language: AppLanguage

    private var theme: SoftMacTheme { SoftMacTheme(colorScheme: colorScheme) }
    private var purposeTitle: String { language == .simplifiedChinese ? "用途" : "Purpose" }
    private var gettingStartedTitle: String { language == .simplifiedChinese ? "如何开始" : "Getting started" }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            tooltipSection(title: purposeTitle, symbol: "lightbulb", text: content.purpose)
            Divider().overlay(theme.hoverStroke)
            tooltipSection(title: gettingStartedTitle, symbol: "play.circle", text: content.gettingStarted)
        }
        .padding(12)
        .frame(width: 292, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .background(theme.hoverSurface.opacity(0.78), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(theme.hoverStroke, lineWidth: 1)
        }
        .shadow(color: theme.hoverShadow, radius: 12, y: 5)
        .accessibilityElement(children: .combine)
    }

    private func tooltipSection(title: String, symbol: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
    }
}

struct VariableInputSheet: View {
    let language: AppLanguage
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var tool: TerminalTool
    let onLaunch: (String) -> Void
    @State private var values: [String: String]
    @State private var validationMessage: String?

    init(tool: TerminalTool, language: AppLanguage, onLaunch: @escaping (String) -> Void) {
        self.tool = tool
        self.language = language
        self.onLaunch = onLaunch
        _values = State(initialValue: CommandTemplate.loadValues(from: tool))
    }

    private var variables: [String] { CommandTemplate.variables(in: tool.commandTemplate) }

    var body: some View {
        NavigationStack {
            Form {
                Section(AppCopy.text("variables", language: language)) {
                    ForEach(variables, id: \.self) { variable in
                        TextField(variable.replacingOccurrences(of: "_", with: " "), text: Binding(
                            get: { values[variable] ?? "" },
                            set: { values[variable] = $0 }
                        ))
                    }
                }
                Section(AppCopy.text("commandPreview", language: language)) {
                    Text(preview)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                Text(AppCopy.text("variableSecurityHint", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .navigationTitle("\(AppCopy.text("launch", language: language)) \(tool.name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppCopy.text("cancel", language: language)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppCopy.text("launch", language: language)) { submit() }
                }
            }
            .alert(AppCopy.text("checkParameters", language: language), isPresented: Binding(
                get: { validationMessage != nil },
                set: { if !$0 { validationMessage = nil } }
            )) {
                Button(AppCopy.text("ok", language: language), role: .cancel) { validationMessage = nil }
            } message: {
                Text(validationMessage ?? "")
            }
        }
        .frame(minWidth: 520, minHeight: 340)
    }

    private var preview: String {
        (try? CommandTemplate.render(template: tool.commandTemplate, values: values)) ?? tool.commandTemplate
    }

    private func submit() {
        do {
            let command = try CommandTemplate.render(template: tool.commandTemplate, values: values)
            CommandTemplate.saveValues(values, to: tool)
            try? modelContext.save()
            dismiss()
            onLaunch(command)
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}

struct ManualToolSheet: View {
    let language: AppLanguage
    @Environment(\.dismiss) private var dismiss
    let onSave: (TerminalTool) -> Void

    @State private var name = ""
    @State private var executablePath = ""
    @State private var commandTemplate = ""
    @State private var toolDescription = ""
    @State private var category = ToolCategory.other
    @State private var iconStyleIdentifier: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(AppCopy.text("basicInfo", language: language)) {
                    TextField(AppCopy.text("toolName", language: language), text: $name)
                    TextField(AppCopy.text("executablePath", language: language), text: $executablePath)
                    Picker(AppCopy.text("categories", language: language), selection: $category) {
                        ForEach(ToolCategory.allCases) { category in
                            Text(category.displayName(language)).tag(category)
                        }
                    }
                }
                Section(AppCopy.text("launchCommand", language: language)) {
                    TextField(AppCopy.text("commandTemplate", language: language), text: $commandTemplate)
                    Text(AppCopy.text("variableHint", language: language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(AppCopy.text("description", language: language), text: $toolDescription, axis: .vertical)
                        .lineLimit(2...4)
                }
                ToolIconSelectionSection(
                    toolName: name,
                    category: category,
                    styleIdentifier: $iconStyleIdentifier,
                    language: language
                )
            }
            .formStyle(.grouped)
            .navigationTitle(AppCopy.text("addTool", language: language))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(AppCopy.text("cancel", language: language)) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppCopy.text("save", language: language)) {
                        let command = commandTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? name : commandTemplate
                        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let tool = TerminalTool(
                            name: normalizedName,
                            executablePath: executablePath.trimmingCharacters(in: .whitespacesAndNewlines),
                            commandTemplate: command,
                            toolDescription: toolDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                            category: category,
                            iconSymbol: ToolIconCatalog.definition(for: name, category: category).symbol,
                            installationSource: .manual,
                            isUserCustomized: true
                        )
                        if let iconStyleIdentifier,
                           let choice = ToolIconCatalog.manualChoices.first(where: { $0.id == iconStyleIdentifier }) {
                            tool.iconStyleIdentifier = choice.id
                            tool.iconSymbol = choice.definition.symbol
                        }
                        onSave(tool)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 540, minHeight: 420)
    }
}

struct ToolEditView: View {
    let language: AppLanguage
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var tool: TerminalTool
    let onDeleted: () -> Void
    @State private var isImportingCustomIcon = false
    @State private var isChoosingWorkingDirectory = false
    @State private var customIconMessage: String?
    @State private var isConfirmingMobileRevoke = false
    @State private var mobileRevokeMessage: String?

    private var health: ToolHealth {
        ToolHealthChecker.check(executablePath: tool.executablePath)
    }

    private var workingDirectoryHealth: ToolWorkingDirectoryHealth {
        ToolLaunchContext.workingDirectoryHealth(for: tool.workingDirectoryPath)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(AppCopy.text("launchCommand", language: language)) {
                    TextField(AppCopy.text("launchCommand", language: language), text: $tool.commandTemplate)
                    Text(AppCopy.text("editVariableHint", language: language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(AppCopy.text("executablePath", language: language), text: $tool.executablePath)
                    Text(AppCopy.text("executablePathHint", language: language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section(AppCopy.text("organize", language: language)) {
                    Picker(AppCopy.text("categories", language: language), selection: $tool.category) {
                        ForEach(ToolCategory.allCases) { category in
                            Text(category.displayName(language)).tag(category)
                        }
                    }
                    Toggle(AppCopy.text("hideThisTool", language: language), isOn: $tool.isHidden)
                    TextField(AppCopy.text("toolDescription", language: language), text: $tool.toolDescription, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section(AppCopy.text("toolHealth", language: language)) {
                    LabeledContent(AppCopy.text("toolHealth", language: language), value: health.displayName(language))
                    if !health.recoveryMessage(language).isEmpty {
                        Text(health.recoveryMessage(language))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section(AppCopy.text("workingDirectory", language: language)) {
                    LabeledContent(AppCopy.text("workingDirectory", language: language), value: workingDirectoryHealth.displayName(language))
                    if let workingDirectoryPath = tool.workingDirectoryPath {
                        Text(workingDirectoryPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    HStack {
                        Button(AppCopy.text("chooseWorkingDirectory", language: language)) {
                            isChoosingWorkingDirectory = true
                        }
                        .accessibilityIdentifier("tool-choose-working-directory")
                        Button(AppCopy.text("clearWorkingDirectory", language: language), role: .destructive, action: clearWorkingDirectory)
                            .disabled(tool.workingDirectoryPath == nil)
                    }
                    if !workingDirectoryHealth.recoveryMessage(language).isEmpty {
                        Text(workingDirectoryHealth.recoveryMessage(language))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(AppCopy.text("workingDirectoryHint", language: language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section(AppCopy.text("customIcon", language: language)) {
                    HStack {
                        Button(AppCopy.text("replaceCustomIcon", language: language)) {
                            isImportingCustomIcon = true
                        }
                        .accessibilityIdentifier("tool-replace-custom-icon")
                        Button(AppCopy.text("removeCustomIcon", language: language), role: .destructive, action: removeCustomIcon)
                            .disabled(tool.customIconFilename == nil)
                    }
                    Text(AppCopy.text("customIconHint", language: language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ToolIconSelectionSection(
                    toolName: tool.name,
                    category: tool.category,
                    styleIdentifier: $tool.iconStyleIdentifier,
                    language: language,
                    onStyleChanged: applyBuiltInIconStyle
                )
                // M0 移动端入口（track-protocol stage 4）：6 字段默认全关，用户必须明确开启。
                // 详见 docs/m0-m1-mobile-entry-design.md §2.4。
                Section {
                    Text(AppCopy.text("mobileEntryHint", language: language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    TextField(AppCopy.text("mobileEntryDisplayName", language: language), text: Binding(
                        get: { tool.mobileDisplayName ?? "" },
                        set: { tool.mobileDisplayName = $0.isEmpty ? nil : $0 }
                    ))
                    .accessibilityIdentifier("tool-mobile-display-name")
                    Text(AppCopy.text("mobileEntryDisplayNameHint", language: language))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField(AppCopy.text("mobileEntryDescription", language: language), text: $tool.mobileDescription, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityIdentifier("tool-mobile-description")
                    Text(AppCopy.text("mobileEntryDescriptionHint", language: language))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Toggle(AppCopy.text("mobileEntryShowInApp", language: language), isOn: $tool.showInMobileEntry)
                        .accessibilityIdentifier("tool-mobile-show-in-entry")
                    Text(AppCopy.text("mobileEntryShowInAppHint", language: language))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    // allowMobileLaunchRequest 仅在 showInMobileEntry=true 时可勾——勾上才能启动。
                    Toggle(AppCopy.text("mobileEntryAllowLaunch", language: language), isOn: $tool.allowMobileLaunchRequest)
                        .disabled(!tool.showInMobileEntry)
                        .accessibilityIdentifier("tool-mobile-allow-launch")
                    Text(AppCopy.text("mobileEntryAllowLaunchHint", language: language))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Picker(AppCopy.text("mobileEntryConfirmPolicy", language: language), selection: $tool.mobileLocalConfirmPolicy) {
                        Text(AppCopy.text("mobileEntryConfirmPolicyEveryTime", language: language))
                            .tag(MobileLocalConfirmPolicy.everyTime)
                        Text(AppCopy.text("mobileEntryConfirmPolicyPerSession", language: language))
                            .tag(MobileLocalConfirmPolicy.perSession)
                        Text(AppCopy.text("mobileEntryConfirmPolicyLowRiskSessionOnly", language: language))
                            .tag(MobileLocalConfirmPolicy.lowRiskSessionOnly)
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("tool-mobile-confirm-policy")
                    Button(role: .destructive) {
                        isConfirmingMobileRevoke = true
                    } label: {
                        Label(AppCopy.text("mobileEntryRevoke", language: language), systemImage: "iphone.slash")
                    }
                    .accessibilityIdentifier("tool-mobile-revoke")
                    .disabled(!tool.showInMobileEntry && !tool.allowMobileLaunchRequest && tool.revokeMobilePermissionAt == nil)
                } header: {
                    Text(AppCopy.text("mobileEntrySection", language: language))
                        .accessibilityIdentifier("tool-mobile-entry-section")
                }
                Section(AppCopy.text("toolTrust", language: language)) {
                    LabeledContent(AppCopy.text("installationSource", language: language), value: tool.installationSource.displayName(language))
                    LabeledContent(AppCopy.text("metadataSource", language: language), value: tool.metadataProvenance.displayName(language))
                    if let repository = tool.repositoryFullName {
                        LabeledContent(AppCopy.text("repository", language: language), value: repository)
                    }
                    if let confidence = tool.metadataMatchConfidence, confidence > 0 {
                        LabeledContent(AppCopy.text("matchConfidence", language: language), value: "\(confidence)%")
                    }
                }
                Section {
                    Button(AppCopy.text("delete", language: language), role: .destructive) {
                        let customIconFilename = tool.customIconFilename
                        modelContext.delete(tool)
                        do {
                            try modelContext.save()
                            ToolIconStore.shared.removeImage(named: customIconFilename)
                            dismiss()
                            onDeleted()
                        } catch {
                            customIconMessage = AppCopy.text("customIconImportFailed", language: language)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(tool.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(AppCopy.text("cancel", language: language)) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppCopy.text("done", language: language)) {
                        tool.isUserCustomized = true
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 420)
        .alert(AppCopy.text("operationResult", language: language), isPresented: Binding(
            get: { customIconMessage != nil },
            set: { if !$0 { customIconMessage = nil } }
        )) {
            Button(AppCopy.text("ok", language: language), role: .cancel) { customIconMessage = nil }
        } message: {
            Text(customIconMessage ?? "")
        }
        // M0 撤销手机权限确认：双撤销（时间戳 + 字段）确保 iPhone 端立即失效。
        .confirmationDialog(
            AppCopy.text("mobileEntryRevokeConfirm", language: language),
            isPresented: $isConfirmingMobileRevoke,
            titleVisibility: .visible
        ) {
            Button(AppCopy.text("mobileEntryRevoke", language: language), role: .destructive) {
                performMobileRevoke()
            }
            Button(AppCopy.text("cancel", language: language), role: .cancel) { }
        } message: {
            Text(AppCopy.text("mobileEntryRevokeConfirm", language: language))
        }
        .alert(AppCopy.text("operationResult", language: language), isPresented: Binding(
            get: { mobileRevokeMessage != nil },
            set: { if !$0 { mobileRevokeMessage = nil } }
        )) {
            Button(AppCopy.text("ok", language: language), role: .cancel) { mobileRevokeMessage = nil }
        } message: {
            Text(mobileRevokeMessage ?? "")
        }
        .fileImporter(
            isPresented: $isImportingCustomIcon,
            allowedContentTypes: ToolIconStore.supportedContentTypes
        ) { result in
            replaceCustomIcon(with: result)
        }
        .fileImporter(
            isPresented: $isChoosingWorkingDirectory,
            allowedContentTypes: [.folder]
        ) { result in
            updateWorkingDirectory(with: result)
        }
    }

    private func replaceCustomIcon(with result: Result<URL, Error>) {
        guard case .success(let sourceURL) = result else {
            customIconMessage = AppCopy.text("customIconImportFailed", language: language)
            return
        }
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let previousFilename = tool.customIconFilename
        do {
            let filename = try ToolIconStore.shared.storeImage(from: sourceURL)
            tool.customIconFilename = filename
            tool.isUserCustomized = true
            do {
                try modelContext.save()
            } catch {
                tool.customIconFilename = previousFilename
                ToolIconStore.shared.removeImage(named: filename)
                throw error
            }
            ToolIconStore.shared.removeImage(named: previousFilename)
            customIconMessage = AppCopy.text("customIconReady", language: language)
        } catch {
            customIconMessage = AppCopy.text("customIconImportFailed", language: language)
        }
    }

    private func updateWorkingDirectory(with result: Result<URL, Error>) {
        guard case .success(let directoryURL) = result else {
            customIconMessage = AppCopy.text("workingDirectoryUpdateFailed", language: language)
            return
        }
        let didAccess = directoryURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess { directoryURL.stopAccessingSecurityScopedResource() }
        }
        guard let normalizedPath = ToolLaunchContext.normalizedDirectoryPath(directoryURL.path),
              ToolLaunchContext.workingDirectoryHealth(for: normalizedPath) == .available else {
            customIconMessage = AppCopy.text("workingDirectoryUpdateFailed", language: language)
            return
        }
        let previousPath = tool.workingDirectoryPath
        tool.workingDirectoryPath = normalizedPath
        do {
            try modelContext.save()
            customIconMessage = AppCopy.text("workingDirectoryReady", language: language)
        } catch {
            tool.workingDirectoryPath = previousPath
            customIconMessage = AppCopy.text("workingDirectoryUpdateFailed", language: language)
        }
    }

    private func clearWorkingDirectory() {
        let previousPath = tool.workingDirectoryPath
        tool.workingDirectoryPath = nil
        do {
            try modelContext.save()
            customIconMessage = AppCopy.text("workingDirectoryReady", language: language)
        } catch {
            tool.workingDirectoryPath = previousPath
            customIconMessage = AppCopy.text("workingDirectoryUpdateFailed", language: language)
        }
    }

    private func removeCustomIcon() {
        let previousFilename = tool.customIconFilename
        tool.customIconFilename = nil
        do {
            try modelContext.save()
            ToolIconStore.shared.removeImage(named: previousFilename)
            customIconMessage = AppCopy.text("customIconReady", language: language)
        } catch {
            tool.customIconFilename = previousFilename
            customIconMessage = AppCopy.text("customIconImportFailed", language: language)
        }
    }

    private func applyBuiltInIconStyle(_ styleIdentifier: String?) {
        if let styleIdentifier,
           let choice = ToolIconCatalog.manualChoices.first(where: { $0.id == styleIdentifier }) {
            tool.iconSymbol = choice.definition.symbol
        } else {
            tool.iconStyleIdentifier = nil
            tool.iconSymbol = ToolIconCatalog.definition(for: tool.name, category: tool.category).symbol
        }
    }

    /// M0 撤销手机权限：双撤销（写时间戳 + 关 6 字段）。iPhone 端下次心跳会读到新值并立即停用。
    private func performMobileRevoke() {
        tool.revokeMobilePermissionAt = Date()
        tool.showInMobileEntry = false
        tool.allowMobileLaunchRequest = false
        do {
            try modelContext.save()
            DiagnosticsStore.shared.record(.mobilePermissionRevoked)
            mobileRevokeMessage = AppCopy.text("mobileEntryRevokedNotice", language: language)
        } catch {
            mobileRevokeMessage = AppCopy.text("customIconImportFailed", language: language)
        }
    }
}

/// 内置图标选择只改变本地 SwiftData 字段；自定义 PNG 仍由 ToolIconStore 单独优先保存。
private struct ToolIconSelectionSection: View {
    let toolName: String
    let category: ToolCategory
    @Binding var styleIdentifier: String?
    let language: AppLanguage
    var onStyleChanged: ((String?) -> Void)? = nil

    private var automaticTitle: String {
        language == .simplifiedChinese ? "自动匹配" : "Automatic match"
    }

    private var pickerTitle: String {
        language == .simplifiedChinese ? "内置图标" : "Built-in Icons"
    }

    private var resetTitle: String {
        language == .simplifiedChinese ? "恢复自动图标" : "Restore automatic icon"
    }

    private var automaticHint: String {
        language == .simplifiedChinese
            ? "自动图标只由本地工具名称和已保存的回退组合决定；不会访问网络。"
            : "Automatic icons are derived only from the local tool name and its saved fallback combination; they never access the network."
    }

    private var previewDefinition: ToolIconDefinition {
        if let styleIdentifier,
           let choice = ToolIconCatalog.manualChoices.first(where: { $0.id == styleIdentifier }) {
            return choice.definition
        }
        return ToolIconCatalog.definition(for: toolName, category: category)
    }

    var body: some View {
        Section(pickerTitle) {
            HStack(spacing: 12) {
                ToolIconDefinitionView(definition: previewDefinition, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(styleIdentifier == nil ? automaticTitle : pickerTitle)
                        .font(.subheadline.weight(.medium))
                    Text(automaticHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button(resetTitle) {
                styleIdentifier = nil
                onStyleChanged?(nil)
            }
            .disabled(styleIdentifier == nil)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                ForEach(ToolIconCatalog.manualChoices) { choice in
                    Button {
                        styleIdentifier = choice.id
                        onStyleChanged?(choice.id)
                    } label: {
                        VStack(spacing: 5) {
                            ToolIconDefinitionView(definition: choice.definition, size: 32)
                            Text(choice.displayName(language: language))
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(styleIdentifier == choice.id ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(choice.displayName(language: language))
                    .accessibilityAddTraits(styleIdentifier == choice.id ? .isSelected : [])
                }
            }
            .accessibilityIdentifier("tool-built-in-icon-picker")
        }
    }
}


/// 首次启动前说明扫描、数据、网络和终端自动化边界，避免用户在不了解行为时开始发现工具。
private struct OnboardingSheet: View {
    let language: AppLanguage
    @Binding var autoEnrich: Bool
    let onFinish: () -> Void

    private var isChinese: Bool { language == .simplifiedChinese }
    private var title: String { isChinese ? "欢迎使用 TermiPad" : "Welcome to TermiPad" }
    private var introduction: String {
        isChinese
            ? "TermiPad 只整理您主动安装、会直接互动使用的命令行工具。开始前，请确认以下边界。"
            : "TermiPad organizes CLI tools you installed and use interactively. Please review these boundaries before you begin."
    }
    private var finishTitle: String { AppCopy.text("onboardingGetStarted", language: language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.tint)

            Text(title)
                .font(.title2.weight(.semibold))
            Text(introduction)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 14) {
                noticeRow(
                    symbol: "magnifyingglass",
                    title: isChinese ? "扫描先进入候选收件箱" : "Scanning starts in the review inbox",
                    detail: isChinese
                        ? "TermiPad 会检查 PATH 和常见第三方安装目录。新命令不会自动进入工具墙，需由您确认收录。"
                        : "TermiPad checks PATH and common third-party install folders. New commands never enter your library until you accept them."
                )
                noticeRow(
                    symbol: "externaldrive",
                    title: isChinese ? "数据默认只保存在这台 Mac" : "Your data stays on this Mac by default",
                    detail: isChinese
                        ? "工具、分类、命令模板和变量值保存在本地。您可随时编辑、隐藏或删除它们。"
                        : "Tools, categories, command templates, and values are stored locally. You can edit, hide, or delete them at any time."
                )
                noticeRow(
                    symbol: "terminal",
                    title: isChinese ? "命令只在您点击后交给偏好终端" : "Commands run only after you choose a tool",
                    detail: isChinese
                        ? "首次使用 Terminal.app 或 iTerm 时，macOS 可能要求您允许自动化；未授权时命令会复制到剪贴板而不会丢失。"
                        : "macOS may ask before TermiPad controls Terminal.app or iTerm. If permission is unavailable, the command is copied instead of being lost."
                )
            }

            Toggle(isChinese ? "允许可选的 GitHub / AI 网络补充" : "Allow optional GitHub / AI enrichment", isOn: $autoEnrich)
            Text(isChinese
                 ? "关闭时，TermiPad 仍可扫描、整理和启动本地工具；需要时可在设置中重新开启。"
                 : "When off, TermiPad can still scan, organize, and launch local tools. You can enable this later in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button(finishTitle, action: onFinish)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("onboarding-finish")
            }
        }
        .padding(24)
        .frame(width: 520)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding-sheet")
    }

    @ViewBuilder
    private func noticeRow(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.body)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
