import SwiftUI
import SwiftData

/// 仿 macOS Launchpad 风格的终端工具启动器主界面
struct LaunchpadView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TerminalTool.name) private var tools: [TerminalTool]
    
    @State private var searchText: String = ""
    @State private var selectedCategory: ToolCategory? = nil
    @State private var isScanning: Bool = false
    @State private var selectedToolForEdit: TerminalTool? = nil
    
    // 网格布局：自适应列宽，图标宫格展示
    let columns = [
        GridItem(.adaptive(minimum: 110, maximum: 140), spacing: 24)
    ]
    
    var filteredTools: [TerminalTool] {
        tools.filter { tool in
            let matchesSearch = searchText.isEmpty || tool.name.localizedCaseInsensitiveContains(searchText) || tool.toolDescription.localizedCaseInsensitiveContains(searchText)
            let matchesCategory = selectedCategory == nil || tool.category == selectedCategory
            return matchesSearch && matchesCategory
        }
    }
    
    var body: some View {
        ZStack {
            // 背景毛玻璃效果
            Color(.windowBackgroundColor)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // 顶部标题栏与搜索、扫描按钮
                headerBar
                
                // 分类横向标签页
                categoryTabs
                
                // 主体宫格区域
                ScrollView {
                    if filteredTools.isEmpty {
                        emptyStateView
                    } else {
                        LazyVGrid(columns: columns, spacing: 30) {
                            ForEach(filteredTools) { tool in
                                ToolCellView(tool: tool) {
                                    launchTool(tool)
                                } onEdit: {
                                    selectedToolForEdit = tool
                                }
                            }
                        }
                        .padding(.horizontal, 40)
                        .padding(.top, 20)
                    }
                }
            }
            .padding(.vertical, 30)
        }
        .sheet(item: $selectedToolForEdit) { tool in
            ToolEditView(tool: tool)
        }
    }
    
    // 顶部标题栏
    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("TermiPad")
                    .font(.system(size: 28, weight: .bold))
                Text("终端工具图标化启动台")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 搜索框
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜索终端工具...", text: $searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 200)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(10)
            
            // 扫描按钮
            Button(action: performScan) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(isScanning ? 360 : 0))
                        .animation(isScanning ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isScanning)
                    Text(isScanning ? "扫描中..." : "发现工具")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(isScanning)
        }
        .padding(.horizontal, 40)
    }
    
    // 分类标签页
    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                CategoryChip(title: "全部", icon: "square.grid.2x2", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                
                ForEach(ToolCategory.allCases) { category in
                    CategoryChip(title: category.rawValue, icon: category.iconName, isSelected: selectedCategory == category) {
                        selectedCategory = category
                    }
                }
            }
            .padding(.horizontal, 40)
        }
    }
    
    // 空状态视图
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("没有找到相关的终端工具")
                .font(.headline)
                .foregroundColor(.primary)
            Text("点击右上角的“发现工具”按钮，自动扫描您电脑上的命令行工具。")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(100)
    }
    
    // 扫描逻辑
    private func performScan() {
        isScanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let discovered = ToolScanner.scanInstalledTools()
            
            DispatchQueue.main.async {
                let existingNames = Set(tools.map { $0.name })
                
                for item in discovered {
                    if !existingNames.contains(item.name) {
                        let guessedCategory = ToolScanner.guessCategory(for: item.name)
                        let newTool = TerminalTool(
                            name: item.name,
                            executablePath: item.path,
                            commandTemplate: item.name,
                            toolDescription: "自动发现的本地工具",
                            category: guessedCategory,
                            iconSymbol: guessedCategory.iconName
                        )
                        modelContext.insert(newTool)
                    }
                }
                
                try? modelContext.save()
                isScanning = false
            }
        }
    }
    
    // 点击图标启动终端
    private func launchTool(_ tool: TerminalTool) {
        let command = tool.commandTemplate
        
        // 使用 AppleScript 唤起默认终端（如 Terminal.app 或 iTerm2）并执行命令
        let scriptText = """
        tell application "Terminal"
            activate
            do script "\(command)"
        end tell
        """
        
        if let script = NSAppleScript(source: scriptText) {
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            if let error = error {
                print("启动终端失败: \\(error)")
            }
        }
    }
}

/// 分类标签组件
struct CategoryChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color(.controlBackgroundColor))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

/// 单个工具图标网格格子
struct ToolCellView: View {
    let tool: TerminalTool
    let action: () -> Void
    let onEdit: () -> Void
    
    var body: some View {
        VStack(spacing: 10) {
            // 图标主体
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: [Color.accentColor.opacity(0.8), Color.accentColor.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 72, height: 72)
                    .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 4)
                
                Image(systemName: tool.iconSymbol)
                    .font(.system(size: 32))
                    .foregroundColor(.white)
            }
            .contextMenu {
                Button(action: onEdit) {
                    Label("编辑命令与分类", systemImage: "pencil")
                }
            }
            
            // 工具名称
            Text(tool.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .foregroundColor(.primary)
            
            // 分类标签
            Text(tool.category.rawValue)
                .font(.system(size: 10))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(.controlBackgroundColor))
                .foregroundColor(.secondary)
                .cornerRadius(4)
        }
        .frame(width: 110)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

/// 工具编辑弹窗视图
struct ToolEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var tool: TerminalTool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("编辑工具：\\(tool.name)")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("启动命令模板")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("例如: claude --model=sonnet", text: $tool.commandTemplate)
                    .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("分类")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Picker("分类", selection: $tool.category) {
                    ForEach(ToolCategory.allCases) { cat in
                        Text(cat.rawValue).tag(cat)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("工具描述")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("简要说明工具用途...", text: $tool.toolDescription)
                    .textFieldStyle(.roundedBorder)
            }
            
            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                Button("保存") {
                    tool.isUserCustomized = true
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}
