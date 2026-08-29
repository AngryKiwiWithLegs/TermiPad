import CoreFoundation
import Foundation
import SwiftData

/// 只在同一登录用户的本机进程间传输受限 MCP 请求。它不是网络端口，也不是客户端认证机制。
enum LocalMCPBridgeOperation: String, Codable {
    case listTaskScopes
    case listFixedTasks
    case proposeTask
    case getTaskStatus
    case cancelTask
}

struct LocalMCPBridgeRequest: Codable {
    let operation: LocalMCPBridgeOperation
    let scopeID: UUID?
    let taskKind: String?
    let taskID: UUID?
}

struct LocalMCPScopeSummary: Codable {
    let scopeID: UUID
    let displayName: String
    let status: String
}

struct LocalMCPTaskSummary: Codable {
    let taskKind: String
    let risk: String
    let purpose: String
}

struct LocalMCPTaskState: Codable {
    let taskID: UUID
    let taskKind: String
    let risk: String
    let state: String
    let executionState: String
    let exitCode: Int?
    let executionReason: String?
    let expiresAt: Date?
}

struct LocalMCPBridgeResponse: Codable {
    let success: Bool
    let code: String?
    let message: String
    let scopes: [LocalMCPScopeSummary]?
    let tasks: [LocalMCPTaskSummary]?
    let task: LocalMCPTaskState?

    static func failure(code: String, message: String) -> LocalMCPBridgeResponse {
        .init(success: false, code: code, message: message, scopes: nil, tasks: nil, task: nil)
    }

    static func success(message: String, scopes: [LocalMCPScopeSummary]? = nil, tasks: [LocalMCPTaskSummary]? = nil, task: LocalMCPTaskState? = nil) -> LocalMCPBridgeResponse {
        .init(success: true, code: nil, message: message, scopes: scopes, tasks: tasks, task: task)
    }
}

/// 主应用在持有 SwiftData 容器时安装的本机桥接。stdio 子进程绝不直接打开或竞争应用 store。
@MainActor
final class TaskMCPBridge {
    /// 字符串字面量不依赖实例状态；显式声明 nonisolated 让 stdio 子进程桥接无需跨 actor 访问。
    nonisolated static let serviceName = "com.termipad.app.local-mcp-v1"
    private static var shared: TaskMCPBridge?

    private let modelContext: ModelContext
    private var localPort: CFMessagePort?
    private var runLoopSource: CFRunLoopSource?

    private init(modelContainer: ModelContainer) {
        modelContext = modelContainer.mainContext
    }

    static func install(modelContainer: ModelContainer) {
        guard shared == nil else { return }
        let bridge = TaskMCPBridge(modelContainer: modelContainer)
        guard bridge.installPort() else { return }
        shared = bridge
    }

    private func installPort() -> Bool {
        var context = CFMessagePortContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        var shouldFreeInfo = DarwinBoolean(false)
        guard let port = CFMessagePortCreateLocal(
            kCFAllocatorDefault,
            Self.serviceName as CFString,
            { _, _, data, info in
                guard let data, let info else { return nil }
                let bridge = Unmanaged<TaskMCPBridge>.fromOpaque(info).takeUnretainedValue()
                let request = data as Data
                let response = bridge.handle(request)
                return Unmanaged.passRetained(response as CFData)
            },
            &context,
            &shouldFreeInfo
        ) else {
            return false
        }
        guard let source = CFMessagePortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else { return false }
        localPort = port
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        return true
    }

    func handle(_ data: Data) -> Data {
        guard let request = try? JSONDecoder().decode(LocalMCPBridgeRequest.self, from: data) else {
            return encode(.failure(code: "invalid_bridge_request", message: "Local MCP request is malformed."))
        }
        guard TaskMCPSettings.isLocalMCPEnabled else {
            return encode(.failure(code: "local_mcp_disabled", message: "Local MCP is disabled in TermiPad on this Mac."))
        }

        let response: LocalMCPBridgeResponse
        switch request.operation {
        case .listTaskScopes:
            let scopes = (try? modelContext.fetch(FetchDescriptor<TaskProjectScope>())) ?? []
            let summaries = scopes.sorted { $0.createdAt < $1.createdAt }.map { scope in
                LocalMCPScopeSummary(
                    scopeID: scope.id,
                    displayName: String(scope.displayName.replacingOccurrences(of: "\n", with: " ").prefix(80)),
                    status: scope.isRevoked ? "revoked" : (scope.directoryIsAvailable ? "available" : "unavailable")
                )
            }
            DiagnosticsStore.shared.record(.mcpToolListed)
            response = .success(message: "Local project scopes returned.", scopes: summaries)
        case .listFixedTasks:
            let tasks = FixedTaskCatalog.definitions.map {
                LocalMCPTaskSummary(taskKind: $0.kind.rawValue, risk: $0.risk.rawValue, purpose: $0.purposeEnglish)
            }
            DiagnosticsStore.shared.record(.mcpToolListed)
            response = .success(message: "Fixed local tasks returned.", tasks: tasks)
        case .proposeTask:
            response = propose(scopeID: request.scopeID, taskKind: request.taskKind)
        case .getTaskStatus:
            response = status(taskID: request.taskID)
        case .cancelTask:
            response = cancel(taskID: request.taskID)
        }
        return encode(response)
    }

    private func propose(scopeID: UUID?, taskKind rawValue: String?) -> LocalMCPBridgeResponse {
        guard let scopeID, let rawValue, let kind = TaskKind(rawValue: rawValue) else {
            return .failure(code: "invalid_arguments", message: "A fixed task kind and local scope ID are required.")
        }
        let scopes = (try? modelContext.fetch(FetchDescriptor<TaskProjectScope>())) ?? []
        guard let scope = scopes.first(where: { $0.id == scopeID }) else {
            return .failure(code: "project_scope_unknown", message: "The requested project scope is not available on this Mac.")
        }
        guard !scope.isRevoked, scope.directoryIsAvailable else {
            return .failure(code: "project_scope_unavailable", message: "The requested project scope is unavailable or revoked.")
        }
        let intent = TaskIntentPolicy.makeIntent(scope: scope, kind: kind)
        modelContext.insert(intent)
        do {
            try modelContext.save()
            DiagnosticsStore.shared.record(.mcpTaskProposed)
            return .success(message: "Task awaits local review in TermiPad.", task: summary(for: intent))
        } catch {
            return .failure(code: "local_store_save_failed", message: "TermiPad could not save the local task proposal.")
        }
    }

    private func status(taskID: UUID?) -> LocalMCPBridgeResponse {
        guard let taskID else { return .failure(code: "invalid_arguments", message: "A task ID is required.") }
        let intents = (try? modelContext.fetch(FetchDescriptor<TaskIntent>())) ?? []
        guard let intent = intents.first(where: { $0.id == taskID }) else {
            return .failure(code: "task_unknown", message: "The requested task is not available on this Mac.")
        }
        // 双层审计：协议层记 MCP 客户端读取次数（mcpTaskStatusRead），
        // task 域记 task 结果被读取（taskExecutionResultRead）。
        // 同一次读取产生两个 event 是有意义的：可分别分析 MCP 流量和 task 状态查询频率。
        DiagnosticsStore.shared.record(.mcpTaskStatusRead)
        DiagnosticsStore.shared.record(.taskExecutionResultRead)
        return .success(message: "Minimum task state returned.", task: summary(for: intent))
    }

    private func cancel(taskID: UUID?) -> LocalMCPBridgeResponse {
        guard let taskID else { return .failure(code: "invalid_arguments", message: "A task ID is required.") }
        let intents = (try? modelContext.fetch(FetchDescriptor<TaskIntent>())) ?? []
        guard let intent = intents.first(where: { $0.id == taskID }) else {
            return .failure(code: "task_unknown", message: "The requested task is not available on this Mac.")
        }
        guard intent.executionState != .running else {
            return .failure(code: "task_running_local_stop_required", message: "This task is running locally and must be stopped from the TermiPad workbench on this Mac.")
        }
        TaskIntentPolicy.cancel(intent)
        do {
            try modelContext.save()
            DiagnosticsStore.shared.record(.mcpTaskCancelled)
            return .success(message: "Local task cancellation recorded.", task: summary(for: intent))
        } catch {
            return .failure(code: "local_store_save_failed", message: "TermiPad could not save the task cancellation.")
        }
    }

    private func summary(for intent: TaskIntent) -> LocalMCPTaskState {
        .init(
            taskID: intent.id,
            taskKind: intent.kindRawValue,
            risk: intent.risk.rawValue,
            state: intent.state.rawValue,
            executionState: intent.executionState.rawValue,
            exitCode: intent.executionExitCode,
            executionReason: intent.executionRejectionReason?.rawValue,
            expiresAt: intent.expiresAt
        )
    }

    private func encode(_ response: LocalMCPBridgeResponse) -> Data {
        (try? JSONEncoder().encode(response)) ?? Data()
    }
}

protocol LocalMCPBridgeTransport {
    func send(_ request: LocalMCPBridgeRequest) -> LocalMCPBridgeResponse
}

struct CFMessagePortMCPBridgeTransport: LocalMCPBridgeTransport {
    func send(_ request: LocalMCPBridgeRequest) -> LocalMCPBridgeResponse {
        guard let requestData = try? JSONEncoder().encode(request),
              let port = CFMessagePortCreateRemote(kCFAllocatorDefault, TaskMCPBridge.serviceName as CFString) else {
            return .failure(code: "local_bridge_unavailable", message: "Open TermiPad on this Mac before using its local MCP service.")
        }
        var reply: Unmanaged<CFData>?
        let replyMode: CFString = CFRunLoopMode.defaultMode.rawValue as CFString
        let status = CFMessagePortSendRequest(port, 0, requestData as CFData, 5, 5, replyMode, &reply)
        guard status == kCFMessagePortSuccess, let replyData = reply?.takeRetainedValue() else {
            return .failure(code: "local_bridge_unavailable", message: "TermiPad local MCP bridge is unavailable.")
        }
        let responseData = replyData as Data
        return (try? JSONDecoder().decode(LocalMCPBridgeResponse.self, from: responseData))
            ?? .failure(code: "local_bridge_invalid_response", message: "TermiPad local MCP bridge returned an invalid response.")
    }
}
