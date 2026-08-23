import SwiftUI
import SwiftData

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
    @AppStorage("TermiPad.autoEnrich") private var autoEnrich = true
    @AppStorage("TermiPad.showIgnoredCandidates") private var showIgnoredCandidates = false

    @State private var searchText = ""
    @State private var selectedSidebarItem = SidebarItem.all.rawValue
    @State private var isScanning = false
    @State private var selectedToolForEdit: TerminalTool?
    @State private var toolForVariables: TerminalTool?
    @State private var isPresentingManualTool = false
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
    private var isHiddenLibrary: Bool { selectedSidebarItem == SidebarItem.hidden.rawValue }

    private var selectedCategory: ToolCategory? {
        ToolCategory(rawValue: selectedSidebarItem)
    }

    private var pendingCandidates: [CandidateTool] {
        candidates.filter { candidate in
            candidate.status == .pending || (showIgnoredCandidates && candidate.status == .ignored)
        }
    }

    private var filteredTools: [TerminalTool] {
        tools.filter { tool in
            let visibilityMatches = isHiddenLibrary ? tool.isHidden : !tool.isHidden
            let searchMatches = searchText.isEmpty
                || tool.name.localizedCaseInsensitiveContains(searchText)
                || tool.toolDescription.localizedCaseInsensitiveContains(searchText)
            let categoryMatches = selectedCategory == nil || tool.category == selectedCategory
            return visibilityMatches && searchMatches && categoryMatches
        }
    }

    private var contentTitle: String {
        if isInbox { return AppCopy.text("inbox", language: language) }
        if isHiddenLibrary { return AppCopy.text("hidden", language: language) }
        return selectedCategory?.displayName(language) ?? AppCopy.text("allTools", language: language)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(text: $searchText, placement: .toolbar, prompt: isInbox ? AppCopy.text("searchCandidates", language: language) : AppCopy.text("searchTools", language: language))
        .toolbar {
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
            ToolbarItemGroup(placement: .automatic) {
                Menu {
                    Picker(AppCopy.text("settingsLanguage", language: language), selection: $languageRawValue) {
                        ForEach(AppLanguage.allCases) { option in
                            Text(option.displayName).tag(option.rawValue)
                        }
                    }
                } label: {
                    Label(language.compactName, systemImage: "character")
                }
                .accessibilityIdentifier("language-menu")

                Menu {
                    Picker(AppCopy.text("settingsAppearance", language: language), selection: appearanceSelection) {
                        ForEach(AppAppearance.allCases) { option in
                            Label(option.displayName(language), systemImage: option.symbol).tag(option.rawValue)
                        }
                    }
                } label: {
                    Image(systemName: (AppAppearance(rawValue: appearanceRawValue) ?? .system).symbol)
                }
                .accessibilityIdentifier("appearance-menu")
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
                try? modelContext.save()
            }
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
                Label(AppCopy.text("hidden", language: language), systemImage: "eye.slash")
                    .tag(SidebarItem.hidden.rawValue)
            }

            Section(AppCopy.text("categories", language: language)) {
                ForEach(ToolCategory.allCases) { category in
                    Label(category.displayName(language), systemImage: category.iconName)
                        .tag(category.rawValue)
                }
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
        if isInbox {
            CandidateInboxView(
                candidates: filteredCandidates,
                language: language,
                onAccept: accept,
                onIgnore: ignore,
                onRestore: restoreCandidate
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
                                onToggleVisibility: { toggleVisibility(for: tool) }
                            )
                        }
                    }
                    .padding(24)
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
        if isHiddenLibrary { return AppCopy.text("noHidden", language: language) }
        return searchText.isEmpty ? AppCopy.text("noTools", language: language) : AppCopy.text("noMatches", language: language)
    }

    private var emptyLibrarySymbol: String {
        isHiddenLibrary ? "eye" : "terminal"
    }

    private var emptyLibraryDescription: String {
        if isHiddenLibrary { return AppCopy.text("hiddenDescription", language: language) }
        return AppCopy.text("scanDescription", language: language)
    }

    private func performScan() {
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
        let tool = TerminalTool(
            name: candidate.name,
            executablePath: candidate.executablePath,
            commandTemplate: candidate.name,
            toolDescription: language == .simplifiedChinese ? "由本机扫描发现，等待补充说明。" : "Discovered locally; details are pending enrichment.",
            category: category,
            iconSymbol: ToolIconCatalog.definition(for: candidate.name, category: category).symbol
        )
        modelContext.insert(tool)
        candidate.status = .accepted
        try? modelContext.save()

        if autoEnrich {
            Task { await enrich(tool: tool, toolName: candidate.name, fallbackCategory: category) }
        }
    }

    private func ignore(_ candidate: CandidateTool) {
        candidate.status = .ignored
        try? modelContext.save()
    }

    private func restoreCandidate(_ candidate: CandidateTool) {
        candidate.status = .pending
        try? modelContext.save()
    }

    private func toggleVisibility(for tool: TerminalTool) {
        tool.isHidden.toggle()
        try? modelContext.save()
    }

    @MainActor
    private func enrich(tool: TerminalTool, toolName: String, fallbackCategory: ToolCategory) async {
        guard let repository = try? await GitHubService.findRepository(for: toolName) else { return }
        tool.repositoryFullName = repository.repoFullName
        tool.iconURLString = repository.ownerAvatarURLString

        if !tool.isUserCustomized,
           let intelligence = try? await AIService.analyzeTool(name: toolName, readme: repository.readmeContent) {
            tool.commandTemplate = intelligence.commandTemplate
            tool.toolDescription = intelligence.description
            tool.category = ToolCategory(rawValue: intelligence.suggestedCategory) ?? fallbackCategory
        }
        try? modelContext.save()
    }

    private func requestLaunch(for tool: TerminalTool) {
        if CommandTemplate.variables(in: tool.commandTemplate).isEmpty {
            execute(command: tool.commandTemplate, for: tool)
        } else {
            toolForVariables = tool
        }
    }

    private func execute(command: String, for tool: TerminalTool) {
        do {
            let result = try TerminalLauncher.launch(command: command, target: terminalTarget)
            tool.lastLaunchedAt = Date()
            try? modelContext.save()
            switch result {
            case .launched(let target):
                let message = target == .iTerm
                    ? AppCopy.text("itermLaunched", language: language)
                    : AppCopy.text("terminalLaunched", language: language)
                launchNotice = LaunchNotice(title: AppCopy.text("operationComplete", language: language), message: message)
            case .copied(let target):
                let message = target == .warp
                    ? AppCopy.text("warpCopied", language: language)
                    : AppCopy.text("copied", language: language)
                launchNotice = LaunchNotice(title: AppCopy.text("operationComplete", language: language), message: message)
            }
        } catch {
            let message = (error as? TerminalLauncherError)?.message(language: language) ?? error.localizedDescription
            launchNotice = LaunchNotice(title: "\(AppCopy.text("cannotLaunch", language: language)) \(tool.name)", message: message)
        }
    }
}

private enum SidebarItem: String {
    case all = "__all_tools__"
    case inbox = "__candidate_inbox__"
    case hidden = "__hidden_tools__"
}

private struct LaunchNotice {
    let title: String
    let message: String
}

struct CandidateInboxView: View {
    @Environment(\.colorScheme) private var colorScheme
    let candidates: [CandidateTool]
    let language: AppLanguage
    let onAccept: (CandidateTool) -> Void
    let onIgnore: (CandidateTool) -> Void
    let onRestore: (CandidateTool) -> Void

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
                        Text(candidate.category.displayName(language))
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
            }
        }
        .accessibilityIdentifier("candidate-inbox")
    }
}

/// 单个工具卡片：保持 macOS 控件的克制密度，并允许右键管理。
struct ToolTile: View {
    @Environment(\.colorScheme) private var colorScheme
    let tool: TerminalTool
    let language: AppLanguage
    let action: () -> Void
    let onEdit: () -> Void
    let onToggleVisibility: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ToolIconView(tool: tool, size: 64)
                Text(tool.name)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity)
                Text(tool.category.displayName(language))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 142)
            .background(SoftMacTheme(colorScheme: colorScheme).cardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(SoftMacTheme(colorScheme: colorScheme).cardStroke, lineWidth: 1)
            }
            .shadow(color: SoftMacTheme(colorScheme: colorScheme).cardShadow, radius: 9, y: 4)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: action) { Label(AppCopy.text("launchByTemplate", language: language), systemImage: "play") }
            Divider()
            Button(action: onEdit) { Label(AppCopy.text("editTool", language: language), systemImage: "slider.horizontal.3") }
            Button(action: onToggleVisibility) {
                Label(tool.isHidden ? AppCopy.text("unhideTool", language: language) : AppCopy.text("hideTool", language: language), systemImage: tool.isHidden ? "eye" : "eye.slash")
            }
        }
        .accessibilityIdentifier("tool-tile-\(tool.name)")
        .help(tool.toolDescription.isEmpty ? tool.commandTemplate : tool.toolDescription)
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
            }
            .formStyle(.grouped)
            .navigationTitle(AppCopy.text("addTool", language: language))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(AppCopy.text("cancel", language: language)) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppCopy.text("save", language: language)) {
                        let command = commandTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? name : commandTemplate
                        let tool = TerminalTool(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            executablePath: executablePath.trimmingCharacters(in: .whitespacesAndNewlines),
                            commandTemplate: command,
                            toolDescription: toolDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                            category: category,
                            iconSymbol: ToolIconCatalog.definition(for: name, category: category).symbol,
                            isUserCustomized: true
                        )
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

    var body: some View {
        NavigationStack {
            Form {
                Section(AppCopy.text("launchCommand", language: language)) {
                    TextField(AppCopy.text("launchCommand", language: language), text: $tool.commandTemplate)
                    Text(AppCopy.text("editVariableHint", language: language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(tool.executablePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
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
                Section {
                    Button(AppCopy.text("delete", language: language), role: .destructive) {
                        modelContext.delete(tool)
                        try? modelContext.save()
                        dismiss()
                        onDeleted()
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
    }
}
