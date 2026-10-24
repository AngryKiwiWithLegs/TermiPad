// M4 interactive session stream service (docs/m4-interactive-session-design.md §2.1/§4).
// Responsibilities: manage output stream subscriptions for tasks (stream registry + a cursor per subscription), take the raw output from the T1 capture
// pipe through redaction / framing / cursor advancement, and hand the pushes to the connection layer (the outlets MobilePairing-
// Service registers).
// Red lines: everything passes through OutputRedactor before being pushed; buffers are memory only; tool launches never have a stream;
// precondition for openStream = the daily remote window is open (decided in the dispatch layer; this service only manages streams).
import Foundation

@MainActor
final class TaskOutputStreamService: ObservableObject {
    static let shared = TaskOutputStreamService()

    /// Per-chunk push limit (bytes): headroom under the frame protocol's 64KB limit.
    static let chunkByteLimit = 8 * 1024
    /// Output buffer limit for unsubscribed tasks (bytes) — beyond it the oldest data is dropped (backpressure).
    static let bufferByteLimit = 64 * 1024

    /// One subscription: task ID + the resume offset declared by the phone.
    struct Subscription {
        let taskID: UUID
        var consumedOffset: Int
    }

    /// Push outlet: registered by the connection layer (one per subscription — a long-lived connection closure).
    typealias PushSink = @MainActor (MobileStreamChunk) -> Void

    /// Task output buffer (memory only, cleared when the window closes).
    private struct TaskBuffer {
        var text: String = ""
        /// Bytes already dropped from the front by backpressure. Cursors and chunk offsets count from the start
        /// of the task's output, so position `p` in the stream is byte `p - droppedByteCount` of `text`.
        var droppedByteCount = 0
        var byteCount: Int { text.utf8.count }
        /// Stream offset just past the last buffered byte.
        var endOffset: Int { droppedByteCount + byteCount }
    }

    private var buffers: [UUID: TaskBuffer] = [:]
    /// Subscription table: connection identifier → subscription (several devices can subscribe to the same task, each with its own cursor).
    private var subscriptions: [UUID: Subscription] = [:]
    /// Push outlets registered by the connection layer (connectionID → sink).
    private var sinks: [UUID: PushSink] = [:]
    /// Interaction request outlets registered by the connection layer (connectionID → sink), released with the push outlet.
    private var interactionSinks: [UUID: (MobileStreamInteraction) -> Void] = [:]

    /// Same test pattern as MobileTaskConsoleService/RemoteAllowWindow: the singleton uses
    /// shared state, and tests inject independent instances.
    init() {}

    // MARK: - Connection layer registration

    /// Register a push outlet (called when openTaskStream is dispatched; unregistered when the connection drops).
    func registerSink(_ connectionID: UUID, sink: @escaping PushSink) {
        sinks[connectionID] = sink
    }

    func removeSink(_ connectionID: UUID) {
        sinks.removeValue(forKey: connectionID)
        interactionSinks.removeValue(forKey: connectionID)
        // Connection dropped = its subscription naturally lapses (resumed by cursor on reconnect).
        subscriptions.removeValue(forKey: connectionID)
    }

    // MARK: - Subscription lifecycle

    /// Subscribe to a task's output stream. Returns the resume cursor (pushing starts after that offset).
    /// resumeOffset is declared by the phone (reconnect after a drop); nil = a brand-new subscription — replay
    /// the last 8KB of the buffer as context (2026-09-18 test: when a task finishes within a second there is no new output after the
    /// subscription point and the phone "waits for output" forever; replaying the tail lets the user see the finished content right away).
    /// **Push the backlog immediately on subscribe** (start → end of buffer): dispatchOutput only fires on new T1
    /// output, so once the task has ended nothing is pushed again — the backlog must be pushed here (confirmed on a real device
    /// at 00:34: cursor 30634 was accepted but the phone never received a single chunk).
    func subscribe(connectionID: UUID, taskID: UUID, resumeOffset: Int?,
                   push: @escaping PushSink) -> Int {
        var buffer = buffers[taskID] ?? TaskBuffer()
        buffers[taskID] = buffer
        // Output the buffer has already dropped cannot be replayed, so no cursor starts before it.
        let start: Int
        if let resumeOffset {
            start = max(buffer.droppedByteCount, min(resumeOffset, buffer.endOffset))
        } else {
            // Brand-new subscription: put the cursor "8KB before the tail" — replay the existing context.
            start = max(buffer.droppedByteCount, buffer.endOffset - Self.contextReplayBytes)
        }
        subscriptions[connectionID] = Subscription(taskID: taskID, consumedOffset: start)
        // Push the backlog immediately (redaction + framing).
        let totalBytes = buffer.endOffset
        MobilePairingService.diagMac("Stream subscribe: task=\(taskID) buffer=\(totalBytes)B replay start=\(start) resume=\(resumeOffset.map(String.init) ?? "nil")")
        let pending = Self.substring(fromUTF8Offset: start - buffer.droppedByteCount, of: buffer.text)
        if !pending.isEmpty {
            let redacted = OutputRedactor.redact(pending)
            MobilePairingService.diagMac("Stream replay: pushing \(redacted.utf8.count)B (start \(start))")
            for chunk in Self.splitIntoChunks(redacted, limit: Self.chunkByteLimit) {
                push(MobileStreamChunk(streamID: taskID, offset: start, text: chunk))
            }
        } else {
            MobilePairingService.diagMac("Stream replay: backlog empty (buffer \(totalBytes)B start \(start))")
        }
        subscriptions[connectionID]?.consumedOffset = totalBytes
        return totalBytes
    }

    /// Context length replayed for a brand-new subscription.
    static let contextReplayBytes = 8 * 1024

    /// Unsubscribe.
    func unsubscribe(connectionID: UUID) {
        subscriptions.removeValue(forKey: connectionID)
    }

    /// Whether the task has active subscriptions.
    func hasActiveSubscribers(taskID: UUID) -> Bool {
        subscriptions.values.contains { $0.taskID == taskID }
    }

    // MARK: - Output dispatch (called by the T1 capture hook)

    /// Every piece of raw text from the T1 capture pipe comes in here: into the buffer (truncating backpressure) → for each active
    /// subscription, slice by cursor → redact → push.
    func dispatchOutput(taskID: UUID, rawText: String) {
        if buffers[taskID] == nil {
            MobilePairingService.diagMac("Stream dispatch: first output of the task buffered (\(rawText.utf8.count)B)")
        }
        var buffer = buffers[taskID] ?? TaskBuffer()
        buffer.text += rawText
        // Backpressure: drop the oldest data beyond the limit (trim by characters to fit). What was dropped is
        // remembered, so the cursors keep counting from the start of the output. Without that, a cursor at the
        // old end of a full buffer would sit at the end of the trimmed buffer too, and nothing after the first
        // 64 KB would ever be pushed.
        if buffer.byteCount > Self.bufferByteLimit {
            let byteCountBeforeTrim = buffer.byteCount
            buffer.text = String(buffer.text.suffix(Self.bufferByteLimit))
            buffer.droppedByteCount += byteCountBeforeTrim - buffer.byteCount
        }
        buffers[taskID] = buffer

        let totalBytes = buffer.endOffset
        for (connectionID, subscription) in subscriptions where subscription.taskID == taskID {
            guard let sink = sinks[connectionID] else { continue }
            let from = max(buffer.droppedByteCount, min(subscription.consumedOffset, totalBytes))
            let pending = Self.substring(fromUTF8Offset: from - buffer.droppedByteCount, of: buffer.text)
            guard !pending.isEmpty else { continue }
            let redacted = OutputRedactor.redact(pending)
            // Split pushes by the chunk limit (framing: several lines are merged into one chunk).
            for chunk in Self.splitIntoChunks(redacted, limit: Self.chunkByteLimit) {
                sink(MobileStreamChunk(
                    streamID: taskID,
                    offset: from,
                    text: chunk))
            }
            subscriptions[connectionID]?.consumedOffset = totalBytes
        }
    }

    /// Task ended: push one state change (subscribers can close the stream on receiving it; the buffer is kept for reconnects).
    func dispatchStateChange(taskID: UUID, state: String, exitCode: Int?, finishedAt: Date?) {
        for (connectionID, subscription) in subscriptions where subscription.taskID == taskID {
            guard let sink = sinks[connectionID] else { continue }
            sink(MobileStreamChunk(
                streamID: taskID,
                offset: subscription.consumedOffset,
                text: ""))  // empty chunk = refresh signal; the state travels in its own struct, sent separately by the connection layer
        }
        // State changes are sent directly by the connection layer via MobileStreamStateChange — this is only a notification.
        stateChangeHandlers.forEach { $0(taskID, state, exitCode, finishedAt) }
    }

    /// M4-3 interaction request push: the task needs a decision → push to the task's active subscribers.
    func dispatchInteraction(taskID: UUID, prompt: String, options: [String]) {
        let interaction = MobileStreamInteraction(
            streamID: taskID, prompt: prompt, options: options)
        for (connectionID, subscription) in subscriptions where subscription.taskID == taskID {
            guard let sink = sinks[connectionID] else { continue }
            sink(MobileStreamChunk(streamID: taskID, offset: 0, text: ""))  // refresh signal
            interactionSinks[connectionID]?(interaction)
        }
    }

    /// Interaction request outlet registered by the connection layer (one per stream connection).
    /// Keyed by connection so it is released together with the push outlet in `removeSink`.
    func registerInteractionSink(_ connectionID: UUID, sink: @escaping (MobileStreamInteraction) -> Void) {
        interactionSinks[connectionID] = sink
    }

    /// State change forwarder registered by the connection layer (decoupling: the service knows no connection details).
    private var stateChangeHandlers: [(UUID, String, Int?, Date?) -> Void] = []
    func addStateChangeHandler(_ handler: @escaping (UUID, String, Int?, Date?) -> Void) {
        stateChangeHandlers.append(handler)
    }

    /// Daily window close hook: clear all buffers + unsubscribe (design §2.3 — buffers are cleared when the window closes).
    func purgeAll() {
        buffers.removeAll()
        subscriptions.removeAll()
    }

    // MARK: - Text utilities (UTF-8 byte offset ↔ String)

    /// The text from the first character that starts at or after `offset` UTF-8 bytes.
    /// Jumps straight to the byte offset; walking the buffer character by character on every piece of output
    /// cost time proportional to the whole buffer.
    static func substring(fromUTF8Offset offset: Int, of text: String) -> String {
        guard offset > 0 else { return text }
        let utf8 = text.utf8
        guard let target = utf8.index(utf8.startIndex, offsetBy: offset, limitedBy: utf8.endIndex),
              target < utf8.endIndex else {
            return ""
        }
        // String index arithmetic rounds an index inside a character down to that character's start, so these
        // two steps find the character containing `target`. An offset inside a character moves forward to the
        // next character, as the character walk did.
        let characterEnd = text.index(after: target)
        let characterStart = text.index(before: characterEnd)
        let start = characterStart == target ? target : characterEnd
        return String(text[start...])
    }

    static func splitIntoChunks(_ text: String, limit: Int) -> [String] {
        guard text.utf8.count > limit else { return [text] }
        var chunks: [String] = []
        var current = ""
        var currentBytes = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let lineText = String(line) + "\n"
            let lineBytes = lineText.utf8.count
            if currentBytes + lineBytes > limit, !current.isEmpty {
                chunks.append(current)
                current = ""
                currentBytes = 0
            }
            current += lineText
            currentBytes += lineBytes
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}
