import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct PreferencesView: View {
    let embeddedInNavigation: Bool
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \TerminalTool.name) private var tools: [TerminalTool]
    @Query(sort: \CandidateTool.discoveredAt, order: .reverse) private var candidates: [CandidateTool]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @AppStorage("TermiPad.language") private var languageRawValue = AppLanguage.simplifiedChinese.rawValue
    @AppStorage("TermiPad.appearance") private var appearanceRawValue = AppAppearance.system.rawValue
    @AppStorage("TermiPad.terminalTarget") private var terminalTargetRawValue = TerminalTarget.systemTerminal.rawValue
    @AppStorage("TermiPad.autoEnrich") private var autoEnrich = false
    @AppStorage("TermiPad.showIgnoredCandidates") private var showIgnoredCandidates = false
    @AppStorage("TermiPad.discoveryPreviewEnabled") private var discoveryPreviewEnabled = false
    @AppStorage(AIService.baseURLDefaultsKey) private var aiBaseURL = "https://api.openai.com/v1"
    @AppStorage(AIService.modelDefaultsKey) private var aiModel = "gpt-4o-mini"
    @AppStorage("TermiPad.updateChecksEnabled") private var updateChecksEnabled = false
    @StateObject private var pairingService = MobilePairingService()
    @ObservedObject private var tunnelService = TailnetTunnelService.shared
    @ObservedObject private var launchPrompt = MobileLaunchPromptCenter.shared

    @State private var apiKeyInput = ""
    @State private var hasStoredAPIKey = false
    @State private var credentialMessage: String?
    @State private var includeSavedVariableValues = false
    @State private var backupDocument: BackupFileDocument?
    @State private var isExportingBackup = false
    @State private var isImportingBackup = false
    @State private var pendingImportedBackup: TermiPadBackup?
    @State private var backupMessage: String?
    @State private var diagnosticDocument: DiagnosticFileDocument?
    @State private var isExportingDiagnostics = false
    @State private var diagnosticMessage: String?
    @State private var isCheckingForUpdates = false
    @State private var updateAlert: String?
    @State private var updateMessage: String?

    init(embeddedInNavigation: Bool = false) {
        self.embeddedInNavigation = embeddedInNavigation
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRawValue) ?? .simplifiedChinese
    }

    private var appearance: Binding<AppAppearance> {
        Binding(
            get: { AppAppearance(rawValue: appearanceRawValue) ?? .system },
            set: { newValue in
                if reduceMotion {
                    appearanceRawValue = newValue.rawValue
                } else {
                    withAnimation(.easeInOut(duration: 0.30)) {
                        appearanceRawValue = newValue.rawValue
                    }
                }
            }
        )
    }

    private var terminalTarget: Binding<TerminalTarget> {
        Binding(
            get: { TerminalTarget(rawValue: terminalTargetRawValue) ?? .systemTerminal },
            set: { terminalTargetRawValue = $0.rawValue }
        )
    }

    private var theme: SoftMacTheme { SoftMacTheme(colorScheme: colorScheme) }

    var body: some View {
        Form {
            Section(AppCopy.text("settingsAppearance", language: language)) {
                Picker(AppCopy.text("settingsAppearance", language: language), selection: appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Label(option.displayName(language), systemImage: option.symbol).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section(AppCopy.text("settingsLanguage", language: language)) {
                Picker(AppCopy.text("settingsLanguage", language: language), selection: $languageRawValue) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(option.displayName).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                Text(language == .simplifiedChinese
                     ? "语言切换会立即应用到 TermiPad 的界面；工具名称、命令和 README 说明保持原样。"
                     : "The change applies immediately to TermiPad's interface. Tool names, commands, and README descriptions are kept as-is.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(AppCopy.text("settingsTerminal", language: language)) {
                Picker(AppCopy.text("defaultTerminal", language: language), selection: terminalTarget) {
                    ForEach(TerminalTarget.allCases) { target in
                        Text(target.displayName(language)).tag(target)
                    }
                }
                .accessibilityIdentifier("settings-terminal-picker")
                Text((TerminalTarget(rawValue: terminalTargetRawValue) ?? .systemTerminal).helpText(language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(AppCopy.text("toolDiscovery", language: language)) {
                Toggle(AppCopy.text("autoEnrich", language: language), isOn: $autoEnrich)
                Toggle(AppCopy.text("showIgnored", language: language), isOn: $showIgnoredCandidates)
                Text(AppCopy.text("scanPreferenceHint", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(AppCopy.text("discoveryPreview", language: language)) {
                Toggle(AppCopy.text("enableDiscoveryPreview", language: language), isOn: $discoveryPreviewEnabled)
                    .accessibilityIdentifier("settings-discovery-preview-enabled")
                if discoveryPreviewEnabled {
                    Button(AppCopy.text("clearDiscoveryCache", language: language)) {
                        DiscoveryCacheStore.clear()
                    }
                    .accessibilityIdentifier("settings-clear-discovery-cache")
                }
                Text(AppCopy.text("discoverySettingsHint", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(AppCopy.text("updates", language: language)) {
                Toggle(AppCopy.text("enableUpdateChecks", language: language), isOn: $updateChecksEnabled)
                    .accessibilityIdentifier("settings-update-check-enabled")
                if updateChecksEnabled {
                    HStack {
                        Button(AppCopy.text("checkForUpdates", language: language), action: checkForUpdates)
                            .disabled(isCheckingForUpdates)
                            .accessibilityIdentifier("settings-check-updates")
                        if isCheckingForUpdates { ProgressView().controlSize(.small) }
                    }
                }
                Text(AppCopy.text("updateChecksHint", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(AppCopy.text("mobileCompanion", language: language)) {
                HStack {
                    if case .listening(let code, let fingerprint) = pairingService.state {
                        Button(AppCopy.text("mobileCompanionDisable", language: language), action: pairingService.stopPairing)
                            .accessibilityIdentifier("settings-mobile-companion-disable")
                        Spacer()
                        Label(AppCopy.text("mobileCompanionListening", language: language), systemImage: "dot.radiowaves.left.and.right")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else if case .failed(let message) = pairingService.state {
                        Button(AppCopy.text("mobileCompanionEnable", language: language), action: pairingService.startPairing)
                            .accessibilityIdentifier("settings-mobile-companion-enable")
                        Spacer()
                        Label(AppCopy.format("mobileCompanionFailed", message, language: language), systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        Button(AppCopy.text("mobileCompanionEnable", language: language), action: pairingService.startPairing)
                            .accessibilityIdentifier("settings-mobile-companion-enable")
                        Spacer()
                        Text(AppCopy.text("mobileCompanionOff", language: language))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if case .listening(let code, let fingerprint) = pairingService.state {
                    HStack {
                        Text(AppCopy.text("mobileCompanionPairingCode", language: language))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(code)
                            .font(.system(.body, design: .monospaced).bold())
                            .textSelection(.enabled)
                            .accessibilityIdentifier("settings-mobile-companion-code")
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(AppCopy.text("mobileCompanionFingerprint", language: language))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(fingerprint)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                let active = pairingService.activePairedDevices
                if active.isEmpty {
                    Text(AppCopy.text("mobileCompanionNoPairedDevices", language: language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(active) { device in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.displayName)
                                    .font(.body)
                                Text(device.pairedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(AppCopy.text("mobileCompanionRevoke", language: language), role: .destructive) {
                                pairingService.revoke(id: device.id)
                            }
                            .accessibilityIdentifier("settings-mobile-companion-revoke-\(device.id.uuidString)")
                        }
                    }
                }
                Text(AppCopy.text("mobileCompanionHint", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // M2a 异地隧道（docs/m2-secure-remote-session-design.md §5）
            Section(AppCopy.text("mobileTunnel", language: language)) {
                HStack {
                    Toggle(AppCopy.text("mobileTunnel", language: language), isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: TailnetTunnelService.enabledDefaultsKey) },
                        set: { tunnelService.setEnabled($0) }))
                        .labelsHidden()
                        .accessibilityIdentifier("settings-mobile-tunnel-toggle")
                    Text(AppCopy.text("mobileTunnel", language: language))
                    Spacer()
                    switch tunnelService.state {
                    case .off:
                        Text(AppCopy.text("mobileTunnelOff", language: language))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .detecting:
                        ProgressView().controlSize(.small)
                    case .ready(let endpoint):
                        Label(AppCopy.format("mobileTunnelReady", endpoint, language: language), systemImage: "checkmark.shield")
                            .font(.caption)
                            .foregroundStyle(.green)
                    case .failed(let message):
                        Label(AppCopy.format("mobileTunnelFailed", message, language: language), systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Text(AppCopy.text("mobileTunnelHint", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // M2b 输出档位（docs/m2b-remote-task-console-design.md §5.4）：
                // Mac 是权威——手机端不持有档位状态，回传内容自然体现档位效果。
                Picker(AppCopy.text("remoteOutputVisibility", language: language), selection: Binding(
                    get: {
                        MobileTaskConsoleService.OutputVisibility(
                            rawValue: UserDefaults.standard.string(
                                forKey: MobileTaskConsoleService.outputVisibilityDefaultsKey) ?? "")
                            ?? .restricted
                    },
                    set: { UserDefaults.standard.set($0.rawValue, forKey: MobileTaskConsoleService.outputVisibilityDefaultsKey) }
                )) {
                    Text(AppCopy.text("remoteOutputVisibilityMinimal", language: language)).tag(MobileTaskConsoleService.OutputVisibility.minimal)
                    Text(AppCopy.text("remoteOutputVisibilityRestricted", language: language)).tag(MobileTaskConsoleService.OutputVisibility.restricted)
                    Text(AppCopy.text("remoteOutputVisibilityFull", language: language)).tag(MobileTaskConsoleService.OutputVisibility.full)
                }
                .accessibilityIdentifier("settings-output-visibility-picker")
                Text(AppCopy.text("remoteOutputVisibilityHint", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(AppCopy.text("aiConfiguration", language: language)) {
                SecureField(AppCopy.text("aiAPIKey", language: language), text: $apiKeyInput)
                    .textContentType(.password)
                TextField(AppCopy.text("aiBaseURL", language: language), text: $aiBaseURL)
                TextField(AppCopy.text("aiModel", language: language), text: $aiModel)

                HStack {
                    Button(AppCopy.text("saveToKeychain", language: language), action: saveAPIKey)
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(AppCopy.text("clearAPIKey", language: language), role: .destructive, action: clearAPIKey)
                        .disabled(!hasStoredAPIKey)
                }

                Label(
                    hasStoredAPIKey
                        ? AppCopy.text("apiKeyStored", language: language)
                        : AppCopy.text("apiKeyNotStored", language: language),
                    systemImage: hasStoredAPIKey ? "key.fill" : "key"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(AppCopy.text("aiConfigurationHint", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(AppCopy.text("dataManagement", language: language)) {
                Toggle(AppCopy.text("includeSavedValues", language: language), isOn: $includeSavedVariableValues)
                Text(AppCopy.text("backupHint", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button(AppCopy.text("exportBackup", language: language), action: prepareBackupExport)
                        .accessibilityIdentifier("settings-export-backup")
                    Button(AppCopy.text("importBackup", language: language)) {
                        isImportingBackup = true
                    }
                }
            }

            Section(AppCopy.text("diagnostics", language: language)) {
                HStack {
                    Button(AppCopy.text("exportDiagnostics", language: language), action: prepareDiagnosticsExport)
                        .accessibilityIdentifier("settings-export-diagnostics")
                    Button(AppCopy.text("clearDiagnostics", language: language), role: .destructive, action: clearDiagnostics)
                }
                Text(AppCopy.text("diagnosticsHint", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(AppCopy.text("dataPrivacy", language: language)) {
                Text(AppCopy.text("privacyHint", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("preferences-content")
        .onAppear {
            hasStoredAPIKey = AIService.hasStoredAPIKey
        }
        .alert(AppCopy.text("aiConfiguration", language: language), isPresented: Binding(
            get: { credentialMessage != nil },
            set: { if !$0 { credentialMessage = nil } }
        )) {
            Button(AppCopy.text("ok", language: language), role: .cancel) { credentialMessage = nil }
        } message: {
            Text(credentialMessage ?? "")
        }
        .alert(AppCopy.text("dataManagement", language: language), isPresented: Binding(
            get: { backupMessage != nil },
            set: { if !$0 { backupMessage = nil } }
        )) {
            Button(AppCopy.text("ok", language: language), role: .cancel) { backupMessage = nil }
        } message: {
            Text(backupMessage ?? "")
        }
        .alert(AppCopy.text("updates", language: language), isPresented: Binding(
            get: { updateMessage != nil },
            set: { if !$0 { updateMessage = nil } }
        )) {
            Button(AppCopy.text("ok", language: language), role: .cancel) { updateMessage = nil }
        } message: {
            Text(updateMessage ?? "")
        }
        .alert(AppCopy.text("diagnostics", language: language), isPresented: Binding(
            get: { diagnosticMessage != nil },
            set: { if !$0 { diagnosticMessage = nil } }
        )) {
            Button(AppCopy.text("ok", language: language), role: .cancel) { diagnosticMessage = nil }
        } message: {
            Text(diagnosticMessage ?? "")
        }
        .confirmationDialog(AppCopy.text("restorePreview", language: language), isPresented: Binding(
            get: { pendingImportedBackup != nil },
            set: { if !$0 { pendingImportedBackup = nil } }
        ), titleVisibility: .visible) {
            Button(AppCopy.text("restoreBackup", language: language), action: restoreImportedBackup)
            Button(AppCopy.text("cancelRestore", language: language), role: .cancel) { pendingImportedBackup = nil }
        } message: {
            Text(importPreviewMessage)
        }
        .fileExporter(
            isPresented: $isExportingBackup,
            document: backupDocument,
            contentType: .json,
            defaultFilename: BackupService.suggestedFileName()
        ) { result in
            switch result {
            case .success:
                DiagnosticsStore.shared.record(.backupExported, itemCount: tools.count + candidates.count)
                backupMessage = AppCopy.text("backupExported", language: language)
            case .failure(let error):
                backupMessage = backupFailureMessage(error)
            }
            backupDocument = nil
        }
        .fileImporter(isPresented: $isImportingBackup, allowedContentTypes: [.json]) { result in
            handleBackupImport(result)
        }
        .fileExporter(
            isPresented: $isExportingDiagnostics,
            document: diagnosticDocument,
            contentType: .json,
            defaultFilename: "TermiPad-diagnostics-\(diagnosticFileTimestamp())"
        ) { result in
            switch result {
            case .success:
                diagnosticMessage = AppCopy.text("diagnosticsExported", language: language)
            case .failure:
                diagnosticMessage = AppCopy.text("diagnosticsExportFailed", language: language)
            }
            diagnosticDocument = nil
        }
        .scrollContentBackground(.hidden)
        .background(theme.contentSurface)
        .padding(20)
        .frame(maxWidth: embeddedInNavigation ? .infinity : 560, alignment: .topLeading)
        .onAppear {
            pairingService.configure(modelContext: modelContext)
        }
        // 手机启动/任务确认弹窗已提升到 app 根视图（TermiPadApp 的
        // MobileLaunchConfirmationRootView）——用户不在设置页时也要能弹，
        // 此处保留挂载会与根视图重复弹窗。
    }

    private func saveAPIKey() {
        do {
            try AIService.saveAPIKey(apiKeyInput)
            apiKeyInput = ""
            hasStoredAPIKey = AIService.hasStoredAPIKey
            credentialMessage = AppCopy.text("apiKeyStored", language: language)
        } catch {
            let prefix = AppCopy.text("keychainOperationFailed", language: language)
            credentialMessage = "\(prefix) \(error.localizedDescription)"
        }
    }

    private func clearAPIKey() {
        do {
            try AIService.clearAPIKey()
            apiKeyInput = ""
            hasStoredAPIKey = false
            credentialMessage = AppCopy.text("apiKeyCleared", language: language)
        } catch {
            let prefix = AppCopy.text("keychainOperationFailed", language: language)
            credentialMessage = "\(prefix) \(error.localizedDescription)"
        }
    }

    private var importPreviewMessage: String {
        guard let backup = pendingImportedBackup else { return "" }
        let valuesText = backup.includesSavedVariableValues
            ? (language == .simplifiedChinese ? "包含已保存的变量值。" : "Saved variable values are included.")
            : (language == .simplifiedChinese ? "不包含已保存的变量值。" : "Saved variable values are not included.")
        let restoreHint = AppCopy.text("restoreHint", language: language)
        if language == .simplifiedChinese {
            return "备份包含 \(backup.tools.count) 个工具和 \(backup.candidates.count) 个候选项目。\(valuesText) \(restoreHint)"
        }
        return "This backup contains \(backup.tools.count) tools and \(backup.candidates.count) candidates. \(valuesText) \(restoreHint)"
    }

    private func checkForUpdates() {
        guard updateChecksEnabled else { return }
        isCheckingForUpdates = true

        Task { @MainActor in
            defer { isCheckingForUpdates = false }
            let result = await UpdateCheckService.check()
            updateMessage = updateCheckMessage(for: result)
        }
    }

    /// 把 CheckResult 转成用户可见的 alert 文本。同 CheckResult
    /// 的 displaySummary 但走 i18n 模板（zh/en 各有不同文案）。
    private func updateCheckMessage(for result: UpdateCheckService.CheckResult) -> String {
        switch result {
        case .neverChecked:
            return AppCopy.text("updateCheckNever", language: language)
        case .upToDate(let latest, _):
            return AppCopy.format("updateCheckUpToDate", latest, language: language)
        case .updateAvailable(let latest, _):
            return AppCopy.format("updateCheckAvailableBody", latest, language: language)
        case .checkFailed(let reason):
            return AppCopy.format("updateCheckFailed", reason, language: language)
        case .disabled:
            return AppCopy.text("updateCheckDisabled", language: language)
        }
    }

    /// 把 CheckResult 转成 alert 内容：升级时显示 "在 GitHub 上打开" 按钮，
    /// 其它情况只显示状态文字。Source-of-truth 在 UpdateCheckService——这个函数
    /// 只负责把 enum 翻译成 AppCopy 模板，不做网络调用。

    private func prepareDiagnosticsExport() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            diagnosticDocument = DiagnosticFileDocument(data: try encoder.encode(DiagnosticsStore.shared.makePrivacyReport()))
            isExportingDiagnostics = true
        } catch {
            diagnosticMessage = AppCopy.text("diagnosticsExportFailed", language: language)
        }
    }

    private func clearDiagnostics() {
        DiagnosticsStore.shared.clear()
        diagnosticMessage = AppCopy.text("diagnosticsCleared", language: language)
    }

    private func diagnosticFileTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: Date())
    }

    private func prepareBackupExport() {
        do {
            let backup = TermiPadBackup.make(
                tools: tools,
                candidates: candidates,
                includeSavedVariableValues: includeSavedVariableValues
            )
            backupDocument = BackupFileDocument(data: try BackupService.encode(backup))
            isExportingBackup = true
        } catch {
            backupMessage = backupFailureMessage(error)
        }
    }

    private func handleBackupImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess { url.stopAccessingSecurityScopedResource() }
            }
            do {
                pendingImportedBackup = try BackupService.decode(Data(contentsOf: url))
            } catch {
                backupMessage = backupFailureMessage(error)
            }
        case .failure(let error):
            backupMessage = backupFailureMessage(error)
        }
    }

    private func restoreImportedBackup() {
        guard let backup = pendingImportedBackup else { return }
        let summary = BackupService.restore(
            backup,
            existingTools: tools,
            existingCandidates: candidates,
            modelContext: modelContext
        )
        do {
            try modelContext.save()
            DiagnosticsStore.shared.record(
                .backupRestored,
                itemCount: summary.addedTools + summary.updatedTools + summary.addedCandidates + summary.updatedCandidates
            )
            pendingImportedBackup = nil
            backupMessage = restoreSummaryMessage(summary)
        } catch {
            backupMessage = backupFailureMessage(error)
        }
    }

    private func backupFailureMessage(_ error: Error) -> String {
        DiagnosticsStore.shared.record(.backupFailed)
        let prefix = AppCopy.text("backupImportFailed", language: language)
        return "\(prefix) \(error.localizedDescription)"
    }

    private func restoreSummaryMessage(_ summary: BackupRestoreSummary) -> String {
        if language == .simplifiedChinese {
            return "新增 \(summary.addedTools) 个工具，更新 \(summary.updatedTools) 个工具；新增 \(summary.addedCandidates) 个候选，更新 \(summary.updatedCandidates) 个候选。"
        }
        return "\(summary.addedTools) tools added, \(summary.updatedTools) tools updated; \(summary.addedCandidates) candidates added, \(summary.updatedCandidates) candidates updated."
    }
}
