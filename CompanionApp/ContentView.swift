import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var client: CompanionPairingClient

    var body: some View {
        NavigationStack {
            Form {
                pairingSection
            }
            .navigationTitle("TermiPad 伴侣")
        }
    }

    @ViewBuilder
    private var pairingSection: some View {
        Section {
            switch client.phase {
            case .idle:
                Button("开始搜索附近的 Mac") { client.startBrowsing() }
                    .accessibilityIdentifier("companion-start-browsing")
            case .browsing:
                HStack {
                    ProgressView()
                    Text("正在搜索同一 Wi-Fi 下的 Mac…")
                        .foregroundStyle(.secondary)
                }
                Button("停止", role: .destructive) { client.stopBrowsing() }
            case .connecting(let mac):
                HStack {
                    ProgressView()
                    Text("正在连接 \(mac.serviceName)…")
                }
            case .verifyFingerprint(let mac, let fingerprint):
                Text("已发现 \(mac.serviceName)")
                    .font(.body.bold())
                VStack(alignment: .leading, spacing: 4) {
                    Text("第 1 步：核对指纹")
                        .font(.caption.bold())
                    Text("手机下面的指纹必须与 Mac「设置 → 手机伴侣」屏幕上的完全一致：")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(fingerprint)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .accessibilityIdentifier("companion-mac-fingerprint")
                }
                TextField("设备名（如：我的 iPhone）", text: $client.deviceName)
                    .accessibilityIdentifier("companion-device-name")
                TextField("第 2 步：输入 Mac 屏上的 6 位配对码", text: $client.pairingCodeInput)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("companion-pairing-code-input")
                Button("指纹一致，开始配对") { client.confirmFingerprintAndPair() }
                    .accessibilityIdentifier("companion-confirm-pairing")
                Button("取消", role: .destructive) { client.stopBrowsing() }
            case .awaitingAck:
                HStack {
                    ProgressView()
                    Text("正在完成配对…")
                }
            case .paired:
                Label("配对成功", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.body.bold())
                Text("Mac 已在钥匙串记录本机。工具目录与启动请求将在后续版本开放。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
}

#Preview {
    ContentView().environmentObject(CompanionPairingClient())
}
