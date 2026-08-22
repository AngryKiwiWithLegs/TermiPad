import SwiftUI

struct PreferencesView: View {
    @AppStorage("TermiPad.terminalTarget") private var terminalTargetRawValue = TerminalTarget.systemTerminal.rawValue
    @AppStorage("TermiPad.autoEnrich") private var autoEnrich = true
    @AppStorage("TermiPad.showIgnoredCandidates") private var showIgnoredCandidates = false

    private var terminalTarget: Binding<TerminalTarget> {
        Binding(
            get: { TerminalTarget(rawValue: terminalTargetRawValue) ?? .systemTerminal },
            set: { terminalTargetRawValue = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("终端启动") {
                Picker("默认终端", selection: terminalTarget) {
                    ForEach(TerminalTarget.allCases) { target in
                        Text(target.rawValue).tag(target)
                    }
                }
                Text((TerminalTarget(rawValue: terminalTargetRawValue) ?? .systemTerminal).helpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("工具发现") {
                Toggle("扫描后自动补充 GitHub / AI 信息", isOn: $autoEnrich)
                Toggle("在候选收件箱显示已忽略项目", isOn: $showIgnoredCandidates)
                Text("扫描到的命令会先进入候选收件箱，只有确认后才会出现在工具墙。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("数据与隐私") {
                Text("工具列表、分类、模板和变量值保存在这台 Mac 上。GitHub 与 AI 补充功能只会在您开启自动补充时访问网络。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 520)
    }
}
