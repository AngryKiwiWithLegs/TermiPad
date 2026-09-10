import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var client: CompanionPairingClient
    // M2b-3 新任务表单的选择状态（本地 UI 状态，不进模型）。
    @State private var selectedScopeID: UUID?
    @State private var selectedTaskKind: String?

    var body: some View {
        NavigationStack {
            Form {
                // M2b-1 任务会话页：consoleEntries 非空即显示（数据驱动，
                // 轮询期间 phase 保持稳定——视图不闪动）。
                if !client.consoleEntries.isEmpty {
                    consoleSection
                }
                // M2b-3 新任务提交回执。
                if let result = client.lastTaskProposalResult {
                    Section {
                        if result.status == .accepted {
                            Label("任务已提交，运行状态见上方会话", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label(result.reason ?? "任务被拒绝", systemImage: "xmark.circle")
                                .foregroundStyle(.orange)
                        }
                    } header: {
                        Text("任务提交")
                    }
                }
                // M2b-3 新任务表单：scopes 与 fixedTasks 目录都到齐后渲染。
                if !client.consoleScopes.isEmpty && !client.consoleFixedTasks.isEmpty {
                    newTaskSection
                }
                pairingSection
                if case .paired = client.phase {
                    Section("已配对 Mac") {
                        Button("查看任务会话") {
                            client.openTaskConsole()
                        }
                        .accessibilityIdentifier("companion-open-console")
                        Button("提交新任务") {
                            client.openNewTaskForm()
                        }
                        .accessibilityIdentifier("companion-open-newtask")
                        Button("刷新工具目录") { client.resumeAndFetchTools() }
                            .accessibilityIdentifier("companion-resume-fetch")
                        Button("解除配对", role: .destructive) { client.unpair() }
                            .accessibilityIdentifier("companion-unpair")
                    }
                }
                if case .toolSummaries(let summaries) = client.phase {
                    toolsSection(summaries: summaries)
                }
            }
            .navigationTitle("TermiPad 伴侣")
        }
    }

    /// M2b-1 会话条目流（docs/m2b-remote-task-console-design.md §6）：
    /// 工具启动与固定任务的统一时间线。仅内存渲染——输出片段不落盘。
    @ViewBuilder
    private var consoleSection: some View {
        Section {
            ForEach(client.consoleEntries, id: \.id) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: Self.stateSymbol(for: entry.executionState, kind: entry.kind))
                            .foregroundStyle(Self.stateColor(for: entry.executionState))
                        Text(entry.title).font(.body.bold())
                        Spacer()
                        if let exitCode = entry.exitCode {
                            Text("exit \(exitCode)")
                                .font(.caption.monospaced())
                                .foregroundStyle(exitCode == 0 ? .green : .red)
                        }
                    }
                    if let output = entry.outputSnippet, !output.isEmpty {
                        Text(output)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack {
                        Text(Self.stateText(for: entry.executionState))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let finished = entry.finishedAt {
                            Text(finished.formatted(date: .omitted, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.vertical, 2)
                .accessibilityIdentifier("companion-console-entry-\(entry.id.uuidString)")
            }
            Button("暂停刷新", role: .destructive) { client.closeTaskConsole() }
                .font(.caption)
        } header: {
            Text("任务会话（Mac 实时状态）")
        } footer: {
            Text("显示 Mac 上工具启动与固定任务的运行状态。命令与完整输出不会下发到手机。")
                .font(.caption2)
        }
    }

    // MARK: - 会话状态渲染（T1 TaskExecutionState 原样字符串 + 工具启动两态）

    /// M2b-3 新任务表单（docs/m2b-remote-task-console-design.md §6）：
    /// 选范围 → 选固定任务 → 提交。载荷只有 kind + scopeID 引用。
    @ViewBuilder
    private var newTaskSection: some View {
        Section {
            Picker("项目范围", selection: $selectedScopeID) {
                ForEach(client.consoleScopes, id: \.id) { scope in
                    Text(scope.displayName).tag(scope.id as UUID?)
                }
            }
            .accessibilityIdentifier("companion-newtask-scope")
            ForEach(client.consoleFixedTasks, id: \.kind) { task in
                Button {
                    selectedTaskKind = task.kind
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.purpose).font(.body)
                            Text(task.commandPreview)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: selectedTaskKind == task.kind
                            ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedTaskKind == task.kind ? .green : .secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("companion-newtask-kind-\(task.kind)")
            }
            Button("提交任务") {
                if let scopeID = selectedScopeID, let kind = selectedTaskKind,
                   let task = client.consoleFixedTasks.first(where: { $0.kind == kind }) {
                    client.submitTaskProposal(kind: kind, scopeID: scopeID, title: task.purpose)
                }
            }
            .disabled(selectedScopeID == nil || selectedTaskKind == nil)
            .accessibilityIdentifier("companion-newtask-submit")
        } header: {
            Text("提交新任务（Mac 审阅窗口内执行）")
        } footer: {
            Text("只能提交固定任务目录里的任务；Mac 端本地策略核验（范围/风险/审阅窗口）通过后才执行，可能需要在 Mac 上确认。命令与参数不会下发到手机。")
                .font(.caption2)
        }
    }

    private static func stateSymbol(for state: String, kind: MobileSessionEntry.SessionKind) -> String {
        switch state {
        case "running": return "arrow.triangle.2.circlepath"
        case "succeeded", "launched": return "checkmark.circle.fill"
        case "failed", "launchFailed": return "xmark.circle.fill"
        case "timedOut": return "clock.badge.exclamationmark"
        case "stopped": return "stop.circle"
        case "startRejected", "startFailed": return "slash.circle"
        default: return kind == .toolLaunch ? "terminal" : "circle.dotted"
        }
    }

    private static func stateColor(for state: String) -> Color {
        switch state {
        case "running": return .blue
        case "succeeded", "launched": return .green
        case "failed", "launchFailed", "timedOut": return .red
        case "stopped": return .orange
        default: return .secondary
        }
    }

    private static func stateText(for state: String) -> String {
        switch state {
        case "running": return "运行中"
        case "succeeded": return "成功"
        case "failed": return "失败"
        case "timedOut": return "超时"
        case "stopped": return "已停止"
        case "launched": return "已启动（终端交接）"
        case "launchFailed": return "启动失败"
        case "startRejected": return "被策略拒绝"
        case "startFailed": return "启动出错"
        default: return state
        }
    }

    @ViewBuilder
    private var pairingSection: some View {
        Section {
            switch client.phase {
            case .noCredentials:
                Text("尚未配对 Mac。请确认 Mac 端已在『设置 → 手机伴侣 → 启用同网配对』。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("搜索附近的 Mac") { client.startBrowsing() }
                    .accessibilityIdentifier("companion-start-browsing")
            case .paired(let credentials):
                VStack(alignment: .leading, spacing: 2) {
                    Text("已与 Mac 配对")
                        .font(.body.bold())
                    Text("设备名：\(credentials.deviceName)")
                    Text("deviceID：\(credentials.deviceID.uuidString.prefix(8))…")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Button("搜索并刷新工具目录") { client.startBrowsing() }
            case .idle:
                ProgressView()
            case .browsing:
                HStack {
                    ProgressView()
                    Text(client.hasTailnetEndpoint
                        ? "正在搜索同一 Wi-Fi 下的 Mac…（若无结果，约 6 秒后自动改走异地通道）"
                        : "正在搜索同一 Wi-Fi 下的 Mac…")
                        .foregroundStyle(.secondary)
                }
            case .connecting(let mac):
                HStack {
                    ProgressView()
                    Text(mac.serviceName == CompanionPairingClient.tailnetServiceName
                        ? "正在通过异地通道连接…"
                        : "正在连接 \(mac.serviceName)…")
                }
            case .verifyFingerprint(let mac, let fingerprint, let isResume):
                Text("已发现 \(mac.serviceName)")
                    .font(.body.bold())
                if isResume {
                    Text("信任锚点不一致——可能同网内有另一台 Mac。请核对下方指纹是否与你在 Mac 屏幕看到的一致。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("第 1 步：核对指纹")
                        .font(.caption.bold())
                    Text("手机下面的指纹必须与 Mac『设置 → 手机伴侣』屏幕上的完全一致：")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(fingerprint)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .accessibilityIdentifier("companion-mac-fingerprint")
                if !isResume {
                    TextField("设备名（如：我的 iPhone）", text: $client.deviceName)
                        .accessibilityIdentifier("companion-device-name")
                    TextField("第 2 步：输入 Mac 屏上的 6 位配对码", text: $client.pairingCodeInput)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("companion-pairing-code-input")
                    Button("指纹一致，开始配对") { client.confirmFingerprintAndPair() }
                        .accessibilityIdentifier("companion-confirm-pairing")
                }
                Button("取消", role: .destructive) { client.stopBrowsing() }
            case .awaitingAck(let isResume):
                HStack {
                    ProgressView()
                    Text(isResume ? "正在复用配对…" : "正在完成配对…")
                }
            case .listingTools(let mac):
                HStack {
                    ProgressView()
                    Text("正在获取 \(mac.serviceName) 的工具目录…")
                }
            case .toolSummaries:
                EmptyView()
            case .requestingLaunch(let name):
                HStack {
                    ProgressView()
                    Text("已发送「\(name)」启动请求，请在 Mac 上确认…")
                }
                Button("取消", role: .destructive) { client.stopBrowsing() }
            case .launchResult(let accepted, let message):
                if accepted {
                    Label("Mac 已确认启动", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.body.bold())
                    Text("命令已交给 Mac 上你选择的终端执行。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label("启动未执行", systemImage: "xmark.circle")
                        .foregroundStyle(.orange)
                        .font(.body.bold())
                    if let message {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button("返回工具目录") { client.startBrowsing() }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Button("重新搜索") { client.startBrowsing() }
            }
        } header: {
            Text("与 Mac 配对")
        } footer: {
            Text("仅在本地 Wi-Fi 内通讯。配对码只出现在 Mac 屏幕上；任何要求你离开本页输入配对码的提示都是攻击。")
                .font(.caption2)
        }
    }

    @ViewBuilder
    private func toolsSection(summaries: [MobileToolSummary]) -> some View {
        Section {
            if summaries.isEmpty {
                Text("Mac 上没有勾选『在手机入口显示』的工具。在 Mac 端编辑任一工具 → 手机入口 → 打开开关。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(summaries, id: \.id) { summary in
                    Button {
                        client.requestLaunch(summary)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(summary.displayName).font(.body.bold())
                                Spacer()
                                Image(systemName: "play.circle")
                                    .foregroundStyle(.blue)
                            }
                            if !summary.displayDescription.isEmpty {
                                Text(summary.displayDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("companion-launch-\(summary.id.uuidString)")
                }
            }
        } header: {
            Text("Mac 工具目录（仅名称与说明）")
        } footer: {
            Text("手机端只收到 4 字段（id / 显示名 / 说明 / 图标符号）。命令、路径、变量值不会离开 Mac。")
                .font(.caption2)
        }
    }
}

#Preview {
    ContentView().environmentObject(CompanionPairingClient())
}
