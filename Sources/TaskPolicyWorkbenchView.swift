import AppKit
import SwiftData
import SwiftUI

/// T2 设计提示：原生 macOS 工作台仅执行已批准固定任务；可默认关闭地许可同机 MCP 提出待审阅任务，但不显示交互式终端，也不传输命令或输出。
@MainActor
struct TaskPolicyWorkbenchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \TaskProjectScope.createdAt) private var scopes: [TaskProjectScope]
    @Query(sort: \TaskReviewWindow.openedAt, order: .reverse) private var windows: [TaskReviewWindow]
    @Query(sort: \TaskIntent.proposedAt, order: .reverse) private var intents: [TaskIntent]

    let language: AppLanguage
    @StateObject private var taskExecutor = TaskExecutionCoordinator.shared
    @AppStorage(TaskMCPSettings.localMCPEnabledKey) private var localMCPEnabled = false
    @State private var selectedScopeID: UUID?
    @State private var selectedTaskKind: TaskKind = .swiftPackageTests
    @State private var notice: String?
    @State private var persistenceStatus = ""

    private var selectedScope: TaskProjectScope? {
        scopes.first { $0.id == selectedScopeID }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                policyHeader
                localMCPSection
                scopeSection
                proposalSection
                intentsSection
            }
            .padding(20)
        }
        .background(SoftMacTheme(colorScheme: colorScheme).contentSurface)
        .navigationTitle(copy("taskWorkbench", english: "Task Workbench"))
        .onAppear {
            selectedScopeID = selectedScopeID ?? scopes.first?.id
            persistenceStatus = copy("本地设置会自动保存到这台 Mac。", english: "Local settings save automatically on this Mac.")
        }
        .alert(copy("taskPolicyNotice", english: "Task Policy"), isPresented: Binding(
            get: { notice != nil },
            set: { if !$0 { notice = nil } }
        )) {
            Button(copy("ok", english: "OK"), role: .cancel) { notice = nil }
        } message: {
            Text(notice ?? "")
        }
    }

    private var policyHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(copy("localPolicyOnly", english: "Local policy only"), systemImage: "checkmark.shield")
                .font(.headline)
            Text(copy(
                "T1 只执行已按本地策略批准的固定任务。它不显示交互式终端、不接受远程输入、不保存输出，也不连接网络服务。",
                english: "T1 only executes fixed tasks approved by local policy. It does not show an interactive terminal, accept remote input, retain output, or connect to a network service."
            ))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            Text(persistenceStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("task-policy-auto-save-status")
        }
        .padding(16)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(copy(\"仅本地策略\", english: \"Local policy only\"))。\(persistenceStatus)")
        .accessibilityIdentifier("task-policy-boundary")
    }

    private var localMCPSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(copy("允许本机 MCP 提出任务", english: "Allow Local MCP Task Proposals"), isOn: $localMCPEnabled)
                    .accessibilityIdentifier("task-mcp-toggle")
                Text(localMCPStatus)
                    .font(.caption)
                    .foregroundStyle(localMCPEnabled ? Color.green : Color.secondary)
                    .accessibilityIdentifier("task-mcp-persistence-status")
            }
            Text(copy(
                "默认关闭。开启后，只有同一台 Mac 上以 --termipad-mcp-stdio 启动的本机客户端可查询固定任务、提出待本机审阅的任务、读取最小状态或取消任务。它不能批准、执行、读取路径或终端输出。",
                english: "Off by default. When enabled, only a client launched on this Mac with --termipad-mcp-stdio can list fixed tasks, propose tasks for local review, read minimum state, or cancel tasks. It cannot approve, execute, read paths, or read terminal output."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onChange(of: localMCPEnabled) { _, enabled in
            persistenceStatus = enabled
                ? copy("已自动保存：本机 MCP 已开启。", english: "Saved automatically: Local MCP is enabled.")
                : copy("已自动保存：本机 MCP 已关闭。", english: "Saved automatically: Local MCP is disabled.")
        }
        .accessibilityIdentifier("task-mcp-local-section")
    }

    private var scopeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(copy("项目范围", english: "Project Scopes"))
                    .font(.headline)
                Spacer()
                Button(copy("选择项目文件夹", english: "Choose Project Folder"), action: chooseProjectFolder)
            }
            if scopes.isEmpty {
                ContentUnavailableView(
                    copy("尚未选择项目范围", english: "No Project Scope Selected"),
                    systemImage: "folder.badge.questionmark",
                    description: Text(copy("先在这台 Mac 上选择一个项目文件夹。路径只保存在本地，不进入备份或诊断。", english: "Choose a project folder on this Mac first. Its path stays local and never enters backup or diagnostics."))
                )
            } else {
                ForEach(scopes) { scope in
                    HStack(spacing: 12) {
                        Image(systemName: scope.isRevoked ? "folder.badge.minus" : (scope.directoryIsAvailable ? "folder" : "folder.badge.questionmark"))
                            .foregroundStyle(scope.isRevoked ? Color.secondary : (scope.directoryIsAvailable ? Color.accentColor : Color.orange))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(scope.displayName)
                            Text(scopeStatus(scope))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if scope.isRevoked {
                            Text(copy("已撤销", english: "Revoked"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button(copy("撤销范围", english: "Revoke Scope")) { revoke(scope) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                    .padding(12)
                    .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    private var proposalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(copy("固定任务提案", english: "Fixed Task Proposal"))
                .font(.headline)
            Picker(copy("项目范围", english: "Project Scope"), selection: $selectedScopeID) {
                Text(copy("请选择", english: "Choose a scope")).tag(UUID?.none)
                ForEach(scopes.filter { !$0.isRevoked && $0.directoryIsAvailable }) { scope in
                    Text(scope.displayName).tag(Optional(scope.id))
                }
            }
            Picker(copy("任务类型", english: "Task Type"), selection: $selectedTaskKind) {
                ForEach(FixedTaskCatalog.definitions) { definition in
                    Text(definition.purpose(language: language)).tag(definition.kind)
                }
            }
            if let definition = FixedTaskCatalog.definition(for: selectedTaskKind) {
                HStack(spacing: 8) {
                    Text(definition.commandPreview)
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Text(definition.risk == .low ? copy("低风险", english: "Low risk") : copy("标准审阅", english: "Standard review"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            HStack {
                Button(copy("打开 15 分钟本地审阅窗口", english: "Open 15-Minute Local Review Window"), action: openReviewWindow)
                    .disabled(selectedScope == nil)
                Button(copy("创建任务提案", english: "Create Task Proposal"), action: proposeTask)
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedScope == nil)
            }
            Text(copy("审阅窗口只在这台 Mac 上生效；只有批准后的固定任务可由 T1 执行。", english: "A review window is local to this Mac; only approved fixed tasks can be executed by T1."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var intentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(copy("任务提案", english: "Task Proposals"))
                .font(.headline)
            if intents.isEmpty {
                ContentUnavailableView(
                    copy("尚无任务提案", english: "No Task Proposals"),
                    systemImage: "checklist.unchecked",
                    description: Text(copy("在上方创建一条固定、可审阅的本地任务提案。", english: "Create a fixed, reviewable local task proposal above."))
                )
            } else {
                ForEach(intents) { intent in
                    taskCard(intent)
                }
            }
        }
    }

    private func taskCard(_ intent: TaskIntent) -> some View {
        let scope = scopes.first { $0.id == intent.projectScopeID }
        let definition = intent.kind.flatMap(FixedTaskCatalog.definition)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(definition?.purpose(language: language) ?? copy("未知任务", english: "Unknown Task"))
                    .font(.headline)
                Spacer()
                Text(stateLabel(intent.state))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let definition {
                Text(definition.commandPreview)
                    .font(.system(.caption, design: .monospaced))
            }
            Text(scope?.displayName ?? copy("项目范围不可用", english: "Project scope unavailable"))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let reason = intent.rejectionReason {
                Text(reasonLabel(reason))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                if intent.state == .pendingReview {
                    Button(copy("按本地策略批准", english: "Approve by Local Policy")) { approve(intent) }
                    Button(copy("取消", english: "Cancel"), role: .cancel) { cancel(intent) }
                }
                if intent.state == .approved { executionControls(intent, scope: scope) }
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityIdentifier("task-intent-\(intent.id.uuidString)")
    }

    @ViewBuilder
    private func executionControls(_ intent: TaskIntent, scope: TaskProjectScope?) -> some View {
        switch intent.executionState {
        case .notStarted:
            Button(copy("开始本地任务", english: "Start Local Task")) { start(intent, scope: scope) }
                .buttonStyle(.borderedProminent)
        case .running:
            HStack {
                ProgressView().controlSize(.small)
                Text(copy("正在本机运行；不会显示或保存终端输出。", english: "Running locally; terminal output is neither shown nor retained."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(copy("停止", english: "Stop"), role: .destructive) { stop(intent) }
                    .buttonStyle(.bordered)
            }
        default:
            Text(executionSummary(intent))
                .font(.caption)
                .foregroundStyle(intent.executionState == .succeeded ? Color.secondary : Color.orange)
        }
    }

    private func chooseProjectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = copy("选择项目范围", english: "Choose Project Scope")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = (url.path as NSString).standardizingPath
        guard !scopes.contains(where: { $0.rootPath == path }) else {
            notice = copy("该项目范围已存在。", english: "That project scope already exists.")
            return
        }
        let scope = TaskProjectScope(displayName: url.lastPathComponent, rootPath: path)
        modelContext.insert(scope)
        selectedScopeID = scope.id
        save()
    }

    private func openReviewWindow() {
        guard let scope = selectedScope else { return }
        let now = Date()
        modelContext.insert(TaskReviewWindow(
            projectScopeID: scope.id,
            openedAt: now,
            expiresAt: now.addingTimeInterval(TaskIntentPolicy.localReviewWindowLifetime)
        ))
        DiagnosticsStore.shared.record(.taskReviewWindowOpened)
        save()
    }

    private func proposeTask() {
        guard let scope = selectedScope else { return }
        guard !scope.isRevoked, scope.directoryIsAvailable else {
            notice = copy("所选项目范围不可用或已撤销。", english: "The selected project scope is unavailable or revoked.")
            return
        }
        let intent = TaskIntentPolicy.makeIntent(scope: scope, kind: selectedTaskKind)
        modelContext.insert(intent)
        DiagnosticsStore.shared.record(.taskProposalCreated)
        save()
    }

    private func approve(_ intent: TaskIntent) {
        let scope = scopes.first { $0.id == intent.projectScopeID }
        let decision = TaskIntentPolicy.approve(intent, scope: scope, windows: windows, existingIntents: intents)
        switch decision {
        case .allowed:
            DiagnosticsStore.shared.record(.taskPolicyApproved)
        case .rejected:
            DiagnosticsStore.shared.record(.taskPolicyRejected)
        }
        save()
    }

    private func cancel(_ intent: TaskIntent) {
        taskExecutor.stop(intent: intent)
        TaskIntentPolicy.cancel(intent)
        DiagnosticsStore.shared.record(.taskCancelled)
        save()
    }

    private func start(_ intent: TaskIntent, scope: TaskProjectScope?) {
        let decision = taskExecutor.start(intent: intent, scope: scope) { save() }
        if case .rejected = decision { notice = executionSummary(intent) }
        save()
    }

    private func stop(_ intent: TaskIntent) {
        taskExecutor.stop(intent: intent)
        save()
    }

    private func revoke(_ scope: TaskProjectScope) {
        for intent in intents where intent.projectScopeID == scope.id { taskExecutor.stop(intent: intent) }
        TaskIntentPolicy.revoke(scope: scope, intents: intents)
        for window in windows where window.projectScopeID == scope.id {
            TaskIntentPolicy.revoke(window: window)
        }
        DiagnosticsStore.shared.record(.taskScopeRevoked)
        if selectedScopeID == scope.id { selectedScopeID = nil }
        save()
    }

    private func save() {
        do {
            try modelContext.save()
            persistenceStatus = copy("已自动保存到这台 Mac。", english: "Saved automatically on this Mac.")
        } catch {
            notice = copy("无法保存本地任务策略。", english: "The local task policy could not be saved.")
        }
    }

    private var localMCPStatus: String {
        localMCPEnabled
            ? copy("已自动保存并已开启：只允许本机受限 MCP 提出待审阅任务。", english: "Saved automatically and enabled: only the restricted local MCP may propose tasks for review.")
            : copy("已自动保存：本机 MCP 当前关闭。", english: "Saved automatically: Local MCP is currently disabled.")
    }

    private func scopeStatus(_ scope: TaskProjectScope) -> String {
        if scope.isRevoked { return copy("已撤销", english: "Revoked") }
        return scope.directoryIsAvailable ? copy("仅本地，可用于固定任务审阅", english: "Local only; available for fixed task review") : copy("项目文件夹当前不可用", english: "Project folder is currently unavailable")
    }

    private func stateLabel(_ state: TaskIntentState) -> String {
        switch (state, language) {
        case (.pendingReview, .simplifiedChinese): return "等待本地审阅"
        case (.approved, .simplifiedChinese): return "已按策略批准"
        case (.rejected, .simplifiedChinese): return "已拒绝"
        case (.expired, .simplifiedChinese): return "已过期"
        case (.revoked, .simplifiedChinese): return "已撤销"
        case (.cancelled, .simplifiedChinese): return "已取消"
        case (.pendingReview, .english): return "Pending Local Review"
        case (.approved, .english): return "Policy Approved"
        case (.rejected, .english): return "Rejected"
        case (.expired, .english): return "Expired"
        case (.revoked, .english): return "Revoked"
        case (.cancelled, .english): return "Cancelled"
        }
    }

    private func executionSummary(_ intent: TaskIntent) -> String {
        switch (intent.executionState, language) {
        case (.notStarted, .simplifiedChinese): return "尚未开始。"
        case (.running, .simplifiedChinese): return "正在本机运行。"
        case (.succeeded, .simplifiedChinese): return "已完成（退出码 0）。"
        case (.failed, .simplifiedChinese): return "未完成（非零退出码）。"
        case (.timedOut, .simplifiedChinese): return "已达到时限并向直接任务进程发送停止请求。"
        case (.stopped, .simplifiedChinese): return "已向直接任务进程发送停止请求。"
        case (.startRejected, .simplifiedChinese): return "开始被本地执行策略拒绝。"
        case (.startFailed, .simplifiedChinese): return "本地任务进程无法启动。"
        case (.notStarted, .english): return "Not started."
        case (.running, .english): return "Running locally."
        case (.succeeded, .english): return "Completed (exit code 0)."
        case (.failed, .english): return "Did not complete (non-zero exit code)."
        case (.timedOut, .english): return "Timed out; a stop request was sent to the direct task process."
        case (.stopped, .english): return "A stop request was sent to the direct task process."
        case (.startRejected, .english): return "Start was rejected by local execution policy."
        case (.startFailed, .english): return "The local task process could not start."
        }
    }

    private func reasonLabel(_ reason: TaskRejectionReason) -> String {
        switch (reason, language) {
        case (.unknownTaskKind, .simplifiedChinese): return "任务不在本地固定目录中。"
        case (.projectScopeUnavailable, .simplifiedChinese): return "项目范围不可用或已撤销。"
        case (.localReviewRequired, .simplifiedChinese): return "需要在此 Mac 上打开审阅窗口。"
        case (.reviewWindowExpired, .simplifiedChinese): return "审阅窗口已过期或不允许该风险级别。"
        case (.riskNotPermitted, .simplifiedChinese): return "当前审阅窗口不允许该风险级别。"
        case (.nonceReplayed, .simplifiedChinese): return "一次性标识已被使用。"
        case (.taskExpired, .simplifiedChinese): return "任务提案已过期。"
        case (.taskNotPending, .simplifiedChinese): return "任务不再等待审阅。"
        case (.taskCancelled, .simplifiedChinese): return "任务已取消。"
        case (.unknownTaskKind, .english): return "The task is not in the local fixed catalog."
        case (.projectScopeUnavailable, .english): return "The project scope is unavailable or revoked."
        case (.localReviewRequired, .english): return "Open a review window on this Mac first."
        case (.reviewWindowExpired, .english): return "The review window expired or does not allow this risk level."
        case (.riskNotPermitted, .english): return "The current review window does not allow this risk level."
        case (.nonceReplayed, .english): return "The one-time identifier was already used."
        case (.taskExpired, .english): return "The task proposal expired."
        case (.taskNotPending, .english): return "The task is no longer pending review."
        case (.taskCancelled, .english): return "The task was cancelled."
        }
    }

    private func copy(_ chinese: String, english: String) -> String {
        language == .simplifiedChinese ? chinese : english
    }
}
