// M2a 异地隧道服务（docs/m2-secure-remote-session-design.md §5）。
// 集成模型：依赖用户自装的 Tailscale（OpenClaw 已验证模式），TermiPad 只做编排——
// 不内嵌 tailscaled、不自造 WireGuard、永久禁用 Funnel（公网暴露红线）。
// Mac 端只开一个仅绑 127.0.0.1 的回环监听（57147），由 `tailscale serve --tcp`
// 把 tailnet 流量转发进来——公网/局域网/其他虚拟网卡均不可见该端口。
// CLI 调用纪律：固定绝对路径 + 固定参数 + 无用户输入拼接，不经 shell（与
// EnvironmentReport 同款）；全仓只允许本文件调用 tailscale CLI（verify-macos.sh 守卫）。
import Foundation
import Network

/// 跨隔离域共享的隧道端点盒：TailnetTunnelService（MainActor）写入，
/// MobilePairingService 的 nonisolated static 握手链在构造 MacResumeHello 时读取。
/// NSLock 保护——握手在 listenerQueue 上运行，不能碰 MainActor 状态。
final class TailnetEndpointHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    func set(_ newValue: String?) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

@MainActor
final class TailnetTunnelService: ObservableObject {
    enum TunnelState: Equatable {
        case off
        case detecting
        case ready(endpoint: String)
        case failed(String)
    }

    static let shared = TailnetTunnelService()
    static let tunnelListenerPort: UInt16 = MobilePairingCrypto.tunnelListenerPort
    /// 回环后端端口（Mac 本机内部）。tailscaled 的 serve 前端占着 tailnet 侧
    /// 57147 时，内核拒绝同端口号的回环绑定（EADDRINUSE，实测复现）——
    /// OpenClaw 同款解法：前端与后端用不同端口，serve 把 tailnet:57147
    /// 转发到 127.0.0.1:57148。手机端只见 57147，后端端口不出 Mac。
    static let loopbackBackendPort: UInt16 = 57148
    /// 用户偏好持久化键：开启后 app 每次启动自动恢复隧道（异地能力是常驻
    /// 基础设施，不像配对模式那样需要屏显配对码）。
    static let enabledDefaultsKey = "TermiPad.mobileTailnetTunnelEnabled"
    /// 固定绝对路径白名单：只认 Homebrew 与 /usr/local 两个安装位置，
    /// 不搜索 PATH、不接受用户配置路径。
    nonisolated static let cliCandidatePaths = [
        "/opt/homebrew/bin/tailscale",
        "/usr/local/bin/tailscale"
    ]

    /// 握手链读取的端点共享盒（static，随进程存活）。
    nonisolated static let endpointHolder = TailnetEndpointHolder()

    @Published private(set) var state: TunnelState = .off

    private var loopbackListener: NWListener?
    private let listenerQueue = DispatchQueue(label: "com.termipad.tailnet-tunnel", qos: .userInitiated)

    private init() {}

    /// app 启动时调用：用户上次开启过则自动恢复。
    func restoreIfNeeded() {
        guard UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey), state == .off else {
            return
        }
        enable()
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.enabledDefaultsKey)
        if enabled {
            enable()
        } else {
            disable()
        }
    }

    /// 开启：检测 CLI → 配置 serve 转发 → 读 tailnet IP → 启动回环监听。
    func enable() {
        guard loopbackListener == nil, state != .detecting else { return }
        state = .detecting
        Task.detached(priority: .userInitiated) { [port = Self.tunnelListenerPort, backend = Self.loopbackBackendPort] in
            let result = Self.configureServe(port: port, backendPort: backend)
            await MainActor.run { self.finishEnable(result: result, port: port) }
        }
    }

    func disable() {
        let hadListener = loopbackListener != nil
        stopLoopbackListener()
        Self.endpointHolder.set(nil)
        state = .off
        if hadListener {
            DiagnosticsStore.shared.record(.remoteTunnelClosed)
        }
        // 后台撤销 serve 转发——失败只记诊断，UI 状态已是 off。
        Task.detached(priority: .utility) { [port = Self.tunnelListenerPort] in
            _ = Self.runFixedCLI(arguments: ["serve", "--tcp=\(port)", "off"])
        }
        // 关闭隧道即清会话白名单——免确认缓存绝不超出其授权通道的生命周期。
        MobileLaunchSession.shared.invalidateAll()
    }

    // MARK: - 启用流程

    private func finishEnable(result: ServeConfigResult, port: UInt16) {
        switch result {
        case .binaryNotFound:
            MobilePairingService.diagMac("隧道失败：未找到 tailscale CLI（固定路径白名单）")
            state = .failed("未找到 Tailscale。请安装并登录后重试（brew install tailscale 或 App Store 版）。")
        case .cliError(let message):
            MobilePairingService.diagMac("隧道失败：\(message)")
            state = .failed("Tailscale 配置失败：\(message)")
        case .configured(let endpoint):
            startLoopbackListener(port: Self.loopbackBackendPort, endpoint: endpoint)
        }
    }

    private func startLoopbackListener(port: UInt16, endpoint: String) {
        let parameters = NWParameters.tcp
        // 仅绑回环接口：该端口对局域网/公网/其他虚拟网卡不可见，只有 tailscaled
        // 的 serve 转发能到达——红线"不开公网端口"的最强形态。
        // 注意：requiredLocalEndpoint 只作用于出站连接，对 NWListener 的监听
        // 绑定**无效**（曾导致"状态就绪但端口根本没绑上"）；监听绑定必须用
        // requiredInterfaceType = .loopback（2026-09-08 实测：自连成功）。
        parameters.requiredInterfaceType = .loopback
        // 快速 关→开 时旧 socket 尚在 TIME_WAIT（M1 同款坑）：不设复用会报
        // "地址已被使用"，表现为第二次打开开关必失败。
        parameters.allowLocalEndpointReuse = true
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            MobilePairingService.diagMac("隧道失败：回环监听创建失败：\(error.localizedDescription)")
            state = .failed("本地监听启动失败：\(error.localizedDescription)")
            return
        }
        listener.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            Task { @MainActor in
                if case .failed(let error) = newState {
                    MobilePairingService.diagMac("隧道监听失败：\(error.localizedDescription)")
                    self.stopLoopbackListener()
                    Self.endpointHolder.set(nil)
                    self.state = .failed("隧道监听错误：\(error.localizedDescription)")
                }
            }
        }
        listener.newConnectionHandler = { connection in
            // 与 M1 同网监听共享同一条握手链——隧道只接受已配对设备的复用请求，
            // 首次配对必须留在同网（人工比对指纹的设计前提）。
            MobilePairingService.beginResumeOnlyHandshake(
                on: connection,
                queue: self.listenerQueue)
        }
        listener.start(queue: listenerQueue)
        loopbackListener = listener
        Self.endpointHolder.set(endpoint)
        state = .ready(endpoint: endpoint)
        DiagnosticsStore.shared.record(.remoteTunnelOpened)
        MobilePairingService.diagMac("异地隧道就绪：\(endpoint)（回环监听 + tailscale serve 转发）")
    }

    private func stopLoopbackListener() {
        loopbackListener?.cancel()
        loopbackListener = nil
    }

    // MARK: - CLI 编排（固定路径 + 固定参数，后台队列执行）

    private enum ServeConfigResult {
        case configured(endpoint: String)
        case binaryNotFound
        case cliError(String)
    }

    nonisolated private static func resolveCLIBinary() -> String? {
        cliCandidatePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// 顺序：serve 配置转发 → tailscale ip -4 取端点。任何一步失败即放弃
    /// （UI 显式报错，不静默降级）。
    nonisolated private static func configureServe(port: UInt16, backendPort: UInt16) -> ServeConfigResult {
        guard let binary = resolveCLIBinary() else {
            return .binaryNotFound
        }
        guard runFixedCLI(
            arguments: ["serve", "--bg", "--tcp=\(port)", "tcp://127.0.0.1:\(backendPort)"]) != nil else {
            return .cliError("serve 转发配置未成功（确认 Tailscale 已登录）")
        }
        // serve 成功输出含端点行；再取本机 tailnet IPv4 拼"IP:port"。
        guard let ipOutput = runFixedCLI(arguments: ["ip", "-4"]),
              let tailnetIP = ipOutput
                  .split(whereSeparator: \.isNewline)
                  .first?
                  .trimmingCharacters(in: .whitespaces),
              !tailnetIP.isEmpty else {
            return .cliError("无法读取 tailnet IP（确认 Tailscale 已连接）")
        }
        return .configured(endpoint: "\(tailnetIP):\(port)")
    }

    /// 跑一条固定参数的 tailscale 子命令。直接 exec 绝对路径——不搜索 PATH、
    /// 不经 shell、参数全部来自本文件的字面量。返回 stdout（含 stderr 拼接），
    /// 退出码非 0 返回 nil。
    nonisolated private static func runFixedCLI(arguments: [String]) -> String? {
        guard let binary = resolveCLIBinary() else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe
        do {
            try process.run()
        } catch {
            return nil
        }
        let stdoutData = pipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return nil
        }
        var output = String(data: stdoutData, encoding: .utf8) ?? ""
        if let stderr = String(data: stderrData, encoding: .utf8), !stderr.isEmpty {
            output += stderr
        }
        return output
    }
}
