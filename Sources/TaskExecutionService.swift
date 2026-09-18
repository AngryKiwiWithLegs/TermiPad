import Combine
import Foundation

struct TaskExecutionRequest: Equatable {
    let executableURL: URL
    let arguments: [String]
    let currentDirectoryURL: URL
    let environment: [String: String]
    let timeout: TimeInterval
}

enum TaskExecutionDecision: Equatable {
    case ready(TaskExecutionRequest)
    case rejected(TaskExecutionRejectionReason)
}

/// T1 纯本机预检与生命周期状态机。固定目录之外的内容无法形成执行请求。
enum TaskExecutionPolicy {
    static func prepare(
        intent: TaskIntent,
        scope: TaskProjectScope?,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) -> TaskExecutionDecision {
        guard intent.state == .approved else { return .rejected(.intentNotApproved) }
        guard intent.executionState == .notStarted else { return .rejected(.taskAlreadyStarted) }
        guard intent.expiresAt > now else { return .rejected(.intentExpired) }
        guard let scope, scope.id == intent.projectScopeID, !scope.isRevoked, scope.directoryIsAvailable else {
            return .rejected(.projectScopeUnavailable)
        }
        guard let kind = intent.kind, let definition = FixedTaskCatalog.definition(for: kind) else {
            return .rejected(.taskDefinitionUnavailable)
        }

        let rootURL = URL(fileURLWithPath: scope.rootPath, isDirectory: true).resolvingSymlinksInPath()
        guard definition.requiredRelativePaths.allSatisfy({ relativePath in
            fileManager.fileExists(atPath: rootURL.appendingPathComponent(relativePath).path)
        }) else {
            return .rejected(.taskPreflightFailed)
        }

        let executableURL: URL?
        switch definition.executable {
        case .absoluteCandidates(let paths):
            executableURL = paths
                .map { URL(fileURLWithPath: $0) }
                .first { fileManager.isExecutableFile(atPath: $0.path) }
        case .projectRelative(let relativePath):
            let candidate = rootURL.appendingPathComponent(relativePath).resolvingSymlinksInPath()
            executableURL = candidate.path.hasPrefix(rootURL.path + "/") && fileManager.isExecutableFile(atPath: candidate.path)
                ? candidate
                : nil
        }
        guard let executableURL else { return .rejected(.taskPreflightFailed) }

        return .ready(TaskExecutionRequest(
            executableURL: executableURL,
            arguments: definition.arguments,
            currentDirectoryURL: rootURL,
            environment: [
                "HOME": rootURL.path,
                "LANG": "en_US_POSIX",
                "LC_ALL": "en_US_POSIX",
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
            ],
            timeout: definition.timeout
        ))
    }

    static func markStarted(_ intent: TaskIntent, now: Date = Date()) {
        intent.executionState = .running
        intent.executionStartedAt = now
        intent.executionFinishedAt = nil
        intent.executionExitCode = nil
        intent.executionRejectionReason = nil
    }

    static func markExited(_ intent: TaskIntent, exitCode: Int, now: Date = Date()) {
        guard intent.executionState == .running else { return }
        intent.executionState = exitCode == 0 ? .succeeded : .failed
        intent.executionExitCode = exitCode
        intent.executionFinishedAt = now
    }

    static func markTimedOut(_ intent: TaskIntent, now: Date = Date()) {
        guard intent.executionState == .running else { return }
        intent.executionState = .timedOut
        intent.executionFinishedAt = now
    }

    static func markStopped(_ intent: TaskIntent, now: Date = Date()) {
        guard intent.executionState == .running else { return }
        intent.executionState = .stopped
        intent.executionFinishedAt = now
    }

    static func markStartRejected(_ intent: TaskIntent, reason: TaskExecutionRejectionReason, now: Date = Date()) {
        intent.executionState = .startRejected
        intent.executionRejectionReason = reason
        intent.executionFinishedAt = now
    }

    static func markStartFailed(_ intent: TaskIntent, now: Date = Date()) {
        intent.executionState = .startFailed
        intent.executionFinishedAt = now
    }
}

/// T1 的唯一进程入口。任务以空 stdin 运行；stdout/stderr 默认丢弃
/// （minimal 档位——M2b-2 之前的行为），仅保留退出码和固定状态。
/// M2b-2（docs/m2b-remote-task-console-design.md §5.4）：输出档位 ≥
/// restricted 时，stdout/stderr 捕获进**仅内存** ring buffer（上限
/// 32 KB / 400 行任一先到即停）——供任务会话回传末尾片段（脱敏后）。
/// 捕获缓冲永不落盘、不进备份、不进诊断。
@MainActor
final class TaskExecutionCoordinator: ObservableObject {
    static let shared = TaskExecutionCoordinator()

    /// 输出捕获缓冲上限（字节 / 行数，任一先到即停——超过后输出只计数丢弃）。
    static let outputCaptureByteLimit = 32 * 1024
    static let outputCaptureLineLimit = 400

    /// 单任务的仅内存输出捕获（行数组，ring 自然保留末尾；计数不被截断丢失）。
    struct OutputCapture {
        private(set) var lines: [String] = []
        private(set) var totalBytes = 0
        private(set) var truncated = false

        mutating func append(_ line: String) {
            let byteCount = line.utf8.count + 1
            if totalBytes + byteCount > TaskExecutionCoordinator.outputCaptureByteLimit
                || lines.count >= TaskExecutionCoordinator.outputCaptureLineLimit {
                truncated = true
                return
            }
            lines.append(line)
            totalBytes += byteCount
        }

        /// 末尾最多 32 行——restricted 档位回传的就是这个切片。
        func tailSnippet() -> String {
            lines.suffix(32).joined(separator: "\n")
        }
    }

    @Published private(set) var runningIntentIDs: Set<UUID> = []
    private var activeProcesses: [UUID: Process] = [:]
    private var activeIntents: [UUID: TaskIntent] = [:]
    private var completionHandlers: [UUID: () -> Void] = [:]
    /// 档位 ≥ restricted 时的捕获中任务（intentID → 缓冲 + 收流管道）。
    private var outputCaptures: [UUID: OutputCapture] = [:]
    private var outputPipes: [UUID: Pipe] = [:]
    private var outputSources: [UUID: DispatchSourceRead] = [:]

    /// 是否捕获输出（档位裁决——读取 Mac 端权威设置）。
    var capturesOutput: Bool {
        MobileTaskConsoleService.shared.currentVisibility != .minimal
    }

    /// M2b-3：手机取消任务时取回活动 intent（进程停止需要 intent 对象）。
    func intent(forID id: UUID) -> TaskIntent? {
        activeIntents[id]
    }

    @discardableResult
    func start(
        intent: TaskIntent,
        scope: TaskProjectScope?,
        onCompletion: @escaping () -> Void
    ) -> TaskExecutionDecision {
        let decision = TaskExecutionPolicy.prepare(intent: intent, scope: scope)
        guard case .ready(let request) = decision else {
            if case .rejected(let reason) = decision {
                TaskExecutionPolicy.markStartRejected(intent, reason: reason)
                DiagnosticsStore.shared.record(.taskExecutionRejected)
            }
            return decision
        }

        let process = Process()
        process.executableURL = request.executableURL
        process.arguments = request.arguments
        process.currentDirectoryURL = request.currentDirectoryURL
        process.environment = request.environment
        process.standardInput = FileHandle.nullDevice
        if capturesOutput {
            attachOutputCapture(for: intent.id, to: process)
        } else {
            // minimal 档位：维持原行为——stdout/stderr 全丢弃。
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }
        let intentID = intent.id
        process.terminationHandler = { [weak self, intentID] completedProcess in
            let exitCode = Int(completedProcess.terminationStatus)
            Task { @MainActor [weak self, intentID, exitCode] in
                self?.finish(intentID: intentID, exitCode: exitCode)
            }
        }

        do {
            try process.run()
        } catch {
            TaskExecutionPolicy.markStartFailed(intent)
            DiagnosticsStore.shared.record(.taskExecutionStartFailed)
            return .rejected(.taskPreflightFailed)
        }

        TaskExecutionPolicy.markStarted(intent)
        activeProcesses[intent.id] = process
        activeIntents[intent.id] = intent
        completionHandlers[intent.id] = onCompletion
        runningIntentIDs.insert(intent.id)
        DiagnosticsStore.shared.record(.taskExecutionStarted)
        scheduleTimeout(for: intent.id, after: request.timeout)
        return decision
    }

    func stop(intent: TaskIntent) {
        guard let process = activeProcesses[intent.id], process.isRunning else { return }
        TaskExecutionPolicy.markStopped(intent)
        DiagnosticsStore.shared.record(.taskExecutionStopped)
        process.terminate()
        // 条目登记统一由 finish()（terminationHandler 必经路径）做——
        // 这里提前登记会被 finish 的二次登记用空片段覆盖。
    }

    /// 档位 ≥ restricted：stdout+stderr 合并捕获到仅内存 ring buffer。
    /// 行级读取（DispatchSourceRead），字节/行数上限任一先到即停——
    /// 缓冲不落盘；任务结束即从管道字典移除（缓冲保留到条目登记）。
    private func attachOutputCapture(for intentID: UUID, to process: Process) {
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        outputCaptures[intentID] = OutputCapture()
        outputPipes[intentID] = pipe
        let source = DispatchSource.makeReadSource(
            fileDescriptor: pipe.fileHandleForReading.fileDescriptor,
            queue: DispatchQueue(label: "com.termipad.task-output", qos: .utility))
        source.setEventHandler { [weak self] in
            let data = pipe.fileHandleForReading.availableData
            guard !data.isEmpty else {
                source.cancel()
                return
            }
            guard let self else { return }
            Task { @MainActor in
                let text = String(data: data, encoding: .utf8) ?? ""
                for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                    self.outputCaptures[intentID]?.append(String(line))
                }
                // M4 流式分发：捕获的每段文本即推给活跃订阅者
                // （TaskOutputStreamService 内部做游标、合帧、脱敏、背压）。
                TaskOutputStreamService.shared.dispatchOutput(
                    taskID: intentID, rawText: text)
            }
        }
        source.setCancelHandler { [weak self] in
            try? pipe.fileHandleForReading.close()
            Task { @MainActor in
                self?.outputSources.removeValue(forKey: intentID)
                self?.outputPipes.removeValue(forKey: intentID)
            }
        }
        source.resume()
        outputSources[intentID] = source
    }

    /// 任务生命周期落地：状态 + 退出码 + （档位 ≥ restricted 时）脱敏后的
    /// 末尾片段登记进手机会话条目流（MobileTaskConsoleService 做档位裁决）。
    private func recordConsoleEntry(for intent: TaskIntent) {
        let title = intent.kind.flatMap { kind in
            FixedTaskCatalog.definition(for: kind)?.purpose(language: .simplifiedChinese)
        } ?? "固定任务"
        let snippet = outputCaptures.removeValue(forKey: intent.id)
        let rawSnippet = (snippet?.tailSnippet()).map(OutputRedactor.redact)
        MobileTaskConsoleService.shared.recordTaskState(
            id: intent.id,
            title: title,
            executionState: intent.executionState,
            exitCode: intent.executionExitCode,
            startedAt: intent.executionStartedAt,
            finishedAt: intent.executionFinishedAt,
            outputSnippet: rawSnippet)
    }

    private func scheduleTimeout(for intentID: UUID, after timeout: TimeInterval) {
        Task { @MainActor [weak self, intentID] in
            try? await Task.sleep(for: .seconds(timeout))
            self?.timeout(intentID: intentID)
        }
    }

    private func timeout(intentID: UUID) {
        guard let intent = activeIntents[intentID],
              let process = activeProcesses[intentID],
              process.isRunning else { return }
        TaskExecutionPolicy.markTimedOut(intent)
        DiagnosticsStore.shared.record(.taskExecutionTimedOut)
        process.terminate()
    }

    private func finish(intentID: UUID, exitCode: Int) {
        guard let intent = activeIntents.removeValue(forKey: intentID) else { return }
        activeProcesses.removeValue(forKey: intentID)
        runningIntentIDs.remove(intentID)
        if intent.executionState == .running {
            TaskExecutionPolicy.markExited(intent, exitCode: exitCode)
            DiagnosticsStore.shared.record(exitCode == 0 ? .taskExecutionSucceeded : .taskExecutionFailed)
        }
        // M2b-2：任务结束（退出/超时/停止）即登记会话条目——状态、退出码、
        // 末尾脱敏片段（档位裁决在 MobileTaskConsoleService 内）。
        recordConsoleEntry(for: intent)
        let completion = completionHandlers.removeValue(forKey: intentID)
        completion?()
    }
}
