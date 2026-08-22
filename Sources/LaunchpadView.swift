import SwiftUI
import SwiftData

/// macOS 原生风格的终端工具启动器主界面。
struct LaunchpadView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TerminalTool.name) private var tools: [TerminalTool]

    @State private var searchText = ""
    @State private var selectedSidebarItem = SidebarItem.all.rawValue
    @State private var isScanning = false
    @State private var selectedToolForEdit: TerminalTool?
    @State private var scanMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 142, maximum: 180), spacing: 18)]

    private var selectedCategory: ToolCategory? {
        ToolCategory(rawValue: selectedSidebarItem)
    }

    private var filteredTools: [TerminalTool] {
        tools.filter { tool in
            let searchMatches = searchText.isEmpty
                || tool.name.localizedCaseInsensitiveContains(searchText)
                || tool.toolDescription.localizedCaseInsensitiveContains(searchText)
            let categoryMatches = selectedCategory == nil || tool.category == selectedCategory
            return searchMatches && categoryMatches
        }
    }

    private var contentTitle: String {
        selectedCategory?.rawValue ?? "所有工具"
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            toolLibrary
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(text: $searchText, placement: .toolbar, prompt: "搜索工具")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: performScan) {
                    Label(isScanning ? "正在发现" : "发现工具", systemImage: isScanning ? "arrow.triangle.2.circlepath" : "plus.viewfinder")
                }
                .disabled(isScanning)
                .accessibilityIdentifier("discover-tools-button")
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
    }

    private var sidebar: some View {
        List(selection: $selectedSidebarItem) {
            Section("工具库") {
                Label("所有工具", systemImage: "square.grid.2x2")
                    .tag(SidebarItem.all.rawValue)
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

    private var toolLibrary: some View {
        Group {
            if filteredTools.isEmpty {
                ContentUnavailableView {
                    Label(searchText.isEmpty ? "尚未收录工具" : "未找到匹配工具", systemImage: searchText.isEmpty ? "terminal" : "magnifyingglass")
                } description: {
                    Text(searchText.isEmpty
                         ? "使用“发现工具”扫描 PATH 中的交互式命令行工具。"
                         : "尝试修改搜索关键词或切换分类。")
                } actions: {
                    if searchText.isEmpty {
                        Button("发现工具", action: performScan)
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("清除搜索") { searchText = "" }
                    }
                }
                .accessibilityIdentifier("empty-state-title")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(filteredTools) { tool in
                            ToolTile(tool: tool) {
                                launchTool(tool)
                            } onEdit: {
                                selectedToolForEdit = tool
                            }
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
        .sheet(item: $selectedToolForEdit) { tool in
            ToolEditView(tool: tool)
        }
        .accessibilityIdentifier("tool-library")
    }

    private func performScan() {
        guard !isScanning else { return }
        isScanning = true

        DispatchQueue.global(qos: .userInitiated).async {
            let discovered = ToolScanner.scanInstalledTools()

            DispatchQueue.main.async {
                let existingNames = Set(tools.map(\.name))
                var addedCount = 0

                for item in discovered where !existingNames.contains(item.name) {
                    let category = ToolScanner.guessCategory(for: item.name)
                    let tool = TerminalTool(
                        name: item.name,
                        executablePath: item.path,
                        commandTemplate: item.name,
                        toolDescription: "本地发现的终端工具",
                        category: category,
                        iconSymbol: ToolIconCatalog.definition(for: item.name, category: category).symbol
                    )
                    modelContext.insert(tool)
                    addedCount += 1

                    Task {
                        await enrich(tool: tool, toolName: item.name, fallbackCategory: category)
                    }
                }

                try? modelContext.save()
                isScanning = false
                scanMessage = addedCount == 0
                    ? "没有发现新的可收录工具。"
                    : "已收录 \(addedCount) 个工具；其余信息会在后台补充。"
            }
        }
    }

    @MainActor
    private func enrich(tool: TerminalTool, toolName: String, fallbackCategory: ToolCategory) async {
        guard let repository = try? await GitHubService.findRepository(for: toolName) else { return }

        tool.repositoryFullName = repository.repoFullName
        tool.iconURLString = repository.ownerAvatarURLString

        if let intelligence = try? await AIService.analyzeTool(name: toolName, readme: repository.readmeContent) {
            tool.commandTemplate = intelligence.commandTemplate
            tool.toolDescription = intelligence.description
            tool.category = ToolCategory(rawValue: intelligence.suggestedCategory) ?? fallbackCategory
        }

        try? modelContext.save()
    }

    private func launchTool(_ tool: TerminalTool) {
        let command = tool.commandTemplate.replacingOccurrences(of: "\"", with: "\\\"")
        let scriptText = """
        tell application "Terminal"
            activate
            do script "\(command)"
        end tell
        """

        guard let script = NSAppleScript(source: scriptText) else {
            print("无法创建 Terminal AppleScript。")
            return
        }

        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            print("启动终端失败: \(error)")
        }
    }
}

private enum SidebarItem: String {
    case all = "__all_tools__"
}

/// 单个工具卡片：保持 macOS 控件的克制密度，并允许右键编辑。
struct ToolTile: View {
    let tool: TerminalTool
    let action: () -> Void
    let onEdit: () -> Void

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
            Button(action: action) {
                Label("在终端中启动", systemImage: "play")
            }
            Divider()
            Button(action: onEdit) {
                Label("编辑工具", systemImage: "slider.horizontal.3")
            }
        }
        .accessibilityIdentifier("tool-tile-\(tool.name)")
        .help(tool.toolDescription.isEmpty ? tool.commandTemplate : tool.toolDescription)
    }
}

struct ToolEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var tool: TerminalTool

    var body: some View {
        NavigationStack {
            Form {
                Section("启动方式") {
                    TextField("启动命令", text: $tool.commandTemplate)
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
                    TextField("工具描述", text: $tool.toolDescription, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(tool.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        tool.isUserCustomized = true
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 460, minHeight: 300)
    }
}
