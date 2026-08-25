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
    @AppStorage("TermiPad.language") private var languageRawValue = AppLanguage.simplifiedChinese.rawValue
    @AppStorage("TermiPad.appearance") private var appearanceRawValue = AppAppearance.system.rawValue
    @AppStorage("TermiPad.terminalTarget") private var terminalTargetRawValue = TerminalTarget.systemTerminal.rawValue
    @AppStorage("TermiPad.autoEnrich") private var autoEnrich = false
    @AppStorage("TermiPad.showIgnoredCandidates") private var showIgnoredCandidates = false
    @AppStorage(AIService.baseURLDefaultsKey) private var aiBaseURL = "https://api.openai.com/v1"
    @AppStorage(AIService.modelDefaultsKey) private var aiModel = "gpt-4o-mini"

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
