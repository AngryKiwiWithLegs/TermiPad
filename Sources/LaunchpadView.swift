import SwiftUI
import SwiftData

/// macOS 原生风格的终端工具启动器主界面。
struct LaunchpadView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TerminalTool.name) private var tools: [TerminalTool]
    @Query(sort: \CandidateTool.discoveredAt, order: .reverse) private var candidates: [CandidateTool]

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

    private var terminalTarget: TerminalTarget {
        TerminalTarget(rawValue: terminalTargetRawValue) ?? .systemTerminal
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
        if isInbox { return "候选收件箱" }
        if isHiddenLibrary { return "已隐藏工具" }
        return selectedCategory?.rawValue ?? "所有工具"
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(text: $searchText, placement: .toolbar, prompt: isInbox ? "筛选候选工具" : "搜索已收录工具")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: performScan) {
                    Label(isScanning ? "正在发现" : "发现工具", systemImage: isScanning ? "arrow.triangle.2.circlepath" : "plus.viewfinder")
                }
                .disabled(isScanning)
                .accessibilityIdentifier("discover-tools-button")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isPresentingManualTool = true
                } label: {
                    Label("手动添加", systemImage: "plus")
                }
            }
        }
        .alert("工具发现完成", isPresented: Binding(
            get: { scanMessage != nil },
            set: { if !$0 { scanMessage = nil } }
        )) {
            Button("好", role: .cancel) { scanMessage = nil }
        } message: {
            Text(scanMessage ?? "")
        }
        .alert(launchNotice?.title ?? "操作结果", isPresented: Binding(
            get: { launchNotice != nil },
            set: { if !$0 { launchNotice = nil } }
        )) {
            Button("好", role: .cancel) { launchNotice = nil }
        } message: {
            Text(launchNotice?.message ?? "")
        }
        .sheet(item: $selectedToolForEdit) { tool in
            ToolEditView(tool: tool, onDeleted: { selectedToolForEdit = nil })
        }
        .sheet(item: $toolForVariables) { tool in
            VariableInputSheet(tool: tool) { command in
                execute(command: command, for: tool)
            }
        }
        .sheet(isPresented: $isPresentingManualTool) {
            ManualToolSheet { tool in
                modelContext.insert(tool)
                try? modelContext.save()
            }
        }
    }

    private var sidebar: some View {
        List(selection: $selectedSidebarItem) {
            Section("工具库") {
                Label("所有工具", systemImage: "square.grid.2x2")
                    .tag(SidebarItem.all.rawValue)
                Label("候选收件箱", systemImage: "tray.full")
                    .badge(pendingCandidates.filter { $0.status == .pending }.count)
                    .tag(SidebarItem.inbox.rawValue)
                Label("已隐藏", systemImage: "eye.slash")
                    .tag(SidebarItem.hidden.rawValue)
            }

            Section("分类") {
                ForEach(ToolCategory.allCases) { category in
                    Label(category.rawValue, systemImage: category.iconName)
                        .tag(category.rawValue)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("TermiPad")
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 270)
    }

    @ViewBuilder
    private var detailContent: some View {
        if isInbox {
            CandidateInboxView(
                candidates: filteredCandidates,
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
                        Button("前往工具库") { selectedSidebarItem = SidebarItem.all.rawValue }
                    } else {
                        Button("发现工具", action: performScan)
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
                                action: { requestLaunch(for: tool) },
                                onEdit: { selectedToolForEdit = tool },
                                onToggleVisibility: { toggleVisibility(for: tool) }
                            )
                        }
                    }
                    .padding(24)
                }
            }
        }
        .navigationTitle(contentTitle)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Text("\(filteredTools.count) 个工具")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .accessibilityIdentifier("tool-library")
    }

    private var emptyLibraryTitle: String {
        isHiddenLibrary ? "没有已隐藏工具" : "尚未收录工具"
    }

    private var emptyLibrarySymbol: String {
        isHiddenLibrary ? "eye" : "terminal"
    }

    private var emptyLibraryDescription: String {
        if isHiddenLibrary { return "在工具卡片的右键菜单中选择“隐藏”后，它会出现在这里。" }
        return "使用“发现工具”扫描 PATH 中的交互式命令行工具；扫描结果会先进入候选收件箱。"
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
                    ? "没有发现新的候选工具。"
                    : "发现 \(freshItems.count) 个候选工具。请在“候选收件箱”中确认要收录的项目。"
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
            toolDescription: "由本机扫描发现，等待补充说明。",
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
            case .launched(let message), .copied(let message):
                launchNotice = LaunchNotice(title: "操作完成", message: message)
            }
        } catch {
            launchNotice = LaunchNotice(title: "无法启动 \(tool.name)", message: error.localizedDescription)
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
    let candidates: [CandidateTool]
    let onAccept: (CandidateTool) -> Void
    let onIgnore: (CandidateTool) -> Void
    let onRestore: (CandidateTool) -> Void

    var body: some View {
        Group {
            if candidates.isEmpty {
                ContentUnavailableView(
                    "候选收件箱为空",
                    systemImage: "tray",
                    description: Text("扫描后发现的新命令会先显示在这里；确认收录后才进入工具库。")
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
                        Text(candidate.category.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if candidate.status == .ignored {
                            Button("恢复") { onRestore(candidate) }
                                .buttonStyle(.bordered)
                        } else {
                            Button("忽略") { onIgnore(candidate) }
                                .buttonStyle(.bordered)
                            Button("收录") { onAccept(candidate) }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .accessibilityIdentifier("candidate-inbox")
    }
}

/// 单个工具卡片：保持 macOS 控件的克制密度，并允许右键管理。
struct ToolTile: View {
    let tool: TerminalTool
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
                Text(tool.category.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 142)
            .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: action) { Label("按模板启动", systemImage: "play") }
            Divider()
            Button(action: onEdit) { Label("编辑工具", systemImage: "slider.horizontal.3") }
            Button(action: onToggleVisibility) {
                Label(tool.isHidden ? "取消隐藏" : "隐藏工具", systemImage: tool.isHidden ? "eye" : "eye.slash")
            }
        }
        .accessibilityIdentifier("tool-tile-\(tool.name)")
        .help(tool.toolDescription.isEmpty ? tool.commandTemplate : tool.toolDescription)
    }
}

struct VariableInputSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var tool: TerminalTool
    let onLaunch: (String) -> Void
    @State private var values: [String: String]
    @State private var validationMessage: String?

    init(tool: TerminalTool, onLaunch: @escaping (String) -> Void) {
        self.tool = tool
        self.onLaunch = onLaunch
        _values = State(initialValue: CommandTemplate.loadValues(from: tool))
    }

    private var variables: [String] { CommandTemplate.variables(in: tool.commandTemplate) }

    var body: some View {
        NavigationStack {
            Form {
                Section("需要填写的参数") {
                    ForEach(variables, id: \.self) { variable in
                        TextField(variable.replacingOccurrences(of: "_", with: " "), text: Binding(
                            get: { values[variable] ?? "" },
                            set: { values[variable] = $0 }
                        ))
                    }
                }
                Section("命令预览") {
                    Text(preview)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                Text("参数会以 shell 安全转义方式写入本次命令，并保存在本机以便下次使用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .navigationTitle("启动 \(tool.name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("启动") { submit() }
                }
            }
            .alert("请检查参数", isPresented: Binding(
                get: { validationMessage != nil },
                set: { if !$0 { validationMessage = nil } }
            )) {
                Button("好", role: .cancel) { validationMessage = nil }
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
                Section("基本信息") {
                    TextField("工具名称", text: $name)
                    TextField("可执行文件路径", text: $executablePath)
                    Picker("分类", selection: $category) {
                        ForEach(ToolCategory.allCases) { category in
                            Text(category.rawValue).tag(category)
                        }
                    }
                }
                Section("启动命令") {
                    TextField("命令模板", text: $commandTemplate)
                    Text("需要用户填写的内容可写为 `{{variable_name}}`，首次启动时会自动询问。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("说明（可选）", text: $toolDescription, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("手动添加工具")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var tool: TerminalTool
    let onDeleted: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("启动方式") {
                    TextField("启动命令", text: $tool.commandTemplate)
                    Text("可使用 `{{variable_name}}` 创建首次启动填写项。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(tool.executablePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Section("整理") {
                    Picker("分类", selection: $tool.category) {
                        ForEach(ToolCategory.allCases) { category in
                            Text(category.rawValue).tag(category)
                        }
                    }
                    Toggle("隐藏此工具", isOn: $tool.isHidden)
                    TextField("工具描述", text: $tool.toolDescription, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section {
                    Button("删除工具", role: .destructive) {
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
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
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
