import SwiftUI

struct PreferencesView: View {
    @Environment(\.colorScheme) private var colorScheme
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

            Section(AppCopy.text("dataPrivacy", language: language)) {
                Text(AppCopy.text("privacyHint", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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
        .scrollContentBackground(.hidden)
        .background(theme.contentSurface)
        .padding(20)
        .frame(width: 560)
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
}
