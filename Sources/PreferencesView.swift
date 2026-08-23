import SwiftUI

struct PreferencesView: View {
    @AppStorage("TermiPad.language") private var languageRawValue = AppLanguage.simplifiedChinese.rawValue
    @AppStorage("TermiPad.appearance") private var appearanceRawValue = AppAppearance.system.rawValue
    @AppStorage("TermiPad.terminalTarget") private var terminalTargetRawValue = TerminalTarget.systemTerminal.rawValue
    @AppStorage("TermiPad.autoEnrich") private var autoEnrich = true
    @AppStorage("TermiPad.showIgnoredCandidates") private var showIgnoredCandidates = false

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRawValue) ?? .simplifiedChinese
    }

    private var appearance: Binding<AppAppearance> {
        Binding(
            get: { AppAppearance(rawValue: appearanceRawValue) ?? .system },
            set: { appearanceRawValue = $0.rawValue }
        )
    }

    private var terminalTarget: Binding<TerminalTarget> {
        Binding(
            get: { TerminalTarget(rawValue: terminalTargetRawValue) ?? .systemTerminal },
            set: { terminalTargetRawValue = $0.rawValue }
        )
    }

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

            Section(AppCopy.text("dataPrivacy", language: language)) {
                Text(AppCopy.text("privacyHint", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 560)
    }
}
