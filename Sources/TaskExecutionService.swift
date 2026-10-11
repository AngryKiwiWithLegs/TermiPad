import Combine
import Foundation

/// Holder for the bytes of a cut-off character, kept between two reads of a task's capture pipe.
/// Touched only by that pipe's read handler, which runs on one serial queue.
private final class UnfinishedUTF8Bytes: @unchecked Sendable {
    var bytes = Data()
}

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

/// T1 purely local pre-check and lifecycle state machine. Nothing outside the fixed catalog can form an execution request.
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

/// The only process entry point of T1. Tasks run with empty stdin; stdout/stderr are discarded by default
/// (minimal visibility — the behavior before M2b-2), keeping only the exit code and fixed states.
/// M2b-2 (docs/m2b-remote-task-console-design.md §5.4): when the output visibility is ≥
/// restricted, stdout/stderr are captured into an **in-memory only** ring buffer (capped at
/// 32 KB / 400 lines, whichever comes first) — so the task session can return the tail snippet (after redaction).
/// The capture buffer is never written to disk, backups, or diagnostics.
@MainActor
final class TaskExecutionCoordinator: ObservableObject {
    static let shared = TaskExecutionCoordinator()

    /// Output capture buffer limits (bytes / lines, whichever comes first — beyond that, output is only counted and discarded).
    static let outputCaptureByteLimit = 32 * 1024
    static let outputCaptureLineLimit = 400

    /// In-memory only output capture for a single task (array of lines; the ring naturally keeps the tail; the counts are not lost to truncation).
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

        /// At most the last 32 lines — this is exactly the slice returned at the restricted level.
        func tailSnippet() -> String {
            lines.suffix(32).joined(separator: "\n")
        }
    }

    @Published private(set) var runningIntentIDs: Set<UUID> = []
    private var activeProcesses: [UUID: Process] = [:]
    private var activeIntents: [UUID: TaskIntent] = [:]
    private var completionHandlers: [UUID: () -> Void] = [:]
    /// Tasks being captured when the visibility is ≥ restricted (intentID → buffer + receiving pipe).
    private var outputCaptures: [UUID: OutputCapture] = [:]
    private var outputPipes: [UUID: Pipe] = [:]
    private var outputSources: [UUID: DispatchSourceRead] = [:]
    /// M4-3: stdin pipes of tasks that declare interaction points (the phone's selection is written back to the process).
    private var inputPipes: [UUID: Pipe] = [:]
    /// The interaction points declared by the task (copied from the definition at start).
    private var interactionPoints: [UUID: [TaskInteractionPoint]] = [:]
    /// Interaction points already triggered (each interaction point fires only once per task).
    private var triggeredInteractions: [UUID: Set<Int>] = [:]

    /// Whether to capture output (visibility decision — reads the authoritative setting on the Mac).
    var capturesOutput: Bool {
        MobileTaskConsoleService.shared.currentVisibility != .minimal
    }

    /// M2b-3: retrieve the active intent when the phone cancels a task (stopping the process needs the intent object).
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
            // minimal visibility: keep the original behavior — discard all stdout/stderr.
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }
        // M4-3: the task declares interaction points → stdin uses a pipe (the phone's selection is written back);
        // tasks that declare none keep empty input (the red line is unchanged).
        if let points = intent.kind.flatMap({ FixedTaskCatalog.definition(for: $0)?.interactionPoints }),
           !points.isEmpty {
            let inputPipe = Pipe()
            process.standardInput = inputPipe
            inputPipes[intent.id] = inputPipe
            interactionPoints[intent.id] = points
            triggeredInteractions[intent.id] = []
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
        // Entry registration is done in one place, finish() (the path every terminationHandler goes through) —
        // registering early here would be overwritten with an empty snippet by finish's second registration.
    }

    /// Visibility ≥ restricted: stdout+stderr are captured together into an in-memory only ring buffer.
    /// Line-level reads (DispatchSourceRead), stopping at whichever of the byte/line limits comes first —
    /// the buffer is never written to disk; when the task ends it is removed from the pipe dictionary (the buffer is kept until the entry is registered).
    private func attachOutputCapture(for intentID: UUID, to process: Process) {
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        outputCaptures[intentID] = OutputCapture()
        outputPipes[intentID] = pipe
        let source = DispatchSource.makeReadSource(
            fileDescriptor: pipe.fileHandleForReading.fileDescriptor,
            queue: DispatchQueue(label: "com.termipad.task-output", qos: .utility))
        // Bytes of a character that a read cut in half. Only the event handler touches it, on the source's serial queue.
        let unfinishedCharacter = UnfinishedUTF8Bytes()
        source.setEventHandler { [weak self] in
            let chunk = pipe.fileHandleForReading.availableData
            guard !chunk.isEmpty else {
                source.cancel()
                return
            }
            guard let self else { return }
            // A read can end in the middle of a multi-byte character. Decoding each read on its own then failed
            // and the whole read was lost, so the unfinished bytes wait for the read that completes them.
            unfinishedCharacter.bytes.append(chunk)
            let data = TaskExecutionCoordinator.takeCompleteUTF8Prefix(from: &unfinishedCharacter.bytes)
            guard !data.isEmpty else { return }
            Task { @MainActor in
                let text = String(data: data, encoding: .utf8) ?? ""
                for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                    self.outputCaptures[intentID]?.append(String(line))
                }
                // M4 streaming dispatch: every captured piece of text is pushed to active subscribers right away
                // (TaskOutputStreamService handles cursors, framing, redaction, and backpressure internally).
                TaskOutputStreamService.shared.dispatchOutput(
                    taskID: intentID, rawText: text)
                // M4-3 interaction point detection: output matches a declared pattern → push an interaction request.
                self.checkInteractionPoints(intentID: intentID, output: text)
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

    /// Removes and returns the part of `buffer` that does not end inside a UTF-8 sequence. Only the bytes of an
    /// unfinished trailing sequence (at most 3) stay behind; anything else, valid or not, is returned unchanged.
    nonisolated static func takeCompleteUTF8Prefix(from buffer: inout Data) -> Data {
        let bytes = [UInt8](buffer)
        var completeCount = bytes.count
        // An unfinished sequence is a lead byte followed by fewer continuation bytes than it announces,
        // so its lead byte is one of the last three bytes.
        for index in stride(from: bytes.count - 1, through: max(bytes.count - 3, 0), by: -1) {
            let byte = bytes[index]
            if byte & 0b1100_0000 == 0b1000_0000 { continue }  // continuation byte: keep looking for its lead
            let sequenceLength: Int
            if byte & 0b1110_0000 == 0b1100_0000 {
                sequenceLength = 2
            } else if byte & 0b1111_0000 == 0b1110_0000 {
                sequenceLength = 3
            } else if byte & 0b1111_1000 == 0b1111_0000 {
                sequenceLength = 4
            } else {
                sequenceLength = 1
            }
            if bytes.count - index < sequenceLength { completeCount = index }
            break
        }
        buffer = Data(bytes[completeCount...])
        return Data(bytes[..<completeCount])
    }

    /// M4-3 interaction point detection: output matches a declared pattern → push an interaction request to the phone (once per point).
    private func checkInteractionPoints(intentID: UUID, output: String) {
        guard let points = interactionPoints[intentID],
              let triggered = triggeredInteractions[intentID] else { return }
        for (index, point) in points.enumerated() where !triggered.contains(index) {
            guard output.range(of: point.triggerPattern, options: .regularExpression) != nil else { continue }
            triggeredInteractions[intentID]?.insert(index)
            MobilePairingService.diagMac("Task interaction point triggered: \(point.prompt.prefix(20))…")
            TaskOutputStreamService.shared.dispatchInteraction(
                taskID: intentID,
                prompt: point.prompt,
                options: point.options)
            return
        }
    }

    /// Write the phone's selection back to the process's stdin (only tasks that declare interaction points have a pipe).
    func respondInteraction(intentID: UUID, selection: String) {
        guard let pipe = inputPipes[intentID],
              interactionPoints[intentID] != nil else { return }
        // The process can exit just before its bookkeeping is cleared in finish(). Writing to its closed pipe with
        // the non-throwing write would raise an exception and take the app down, so skip a finished process and
        // use the throwing variant.
        guard activeProcesses[intentID]?.isRunning == true else { return }
        let data = Data("\(selection)\n".utf8)
        guard (try? pipe.fileHandleForWriting.write(contentsOf: data)) != nil else { return }
        DiagnosticsStore.shared.record(.mobileInteractionResponded)
    }

    /// Landing the task lifecycle: status + exit code + (when the visibility is ≥ restricted) the redacted
    /// tail snippet are registered into the phone's session entry feed (MobileTaskConsoleService makes the visibility decision).
    private func recordConsoleEntry(for intent: TaskIntent) {
        let title = intent.kind.flatMap { kind in
            FixedTaskCatalog.definition(for: kind)?.purpose(language: .current)
        } ?? "Fixed task"
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
        inputPipes.removeValue(forKey: intentID)
        interactionPoints.removeValue(forKey: intentID)
        triggeredInteractions.removeValue(forKey: intentID)
        if intent.executionState == .running {
            TaskExecutionPolicy.markExited(intent, exitCode: exitCode)
            DiagnosticsStore.shared.record(exitCode == 0 ? .taskExecutionSucceeded : .taskExecutionFailed)
        }
        // M2b-2: as soon as a task ends (exit / timeout / stop) the session entry is registered — status, exit code,
        // and the redacted tail snippet (the visibility decision is inside MobileTaskConsoleService).
        recordConsoleEntry(for: intent)
        let completion = completionHandlers.removeValue(forKey: intentID)
        completion?()
    }
}
