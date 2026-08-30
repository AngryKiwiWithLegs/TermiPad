import Foundation

/// T2 仅实现同一台 Mac 上的 JSON-RPC stdio 子集。它不打开 store、不执行任务；所有状态操作必须经由已运行的 TermiPad 主应用桥接。
final class TermiPadMCPStdIORuntime {
    /// 仅接受已逐项核验过的 stdio MCP 协议版本；拒绝任何未知版本，避免以宽松协商掩盖协议差异。
    private static let supportedProtocolVersions: Set<String> = ["2025-03-26", "2025-11-25"]
    private let bridge: LocalMCPBridgeTransport
    private var didInitialize = false
    private var requestDates: [Date] = []

    init(bridge: LocalMCPBridgeTransport = CFMessagePortMCPBridgeTransport()) {
        self.bridge = bridge
    }

    static func run() {
        let runtime = TermiPadMCPStdIORuntime()
        while let line = readLine(strippingNewline: true) {
            guard let data = line.data(using: .utf8),
                  let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let response = runtime.respond(to: request) else { continue }
            write(response)
        }
    }

    func respond(to request: [String: Any], now: Date = Date()) -> [String: Any]? {
        guard request["jsonrpc"] as? String == "2.0", let method = request["method"] as? String else {
            return protocolError(id: request["id"], code: -32600, message: "Invalid JSON-RPC request.")
        }
        if method == "notifications/initialized" {
            didInitialize = true
            return nil
        }
        guard let id = request["id"] else { return nil }
        if method == "initialize" { return initialize(id: id, request: request) }
        guard didInitialize else {
            return protocolError(id: id, code: -32002, message: "MCP initialization is required before tool operations.")
        }
        guard permitRequest(at: now) else {
            return toolError(id: id, code: "rate_limited", message: "Local MCP request rate limit reached; retry later.")
        }
        switch method {
        case "ping":
            return result(id: id, value: [:])
        case "tools/list":
            return result(id: id, value: ["tools": toolDefinitions])
        case "tools/call":
            return callTool(id: id, params: request["params"] as? [String: Any] ?? [:])
        default:
            return protocolError(id: id, code: -32601, message: "Unknown MCP method: \(method).")
        }
    }

    private func initialize(id: Any, request: [String: Any]) -> [String: Any] {
        let params = request["params"] as? [String: Any] ?? [:]
        guard let version = params["protocolVersion"] as? String, Self.supportedProtocolVersions.contains(version) else {
            let supported = Self.supportedProtocolVersions.sorted().joined(separator: ", ")
            return protocolError(id: id, code: -32602, message: "Unsupported protocol version. Supported: \(supported).")
        }
        return result(id: id, value: [
            "protocolVersion": version,
            "capabilities": ["tools": [:]],
            "serverInfo": ["name": "termipad-local", "version": UpdateCheckService.currentAppVersion()],
            "instructions": "This is a local-only, user-enabled TermiPad service. It never accepts shell commands, paths, variables, files, or terminal output. Task proposals require local Mac review before approval or execution."
        ])
    }

    private func callTool(id: Any, params: [String: Any]) -> [String: Any] {
        guard let name = params["name"] as? String else {
            return protocolError(id: id, code: -32602, message: "Tool name is required.")
        }
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        let response: LocalMCPBridgeResponse
        switch name {
        case "list_task_scopes":
            guard arguments.isEmpty else { return invalidArguments(id: id) }
            response = bridge.send(.init(operation: .listTaskScopes, scopeID: nil, taskKind: nil, taskID: nil))
        case "list_fixed_tasks":
            guard arguments.isEmpty else { return invalidArguments(id: id) }
            response = bridge.send(.init(operation: .listFixedTasks, scopeID: nil, taskKind: nil, taskID: nil))
        case "propose_task":
            guard Set(arguments.keys) == Set(["scope_id", "task_kind"]),
                  let scopeID = uuid(arguments["scope_id"]),
                  let taskKind = arguments["task_kind"] as? String,
                  TaskKind(rawValue: taskKind) != nil else { return invalidArguments(id: id) }
            response = bridge.send(.init(operation: .proposeTask, scopeID: scopeID, taskKind: taskKind, taskID: nil))
        case "get_task_status":
            guard Set(arguments.keys) == Set(["task_id"]), let taskID = uuid(arguments["task_id"]) else { return invalidArguments(id: id) }
            response = bridge.send(.init(operation: .getTaskStatus, scopeID: nil, taskKind: nil, taskID: taskID))
        case "cancel_task":
            guard Set(arguments.keys) == Set(["task_id"]), let taskID = uuid(arguments["task_id"]) else { return invalidArguments(id: id) }
            response = bridge.send(.init(operation: .cancelTask, scopeID: nil, taskKind: nil, taskID: taskID))
        default:
            return protocolError(id: id, code: -32601, message: "Unknown TermiPad tool: \(name).")
        }
        return response.success ? toolSuccess(id: id, response: response) : toolError(id: id, code: response.code ?? "local_bridge_error", message: response.message)
    }

    private func permitRequest(at now: Date) -> Bool {
        requestDates = requestDates.filter { now.timeIntervalSince($0) < 60 }
        guard requestDates.count < 30 else { return false }
        requestDates.append(now)
        return true
    }

    private var toolDefinitions: [[String: Any]] {
        [
            tool(name: "list_task_scopes", description: "List opaque, user-selected local project scopes by display name and availability. Paths are never returned.", properties: [:], required: []),
            tool(name: "list_fixed_tasks", description: "List TermiPad fixed local task kinds, their risk class, and purpose. Commands and arguments are never returned.", properties: [:], required: []),
            tool(name: "propose_task", description: "Create a pending local review task for one fixed task kind and one opaque project scope. It cannot approve or execute a task.", properties: ["scope_id": ["type": "string"], "task_kind": ["type": "string", "enum": TaskKind.allCases.map(\.rawValue)]], required: ["scope_id", "task_kind"]),
            tool(name: "get_task_status", description: "Read the minimum state of a previously proposed local task. No output, command, path, variables, or project data is returned.", properties: ["task_id": ["type": "string"]], required: ["task_id"]),
            tool(name: "cancel_task", description: "Cancel a pending or approved local task before it starts. Running tasks must be stopped in the local TermiPad workbench. This tool never accepts a command.", properties: ["task_id": ["type": "string"]], required: ["task_id"])
        ]
    }

    private func tool(name: String, description: String, properties: [String: Any], required: [String]) -> [String: Any] {
        ["name": name, "description": description, "inputSchema": ["type": "object", "properties": properties, "required": required, "additionalProperties": false]]
    }

    private func uuid(_ value: Any?) -> UUID? {
        guard let string = value as? String else { return nil }
        return UUID(uuidString: string)
    }

    private func invalidArguments(id: Any) -> [String: Any] {
        toolError(id: id, code: "invalid_arguments", message: "Arguments do not match this tool's fixed schema.")
    }

    private func toolSuccess(id: Any, response: LocalMCPBridgeResponse) -> [String: Any] {
        let value = structured(response)
        return result(id: id, value: ["content": [["type": "text", "text": encodedText(value)]], "structuredContent": value, "isError": false])
    }

    private func toolError(id: Any, code: String, message: String) -> [String: Any] {
        result(id: id, value: ["content": [["type": "text", "text": message]], "structuredContent": ["code": code], "isError": true])
    }

    private func structured(_ response: LocalMCPBridgeResponse) -> [String: Any] {
        var value: [String: Any] = ["message": response.message]
        if let scopes = response.scopes {
            value["scopes"] = scopes.map { ["scope_id": $0.scopeID.uuidString, "display_name": $0.displayName, "status": $0.status] }
        }
        if let tasks = response.tasks {
            value["tasks"] = tasks.map { ["task_kind": $0.taskKind, "risk": $0.risk, "purpose": $0.purpose] }
        }
        if let task = response.task {
            var taskValue: [String: Any] = ["task_id": task.taskID.uuidString, "task_kind": task.taskKind, "risk": task.risk, "state": task.state, "execution_state": task.executionState]
            if let exitCode = task.exitCode { taskValue["exit_code"] = exitCode }
            if let reason = task.executionReason { taskValue["execution_reason"] = reason }
            if let expiresAt = task.expiresAt { taskValue["expires_at"] = ISO8601DateFormatter().string(from: expiresAt) }
            value["task"] = taskValue
        }
        return value
    }

    private func protocolError(id: Any?, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
    }

    private func result(id: Any, value: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": value]
    }

    private func encodedText(_ value: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    private static func write(_ value: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
