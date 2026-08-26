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

/// T1 的唯一进程入口。任务以空 stdin/stdout/stderr 运行，结果仅保留退出码和固定状态。
@MainActor
final class TaskExecutionCoordinator: ObservableObject {
    static let shared = TaskExecutionCoordinator()

    @Published private(set) var runningIntentIDs: Set<UUID> = []
    private var activeProcesses: [UUID: Process] = [:]
    private var activeIntents: [UUID: TaskIntent] = [:]
    private var completionHandlers: [UUID: () -> Void] = [:]

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
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let intentID = intent.id
        process.terminationHandler = { [weak self, intentID] completedProcess in
            let exitCode = completedProcess.terminationStatus
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
        let completion = completionHandlers.removeValue(forKey: intentID)
        completion?()
    }
}
