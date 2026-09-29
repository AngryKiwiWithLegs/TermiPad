// M6 终端遥控服务（docs/m6-keyboard-remote-design.md §2.1）。
// 职责：拉起并管理**一个**受控 PTY shell（TermiPad 自己 fork 的 zsh，
// 不接管用户已有终端窗口）；输出接入 M4 流管道（TaskOutputStreamService
// 分发）；输入（控制键/整行命令）write 进 PTY master。
// 生命周期绑定每日远程窗口：关窗/锁屏 → PTY 收 SIGTERM（shell 退出）。
// 进程纪律：forkpty 仅本文件（verify-macos.sh 白名单）；shell 路径固定
// /bin/zsh（无用户输入拼接）；单会话（新开踢旧）。
import Foundation

@MainActor
final class TerminalRemoteService: ObservableObject {
    static let shared = TerminalRemoteService()

    /// shell 固定路径（不读用户配置——进程纪律）。
    private static let shellPath = "/bin/zsh"
    /// 无输入自动退出（秒）：闲置 shell 不常驻。
    static let idleTimeout: TimeInterval = 30 * 60

    private var shellProcess: Process?
    private var masterFd: Int32 = -1
    private var outputSource: DispatchSourceRead?
    private var idleKickTask: Task<Void, Never>?
    private(set) var isRunning = false

    private init() {}

    // MARK: - 生命周期

    /// 拉起 PTY shell（openShellStream 分发调用；已运行则复用）。
    /// 返回 false = fork 失败。
    func ensureShell() -> Bool {
        if isRunning {
            rescheduleIdleKick()
            return true
        }
        var master: Int32 = -1
        let pid = forkpty(&master, nil, nil, nil)
        guard pid >= 0 else {
            MobilePairingService.diagMac("PTY fork 失败：errno=\(errno)")
            return false
        }
        if pid == 0 {
            // 子进程：exec 固定 shell（forkpty 已把 slave 设为控制终端）。
            // Swift 下 execl 变参不可用——execv 数组形式等价。
            let pathC = strdup(Self.shellPath)!
            var argv: [UnsafeMutablePointer<CChar>?] = [strdup("zsh"), strdup("-l"), nil]
            execv(pathC, &argv)
            // exec 不返回；走到这里 = exec 失败（未可达，防御性退出）。
            exit(127)
        }
        masterFd = master
        isRunning = true
        startOutputReader()
        rescheduleIdleKick()
        MobilePairingService.diagMac("PTY shell 已拉起 pid=\(pid)")
        return true
    }

    /// 关闭 shell（关窗/锁屏/退订/超时）：TERM → 等待 → KILL。
    func terminateShell(reason: String) {
        guard isRunning else { return }
        MobilePairingService.diagMac("PTY shell 关闭：\(reason)")
        outputSource?.cancel()
        outputSource = nil
        if masterFd >= 0 {
            // 先关 master——slave 侧 shell 收到 EOF/HUP 退出。
            close(masterFd)
            masterFd = -1
        }
        shellProcess?.waitUntilExit()
        shellProcess = nil
        isRunning = false
        idleKickTask?.cancel()
        idleKickTask = nil
    }

    /// 每日窗口关闭钩子（设计 §3：锁屏即杀 PTY）。
    func invalidateOnWindowClose() {
        terminateShell(reason: "每日远程窗口关闭")
    }

    // MARK: - 输入（手机 → PTY）

    /// 控制键：与 bash/zsh 键名对应（"C-c"→0x03、"Return"→0x0A 等）。
    func sendKey(_ key: String) {
        guard isRunning, masterFd >= 0 else { return }
        let bytes: [UInt8]
        switch key {
        case "C-c": bytes = [0x03]
        case "C-d": bytes = [0x04]
        case "C-l": bytes = [0x0C]
        case "C-u": bytes = [0x15]
        case "Return": bytes = [0x0A]
        case "Tab": bytes = [0x09]
        case "Up": bytes = [0x1B, 0x5B, 0x41]
        case "Down": bytes = [0x1B, 0x5B, 0x42]
        case "Right": bytes = [0x1B, 0x5B, 0x43]
        case "Left": bytes = [0x1B, 0x5B, 0x44]
        default:
            MobilePairingService.diagMac("未知控制键：\(key)")
            return
        }
        bytes.withUnsafeBufferPointer { buf in
            _ = write(masterFd, buf.baseAddress, buf.count)
        }
        rescheduleIdleKick()
    }

    /// 整行命令：文本 + 换行（设计 §1"发送自动补 \n"）。
    func sendLine(_ text: String) {
        guard isRunning, masterFd >= 0 else { return }
        let line = text + "\n"
        let data = Data(line.utf8)
        data.withUnsafeBytes { buf in
            _ = write(masterFd, buf.baseAddress, buf.count)
        }
        rescheduleIdleKick()
    }

    // MARK: - 输出（PTY → 手机流）

    private func startOutputReader() {
        let source = DispatchSource.makeReadSource(fileDescriptor: masterFd,
                                                   queue: DispatchQueue(label: "com.termipad.pty-output", qos: .userInitiated))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            var buf = [UInt8](repeating: 0, count: 8192)
            let n = read(self.masterFd, &buf, buf.count)
            guard n > 0 else {
                // EOF：shell 退出。
                Task { @MainActor in
                    self.handleShellExit()
                }
                source.cancel()
                return
            }
            let text = String(decoding: buf[0..<n], as: UTF8.self)
            Task { @MainActor in
                TaskOutputStreamService.shared.dispatchOutput(
                    taskID: Self.shellStreamID, rawText: text)
            }
        }
        source.resume()
        outputSource = source
    }

    /// shell 流的固定 taskID（流管道按 ID 分发）。
    static let shellStreamID = UUID(uuidString: "C0FFEE00-0000-4000-8000-5445524D4950")!

    private func handleShellExit() {
        MobilePairingService.diagMac("PTY shell 已退出")
        isRunning = false
        shellProcess = nil
        if masterFd >= 0 { close(masterFd); masterFd = -1 }
        idleKickTask?.cancel()
        idleKickTask = nil
        TaskOutputStreamService.shared.dispatchStateChange(
            taskID: Self.shellStreamID,
            state: "stopped",
            exitCode: nil,
            finishedAt: Date())
    }

    private func rescheduleIdleKick() {
        idleKickTask?.cancel()
        idleKickTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.idleTimeout * 1_000_000_000))
            guard let self, self.isRunning else { return }
            self.terminateShell(reason: "闲置超时（\(Int(Self.idleTimeout / 60)) 分钟无输入）")
        }
    }
}
