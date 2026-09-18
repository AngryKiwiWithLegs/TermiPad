// M4 交互会话流服务（docs/m4-interactive-session-design.md §2.1/§4）。
// 职责：管理任务的输出流订阅（stream 注册表 + 每订阅游标）、把 T1 捕获
// 管道来的原始输出做脱敏/合帧/游标推进、把推送交给连接层（MobilePairing-
// Service 注册的出口）。
// 红线：推送前必经 OutputRedactor；缓冲纯内存；工具启动永无流；
// openStream 前置 = 每日远程窗口开启（裁决在分发层，本服务只管流）。
import Foundation

@MainActor
final class TaskOutputStreamService: ObservableObject {
    static let shared = TaskOutputStreamService()

    /// 单块推送上限（字节）：帧协议 64KB 上限的余量。
    static let chunkByteLimit = 8 * 1024
    /// 未订阅任务的输出缓冲上限（字节）——超出丢最旧（背压）。
    static let bufferByteLimit = 64 * 1024

    /// 一次订阅：任务 ID + 手机端声明的续传偏移。
    struct Subscription {
        let taskID: UUID
        var consumedOffset: Int
    }

    /// 推送出口：连接层注册（每订阅一个——长连接闭包）。
    typealias PushSink = @MainActor (MobileStreamChunk) -> Void

    /// 任务输出缓冲（全量、纯内存、窗口关闭即清）。
    private struct TaskBuffer {
        var text: String = ""
        var byteCount: Int { text.utf8.count }
    }

    private var buffers: [UUID: TaskBuffer] = [:]
    /// 订阅表：连接标识 → 订阅（同一任务可多设备订阅，各自游标）。
    private var subscriptions: [UUID: Subscription] = [:]
    /// 连接层注册的推送出口（connectionID → sink）。
    private var sinks: [UUID: PushSink] = [:]

    private init() {}

    // MARK: - 连接层注册

    /// 注册推送出口（openTaskStream 分发时调用；连接断开时注销）。
    func registerSink(_ connectionID: UUID, sink: @escaping PushSink) {
        sinks[connectionID] = sink
    }

    func removeSink(_ connectionID: UUID) {
        sinks.removeValue(forKey: connectionID)
        // 连接断开 = 其订阅自然失效（重连时按游标续传）。
        subscriptions.removeValue(forKey: connectionID)
    }

    // MARK: - 订阅生命周期

    /// 订阅任务输出流。返回续传游标（从该偏移之后开始推）。
    /// resumeOffset 由手机端声明（断线重连场景）；nil = 全新订阅——回放
    /// 缓冲尾部 8KB 作为上下文（2026-09-18 实测：任务秒完成时订阅点之后
    /// 无新输出，手机永远"等待输出"；回放尾部让用户立刻看到已完成内容）。
    /// **订阅时立即推送存量**（start→缓冲末尾）：dispatchOutput 只在 T1
    /// 新输出时触发，任务已结束则永不再推——存量必须在此处推（真机
    /// 00:34 实证：游标 30634 被接受但手机一个 chunk 都没收到）。
    func subscribe(connectionID: UUID, taskID: UUID, resumeOffset: Int?,
                   push: @escaping PushSink) -> Int {
        var buffer = buffers[taskID] ?? TaskBuffer()
        buffers[taskID] = buffer
        let start: Int
        if let resumeOffset {
            start = min(resumeOffset, buffer.byteCount)
        } else {
            // 全新订阅：游标定在"尾部 8KB 之前"——回放已有上下文。
            start = max(0, buffer.byteCount - Self.contextReplayBytes)
        }
        subscriptions[connectionID] = Subscription(taskID: taskID, consumedOffset: start)
        // 立即推送存量（脱敏 + 合帧）。
        let totalBytes = buffer.byteCount
        let pending = Self.substring(fromUTF8Offset: start, of: buffer.text)
        if !pending.isEmpty {
            let redacted = OutputRedactor.redact(pending)
            for chunk in Self.splitIntoChunks(redacted, limit: Self.chunkByteLimit) {
                push(MobileStreamChunk(streamID: taskID, offset: start, text: chunk))
            }
        }
        subscriptions[connectionID]?.consumedOffset = totalBytes
        return totalBytes
    }

    /// 全新订阅回放的上下文长度。
    static let contextReplayBytes = 8 * 1024

    /// 退订。
    func unsubscribe(connectionID: UUID) {
        subscriptions.removeValue(forKey: connectionID)
    }

    /// 该任务是否有活跃订阅。
    func hasActiveSubscribers(taskID: UUID) -> Bool {
        subscriptions.values.contains { $0.taskID == taskID }
    }

    // MARK: - 输出分发（T1 捕获钩子调用）

    /// T1 捕获管道每段原始文本进来：入缓冲（截断背压）→ 对每个活跃
    /// 订阅按游标切片 → 脱敏 → 推送。
    func dispatchOutput(taskID: UUID, rawText: String) {
        var buffer = buffers[taskID] ?? TaskBuffer()
        buffer.text += rawText
        // 背压：超限丢最旧（按字符裁剪到限内）。
        if buffer.byteCount > Self.bufferByteLimit {
            buffer.text = String(buffer.text.suffix(Self.bufferByteLimit))
        }
        buffers[taskID] = buffer

        let totalBytes = buffer.byteCount
        for (connectionID, subscription) in subscriptions where subscription.taskID == taskID {
            guard let sink = sinks[connectionID] else { continue }
            let from = max(0, min(subscription.consumedOffset, totalBytes))
            let pending = Self.substring(fromUTF8Offset: from, of: buffer.text)
            guard !pending.isEmpty else { continue }
            let redacted = OutputRedactor.redact(pending)
            // 按块上限切分推送（合帧：多行合并为一块）。
            for chunk in Self.splitIntoChunks(redacted, limit: Self.chunkByteLimit) {
                sink(MobileStreamChunk(
                    streamID: taskID,
                    offset: from,
                    text: chunk))
            }
            subscriptions[connectionID]?.consumedOffset = totalBytes
        }
    }

    /// 任务结束：推一条状态变化（订阅者收到后可关流；缓冲保留供重连）。
    func dispatchStateChange(taskID: UUID, state: String, exitCode: Int?, finishedAt: Date?) {
        for (connectionID, subscription) in subscriptions where subscription.taskID == taskID {
            guard let sink = sinks[connectionID] else { continue }
            sink(MobileStreamChunk(
                streamID: taskID,
                offset: subscription.consumedOffset,
                text: ""))  // 空块 = 刷新信号；状态走专用结构由连接层另发
        }
        // 状态变化经 MobileStreamStateChange 由连接层直发——此处仅通知。
        stateChangeHandlers.forEach { $0(taskID, state, exitCode, finishedAt) }
    }

    /// 连接层注册的状态变化转发器（解耦：服务不知道连接细节）。
    private var stateChangeHandlers: [(UUID, String, Int?, Date?) -> Void] = []
    func addStateChangeHandler(_ handler: @escaping (UUID, String, Int?, Date?) -> Void) {
        stateChangeHandlers.append(handler)
    }

    /// 每日窗口关闭钩子：清全部缓冲 + 退订（设计 §2.3——缓冲随窗口关闭清空）。
    func purgeAll() {
        buffers.removeAll()
        subscriptions.removeAll()
    }

    // MARK: - 文本工具（UTF-8 字节偏移 ↔ String）

    static func substring(fromUTF8Offset offset: Int, of text: String) -> String {
        guard offset > 0 else { return text }
        var byteIndex = text.startIndex
        var consumed = 0
        while consumed < offset, byteIndex < text.endIndex {
            let next = text.index(after: byteIndex)
            consumed += text[byteIndex..<next].utf8.count
            byteIndex = next
        }
        return String(text[byteIndex...])
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
