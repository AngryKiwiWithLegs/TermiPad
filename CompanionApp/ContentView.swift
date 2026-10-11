import SwiftUI
import UIKit

/// M5 haptic feedback wrapper (HIG: light impact for key actions, success notification).
enum Haptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

struct ContentView: View {
    @EnvironmentObject private var client: CompanionPairingClient
    // Selection state for the M2b-3 new-task form (local UI state, not part of the model).
    @State private var selectedScopeID: UUID?
    @State private var selectedTaskKind: String?
    /// Bottom feature tabs (2026-09-10 user feedback: no back button after searching, and the features were mutually exclusive,
    /// switchable only by restarting the app) — changed to explicit tab navigation that can switch in any state.
    enum Tab: String, CaseIterable, Identifiable {
        case tools
        case console
        case newTask
        var id: String { rawValue }
        var title: String {
            switch self {
            case .tools: return "Tool Catalog"
            case .console: return "Task Sessions"
            case .newTask: return "Submit New Task"
            }
        }
        var symbol: String {
            switch self {
            case .tools: return "square.grid.2x2"
            case .console: return "list.bullet.rectangle"
            case .newTask: return "plus.square.on.square"
            }
        }
    }
    @State private var selectedTab: Tab = .tools

    var body: some View {
        // M5: bottom TabView (the HIG-preferred navigation) — each tab has its own NavigationStack,
        // and large-title collapsing uses the system behavior.
        TabView(selection: $selectedTab) {
            NavigationStack {
                Form {
                    pairingStatusHeader
                    toolsTab
                }
                .navigationTitle("TermiPad Companion")
            }
            .tabItem { Label(Tab.tools.title, systemImage: Tab.tools.symbol) }
            .tag(Tab.tools)

            NavigationStack {
                Form {
                    pairingStatusHeader
                    consoleTab
                }
                .navigationTitle(Tab.console.title)
            }
            .tabItem { Label(Tab.console.title, systemImage: Tab.console.symbol) }
            .tag(Tab.console)

            NavigationStack {
                Form {
                    pairingStatusHeader
                    newTaskTab
                }
                .navigationTitle(Tab.newTask.title)
            }
            .tabItem { Label(Tab.newTask.title, systemImage: Tab.newTask.symbol) }
            .tag(Tab.newTask)
        }
        .sheet(item: $selectedStreamEntry) { entry in
            TaskStreamDetailView(entry: entry)
                .environmentObject(client)
        }
    }

    /// Pairing status bar: guidance when unpaired; collapses to one line when paired (device name + unpair
    /// tucked into a menu to avoid accidental taps).
    @ViewBuilder
    private var pairingStatusHeader: some View {
        switch client.phase {
        case .noCredentials:
            VStack(spacing: 6) {
                Text("No Mac is paired yet. Make sure “Settings → Mobile Companion → Enable Local Network Pairing” is turned on on the Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Search for Nearby Macs") { client.startBrowsing() }
                    .accessibilityIdentifier("companion-start-browsing")
            }
            .padding(.vertical, 10)
        case .browsing, .connecting, .verifyFingerprint, .awaitingAck, .listingTools, .requestingLaunch:
            // Hide the connection progress bar once catalog/session data is ready (2026-09-10 user test:
            // the top "fetching" spinner kept turning while the submit form was already usable, suggesting it had not finished loading).
            // The progress bar only makes sense during a real handshake / first catalog fetch with no data yet.
            let hasData = !client.consoleEntries.isEmpty
                || (!client.consoleScopes.isEmpty && !client.consoleFixedTasks.isEmpty)
                || (selectedTab == .tools && client.hasToolSummaries)
            if hasData && selectedTab != .tools {
                EmptyView()
            } else {
                pairingSection
            }
        case .failed(let message):
            VStack(spacing: 6) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.caption)
                Button("Search Again") { client.startBrowsing() }
            }
            .padding(.vertical, 10)
        default:
            EmptyView()
        }
    }

    // MARK: - Tool catalog page

    @ViewBuilder
    private var toolsTab: some View {
        Section {
            switch client.phase {
            case .paired(let credentials):
                VStack(alignment: .leading, spacing: 2) {
                    Text("Paired with Mac").font(.body.bold())
                    Text("Device name: \(credentials.deviceName)").font(.caption)
                    Text("deviceID: \(credentials.deviceID.uuidString.prefix(8))…")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                Button("Refresh Tool Catalog") { client.resumeAndFetchTools() }
                    .accessibilityIdentifier("companion-resume-fetch")
            case .toolSummaries(let summaries):
                toolEntries(summaries: summaries)
            case .launchResult(let accepted, let message):
                if accepted {
                    Label("Mac confirmed the launch", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.body.bold())
                    Text("The command was handed to the terminal you chose on the Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Launch not performed", systemImage: "xmark.circle")
                        .foregroundStyle(.orange)
                        .font(.body.bold())
                    if let message {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button("Back to Tool Catalog") { client.resumeAndFetchTools() }
            case .idle:
                ProgressView()
            default:
                EmptyView()
            }
        } footer: {
            Text("The phone receives only 4 fields (id / display name / description / icon symbol). Commands, paths, and variable values never leave the Mac.")
                .font(.caption2)
        }
    }

    @ViewBuilder
    private func toolEntries(summaries: [MobileToolSummary]) -> some View {
        if summaries.isEmpty {
            Text("No tool on the Mac has “Show in Mobile Entry” turned on. On the Mac, edit any tool → Mobile Entry → turn the switch on.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(summaries, id: \.id) { summary in
                Button {
                    Haptics.light()
                    client.requestLaunch(summary)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(summary.displayName).font(.body.bold())
                            Spacer()
                            Image(systemName: "play.circle")
                                .foregroundStyle(.tint)
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
    }

    // MARK: - Task sessions page

    @ViewBuilder
    private var consoleTab: some View {
        if case .paired = client.phase {
            Section {
                Button("Refresh Task Status") { client.openTaskConsole() }
                    .accessibilityIdentifier("companion-open-console")
            }
        }
        if client.consoleEntries.isEmpty {
            Section {
                Text("No task records yet. After you launch a tool or submit a new task, its run status on the Mac appears here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            consoleSection
        }
    }

    // MARK: - New task page

    @ViewBuilder
    private var newTaskTab: some View {
        if let result = client.lastTaskProposalResult {
            Section {
                if result.status == .accepted {
                    Label("Task submitted. See the Task Sessions page for its run status", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label(result.reason ?? "Task rejected", systemImage: "xmark.circle")
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Most recent submission")
            }
        }
        if client.isFetchingCatalog {
            Section {
                HStack {
                    ProgressView()
                    Text("Fetching project scopes and the fixed task catalog from the Mac…")
                        .foregroundStyle(.secondary)
                }
            }
        } else if !client.consoleScopes.isEmpty && !client.consoleFixedTasks.isEmpty {
            newTaskSection
        } else if !client.consoleFixedTasks.isEmpty && client.consoleScopes.isEmpty {
            // The catalog was fetched but the Mac has no project scopes — say clearly what is missing instead of
            // silently rendering an empty form that cannot be submitted (2026-09-10 user test: "nothing happens").
            Section {
                Label("No project scopes are registered on the Mac yet", systemImage: "folder.badge.questionmark")
                    .foregroundStyle(.orange)
                Text("On the Mac, open TermiPad → Task Workbench → register a project directory first (choose your project folder), then open a review window, and come back here and tap “Fetch Task Catalog”.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Fetch Again") { client.openNewTaskForm() }
            } header: {
                Text("Project scope missing")
            }
        } else {
            Section {
                Button("Fetch Task Catalog") { client.openNewTaskForm() }
                    .accessibilityIdentifier("companion-open-newtask")
                Text("Before submitting, project scopes and the fixed task catalog must be fetched from the Mac (the Mac must be reachable over the tunnel or LAN).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// M2b-1 session entry feed (docs/m2b-remote-task-console-design.md §6):
    /// a unified timeline of tool launches and fixed tasks. Rendered from memory only — output snippets are never written to disk.
    @ViewBuilder
    private var consoleSection: some View {
        Section {
            ForEach(client.consoleEntries, id: \.id) { entry in
                Button {
                    // M4: tapping a fixed-task entry opens the interactive session detail (streamed output).
                    if entry.kind == .fixedTask {
                        selectedStreamEntry = entry
                    }
                } label: {
                    consoleEntryRow(entry)
                }
                .buttonStyle(.plain)
                .disabled(entry.kind != .fixedTask)
                .accessibilityIdentifier("companion-console-entry-tap-\(entry.id.uuidString)")
            }
        } header: {
            Text("Task Sessions (live Mac status)")
        } footer: {
            Text("Shows the run status of tool launches and fixed tasks on the Mac. Commands and full output are never sent to the phone.")
                .font(.caption2)
        }
    }

    @State private var selectedStreamEntry: MobileSessionEntry?

    /// Rendering of a single session entry (extracted from the ForEach — the detail page reuses the status styling).
    @ViewBuilder
    private func consoleEntryRow(_ entry: MobileSessionEntry) -> some View {
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
                                .accessibilityLabel(exitCode == 0 ? "Exit code 0, succeeded" : "Exit code \(exitCode), failed")
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
                        // M2c: only running entries visible to the phone offer Stop (fixed tasks can be stopped;
                        // tool launches are terminal handoffs — the terminal owns stopping, so no button is shown).
                        if entry.executionState == "running" && entry.kind == .fixedTask {
                            Button {
                                Haptics.warning()
                                client.cancelTask(taskIntentID: entry.id, title: entry.title)
                            } label: {
                                Label("Stop", systemImage: "stop.circle.fill")
                                    .font(.caption.bold())
                            }
                            .buttonStyle(.borderless)
                            .tint(.red)
                            .accessibilityIdentifier("companion-console-stop-\(entry.id.uuidString)")
                        }
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

    // MARK: - Session status rendering (T1 TaskExecutionState raw strings + the two tool-launch states)

    /// M2b-3 new-task form (docs/m2b-remote-task-console-design.md §6):
    /// pick a scope → pick a fixed task → submit. The payload is only kind + a scopeID reference.
    /// The submit button is **pinned to the top of the form** (2026-09-10 user test: the button sat below the list of 5 tasks,
    /// was pushed off-screen, and the user thought there was no way to submit).
    @ViewBuilder
    private var newTaskSection: some View {
        Section {
            Button {
                if let scopeID = selectedScopeID, let kind = selectedTaskKind,
                   let task = client.consoleFixedTasks.first(where: { $0.kind == kind }) {
                    Haptics.light()
                    client.submitTaskProposal(kind: kind, scopeID: scopeID, title: task.purpose)
                }
            } label: {
                HStack {
                    Image(systemName: "paperplane.fill")
                    Text(selectedTaskKind == nil
                        ? "Submit Task (choose below first)"
                        : "Submit “\(client.consoleFixedTasks.first(where: { $0.kind == selectedTaskKind })?.purpose ?? "")”")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedScopeID == nil || selectedTaskKind == nil)
            .accessibilityIdentifier("companion-newtask-submit")
            // The scope defaults to the first item: a Picker with selection=nil renders as an empty selection,
            // and the user does not know they have to tap it (root cause of the always-grey button in the 2026-09-10 test).
            // Preselect automatically when data arrives; the user can still change it.
            .onReceive(client.$consoleScopes) { scopes in
                if selectedScopeID == nil, let first = scopes.first {
                    selectedScopeID = first.id
                }
            }
            Picker("Project Scope", selection: $selectedScopeID) {
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
                            if let required = task.requiredRelativePaths, !required.isEmpty {
                                // M2c: the task's fixed requirements for the project directory (directory literals)
                                // — the user can match "scope × task" instead of choosing blind.
                                Text("The project directory must contain: \(required.joined(separator: ", "))")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        Image(systemName: selectedTaskKind == task.kind
                            ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedTaskKind == task.kind ? .green : .secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("companion-newtask-kind-\(task.kind)")
                // HIG: add a trailing chevron to selectable rows (hints that they are tappable) — shown only when not selected.
            }
            Button("Submit Task") {
                if let scopeID = selectedScopeID, let kind = selectedTaskKind,
                   let task = client.consoleFixedTasks.first(where: { $0.kind == kind }) {
                    client.submitTaskProposal(kind: kind, scopeID: scopeID, title: task.purpose)
                }
            }
            .disabled(selectedScopeID == nil || selectedTaskKind == nil)
            .accessibilityIdentifier("companion-newtask-submit")
        } header: {
            Text("Submit New Task (runs inside the Mac review window)")
        } footer: {
            Text("Only tasks from the fixed task catalog can be submitted. They run only after the Mac's local policy check (scope / risk / review window) passes, and may need confirmation on the Mac. Commands and arguments are never sent to the phone.")
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

    static func stateColor(for state: String) -> Color {
        switch state {
        case "running": return .blue
        case "succeeded", "launched": return .green
        case "failed", "launchFailed", "timedOut": return .red
        case "stopped": return .orange
        default: return .secondary
        }
    }

    static func stateText(for state: String) -> String {
        switch state {
        case "running": return "Running"
        case "succeeded": return "Succeeded"
        case "failed": return "Failed"
        case "timedOut": return "Timed Out"
        case "stopped": return "Stopped"
        case "launched": return "Launched (terminal handoff)"
        case "launchFailed": return "Launch Failed"
        case "startRejected": return "Rejected by Policy"
        case "startFailed": return "Start Error"
        default: return state
        }
    }

    @ViewBuilder
    private var pairingSection: some View {
        Section {
            switch client.phase {
            case .noCredentials:
                Text("No Mac is paired yet. Make sure “Settings → Mobile Companion → Enable Local Network Pairing” is turned on on the Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Search for Nearby Macs") { client.startBrowsing() }
                    .accessibilityIdentifier("companion-start-browsing")
            case .paired(let credentials):
                VStack(alignment: .leading, spacing: 2) {
                    Text("Paired with Mac")
                        .font(.body.bold())
                    Text("Device name: \(credentials.deviceName)")
                    Text("deviceID: \(credentials.deviceID.uuidString.prefix(8))…")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Button("Search and Refresh Tool Catalog") { client.startBrowsing() }
            case .idle:
                ProgressView()
            case .browsing:
                HStack {
                    ProgressView()
                    Text(client.hasTailnetEndpoint
                        ? "Searching for a Mac on the same Wi-Fi… (if nothing is found, it switches to the remote channel automatically after about 6 seconds)"
                        : "Searching for a Mac on the same Wi-Fi…")
                        .foregroundStyle(.secondary)
                }
            case .connecting(let mac):
                HStack {
                    ProgressView()
                    Text(mac.serviceName == CompanionPairingClient.tailnetServiceName
                        ? "Connecting over the remote channel…"
                        : "Connecting to \(mac.serviceName)…")
                }
            case .verifyFingerprint(let mac, let fingerprint, let isResume):
                Text("Found \(mac.serviceName)")
                    .font(.body.bold())
                if isResume {
                    Text("Trust anchor mismatch — there may be another Mac on the same network. Check that the fingerprint below matches the one shown on your Mac's screen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Step 1: Verify the fingerprint")
                        .font(.caption.bold())
                    Text("The fingerprint below on the phone must exactly match the one on the Mac's “Settings → Mobile Companion” screen:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(fingerprint)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .accessibilityIdentifier("companion-mac-fingerprint")
                if !isResume {
                    TextField("Device name (e.g. My iPhone)", text: $client.deviceName)
                        .accessibilityIdentifier("companion-device-name")
                    TextField("Step 2: Enter the 6-digit pairing code shown on the Mac", text: $client.pairingCodeInput)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("companion-pairing-code-input")
                    Button("Fingerprints Match, Start Pairing") { client.confirmFingerprintAndPair() }
                        .accessibilityIdentifier("companion-confirm-pairing")
                }
                Button("Cancel", role: .destructive) { client.stopBrowsing() }
            case .awaitingAck(let isResume):
                HStack {
                    ProgressView()
                    Text(isResume ? "Resuming pairing…" : "Completing pairing…")
                }
            case .listingTools(let mac):
                HStack {
                    ProgressView()
                    Text("Fetching the tool catalog from \(mac.serviceName)…")
                }
            case .toolSummaries:
                EmptyView()
            case .requestingLaunch(let name):
                HStack {
                    ProgressView()
                    Text("Launch request for “\(name)” sent. Please confirm on the Mac…")
                }
                Button("Cancel", role: .destructive) { client.stopBrowsing() }
            case .launchResult(let accepted, let message):
                if accepted {
                    Label("Mac confirmed the launch", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.body.bold())
                    Text("The command was handed to the terminal you chose on the Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Launch not performed", systemImage: "xmark.circle")
                        .foregroundStyle(.orange)
                        .font(.body.bold())
                    if let message {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button("Back to Tool Catalog") { client.startBrowsing() }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Button("Search Again") { client.startBrowsing() }
            }
        } header: {
            Text("Pair with Mac")
        } footer: {
            Text("Communicates only over local Wi-Fi. The pairing code appears only on the Mac's screen; any prompt asking you to leave this page to enter the pairing code is an attack.")
                .font(.caption2)
        }
    }
}

#Preview {
    ContentView().environmentObject(CompanionPairingClient())
}


/// M4 interactive session detail page (docs/m4-interactive-session-design.md §3):
/// native large-type streamed output + auto-scroll/pause + stop. HIG alignment: system fonts and semantic colors,
/// NavigationStack, toolbar icon buttons, follows Dynamic Type.
struct TaskStreamDetailView: View {
    let entry: MobileSessionEntry
    @EnvironmentObject private var client: CompanionPairingClient
    @Environment(\.dismiss) private var dismiss
    @State private var isPaused = false
    @State private var showReconnectHint = false

    var body: some View {
        NavigationStack {
            Group {
                if client.isStreaming || !client.streamText.isEmpty {
                    streamContent
                } else {
                    unavailableContent
                }
            }
            .navigationTitle(entry.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        client.closeStream()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !client.streamText.isEmpty {
                        Button {
                            isPaused.toggle()
                        } label: {
                            Image(systemName: isPaused ? "play.circle" : "pause.circle")
                        }
                        .accessibilityIdentifier("companion-stream-pause")
                    }
                }
            }
            .onAppear {
                client.openStream(taskID: entry.id)
            }
        }
    }

    /// Output stream body: ScrollView + large monospaced type + auto-follow at the bottom (holds still while paused).
    private var streamContent: some View {
        VStack(spacing: 0) {
            // M4-3 interaction choice card: pinned to the top when the task needs a decision (native HIG card).
            if let interaction = client.pendingInteraction {
                VStack(alignment: .leading, spacing: 10) {
                    Label(interaction.prompt, systemImage: "questionmark.circle")
                        .font(.subheadline.bold())
                    ForEach(interaction.options, id: \.self) { option in
                        Button {
                            client.submitInteractionSelection(option)
                        } label: {
                            Text(option)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("companion-interaction-\(option)")
                    }
                }
                .padding()
                .background(.bar)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .padding(.top, 8)
            }
            // Status bar (native semantic colors).
            HStack(spacing: 6) {
                Circle()
                    .fill(ContentView.stateColor(for: client.streamState ?? "running"))
                    .frame(width: 8, height: 8)
                Text(client.streamState.map(ContentView.stateText) ?? "Live output")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                if isPaused {
                    Label("Paused", systemImage: "pause.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    Text(client.streamText.isEmpty ? "Waiting for output…" : client.streamText)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                    Color.clear.frame(height: 1).id("stream-bottom")
                }
                .onChange(of: client.streamText) { _ in
                    guard !isPaused else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("stream-bottom", anchor: .bottom)
                    }
                }
            }
        }
    }

    /// Empty state when subscribing is not possible (window not open / task not streamable) — native empty-state card.
    private var unavailableContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Session stream unavailable")
                .font(.headline)
            Text("Today's remote window is not open, or this task does not support streamed output. Open “Today's Remote Window” on the Mac and try again.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Retry") {
                client.openStream(taskID: entry.id)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
