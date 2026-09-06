import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var client: CompanionPairingClient

    var body: some View {
        NavigationStack {
            Form {
                Section("Mac 配对") {
                    switch client.phase {
                    case .idle:
                        Button("开始搜索附近的 Mac") { client.startBrowsing() }
                            .accessibilityIdentifier("companion-start-browsing")
                    case .browsing:
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("正在搜索…")
                        }
                    case .awaitingPairingCode(let serviceName, _):
                        Text("已发现 \(serviceName)")
                            .font(.body.bold())
                        TextField("设备名", text: $client.deviceName)
                            .textInputAutocapitalization(.never)
                            .accessibilityIdentifier("companion-device-name")
                        TextField("6 位配对码", text: $client.pairingCodeInput)
                            .keyboardType(.numberPad)
                            .accessibilityIdentifier("companion-pairing-code-input")
                        Text("请在 Mac 端『设置 → 手机伴侣』查看配对码与指纹，并人工比对两者一致。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("提交配对") { client.submitPairingCode() }
                            .accessibilityIdentifier("companion-submit")
                        Button("停止搜索", role: .destructive) { client.stopBrowsing() }
                    case .paired(_, let deviceName):
                        Label("已配对：\(deviceName)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Mac 端已记录此设备。后续工具目录与启动请求将由本地局域网完成。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .failed(let message):
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                        Button("重试") { client.startBrowsing() }
                    }
                }
            }
            .navigationTitle("TermiPad 伴侣")
        }
    }
}

#Preview {
    ContentView().environmentObject(CompanionPairingClient())
}
