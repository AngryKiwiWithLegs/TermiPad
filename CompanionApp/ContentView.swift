import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var client: CompanionPairingClient

    var body: some View {
        NavigationStack {
            Form {
                pairingSection
                if case .paired = client.phase {
                    Section("已配对 Mac") {
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
                    Text("正在搜索同一 Wi-Fi 下的 Mac…")
                        .foregroundStyle(.secondary)
                }
            case .connecting(let mac):
                HStack {
                    ProgressView()
                    Text("正在连接 \(mac.serviceName)…")
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
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.displayName).font(.body.bold())
                        if !summary.displayDescription.isEmpty {
                            Text(summary.displayDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("id: \(summary.id.uuidString.prefix(8))…")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
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
