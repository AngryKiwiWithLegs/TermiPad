import XCTest
@testable import TermiPad

final class MCPStdIORuntimeTests: XCTestCase {
    func testProtocolRequiresInitializationBeforeOperations() {
        let runtime = TermiPadMCPStdIORuntime(bridge: MockBridge())
        let response = runtime.respond(to: request(id: 1, method: "tools/list"))
        XCTAssertEqual(errorCode(response), -32002)
    }

    func testProtocolNegotiatesVerifiedOpenCodeVersionBeforeToolOperations() {
        let runtime = TermiPadMCPStdIORuntime(bridge: MockBridge())
        let response = runtime.respond(to: request(
            id: 1,
            method: "initialize",
            params: ["protocolVersion": "2025-11-25", "capabilities": [:], "clientInfo": ["name": "opencode", "version": "1.14.33"]]
        ))
        XCTAssertEqual((response?["result"] as? [String: Any])?["protocolVersion"] as? String, "2025-11-25")
        XCTAssertNil(runtime.respond(to: ["jsonrpc": "2.0", "method": "notifications/initialized"]))
        XCTAssertNotNil(runtime.respond(to: request(id: 2, method: "tools/list")))
    }

    func testLocalBridgeRejectionSurfacesWithoutDirectStoreAccess() {
        let bridge = MockBridge(response: .failure(code: "local_mcp_disabled", message: "Local MCP is disabled in TermiPad on this Mac."))
        let runtime = initialize(TermiPadMCPStdIORuntime(bridge: bridge))
        let response = runtime.respond(to: toolCall(id: 2, name: "list_fixed_tasks"))
        XCTAssertEqual(toolErrorCode(response), "local_mcp_disabled")
        XCTAssertEqual(bridge.requests.first?.operation, .listFixedTasks)
    }

    func testFixedTaskCatalogResponseDoesNotExposeCommandsOrPaths() {
        let bridge = MockBridge(response: .success(message: "Fixed local tasks returned.", tasks: [
            .init(taskKind: TaskKind.swiftPackageTests.rawValue, risk: TaskRiskLevel.low.rawValue, purpose: "Run tests.")
        ]))
        let runtime = initialize(TermiPadMCPStdIORuntime(bridge: bridge))
        let response = runtime.respond(to: toolCall(id: 3, name: "list_fixed_tasks"))
        let tasks = structured(response)?["tasks"] as? [[String: Any]]
        XCTAssertEqual(tasks?.count, 1)
        XCTAssertFalse(tasks?.contains { $0.keys.contains("command") || $0.keys.contains("path") || $0.keys.contains("arguments") } ?? true)
    }

    func testProposalStaysPendingAndCancellationUsesOpaqueTaskID() {
        let taskID = UUID()
        let bridge = MockBridge(response: .success(message: "Task awaits local review in TermiPad.", task: .init(
            taskID: taskID,
            taskKind: TaskKind.swiftPackageTests.rawValue,
            risk: TaskRiskLevel.low.rawValue,
            state: TaskIntentState.pendingReview.rawValue,
            executionState: TaskExecutionState.notStarted.rawValue,
            exitCode: nil,
            executionReason: nil,
            expiresAt: Date()
        )))
        let runtime = initialize(TermiPadMCPStdIORuntime(bridge: bridge))
        let scopeID = UUID()
        let proposal = runtime.respond(to: toolCall(
            id: 4,
            name: "propose_task",
            arguments: ["scope_id": scopeID.uuidString, "task_kind": TaskKind.swiftPackageTests.rawValue]
        ))
        XCTAssertEqual((structured(proposal)?["task"] as? [String: Any])?["state"] as? String, TaskIntentState.pendingReview.rawValue)
        XCTAssertEqual(bridge.requests.last?.operation, .proposeTask)
        XCTAssertEqual(bridge.requests.last?.scopeID, scopeID)

        bridge.response = .success(message: "Local task cancellation recorded.", task: .init(
            taskID: taskID,
            taskKind: TaskKind.swiftPackageTests.rawValue,
            risk: TaskRiskLevel.low.rawValue,
            state: TaskIntentState.cancelled.rawValue,
            executionState: TaskExecutionState.notStarted.rawValue,
            exitCode: nil,
            executionReason: nil,
            expiresAt: nil
        ))
        let cancellation = runtime.respond(to: toolCall(id: 5, name: "cancel_task", arguments: ["task_id": taskID.uuidString]))
        XCTAssertEqual((structured(cancellation)?["task"] as? [String: Any])?["state"] as? String, TaskIntentState.cancelled.rawValue)
        XCTAssertEqual(bridge.requests.last?.operation, .cancelTask)
        XCTAssertEqual(bridge.requests.last?.taskID, taskID)
    }

    func testProposalRejectsAdditionalPropertiesBeforeBridge() {
        let bridge = MockBridge()
        let runtime = initialize(TermiPadMCPStdIORuntime(bridge: bridge))
        let response = runtime.respond(to: toolCall(
            id: 6,
            name: "propose_task",
            arguments: ["scope_id": UUID().uuidString, "task_kind": TaskKind.swiftPackageTests.rawValue, "command": "swift test"]
        ))
        XCTAssertEqual(toolErrorCode(response), "invalid_arguments")
        XCTAssertTrue(bridge.requests.isEmpty)
    }

    private func initialize(_ runtime: TermiPadMCPStdIORuntime) -> TermiPadMCPStdIORuntime {
        let response = runtime.respond(to: request(
            id: 1,
            method: "initialize",
            params: ["protocolVersion": "2025-03-26", "capabilities": [:], "clientInfo": ["name": "test-host", "version": "1"]]
        ))
        XCTAssertEqual((response?["result"] as? [String: Any])?["protocolVersion"] as? String, "2025-03-26")
        XCTAssertNil(runtime.respond(to: ["jsonrpc": "2.0", "method": "notifications/initialized"]))
        return runtime
    }

    private func request(id: Int, method: String, params: [String: Any] = [:]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
    }

    private func toolCall(id: Int, name: String, arguments: [String: Any] = [:]) -> [String: Any] {
        request(id: id, method: "tools/call", params: ["name": name, "arguments": arguments])
    }

    private func structured(_ response: [String: Any]?) -> [String: Any]? {
        let result = response?["result"] as? [String: Any]
        return result?["structuredContent"] as? [String: Any]
    }

    private func toolErrorCode(_ response: [String: Any]?) -> String? {
        structured(response)?["code"] as? String
    }

    private func errorCode(_ response: [String: Any]?) -> Int? {
        (response?["error"] as? [String: Any])?["code"] as? Int
    }
}

private final class MockBridge: LocalMCPBridgeTransport {
    var response: LocalMCPBridgeResponse
    private(set) var requests: [LocalMCPBridgeRequest] = []

    init(response: LocalMCPBridgeResponse = .failure(code: "local_mcp_disabled", message: "Local MCP is disabled in TermiPad on this Mac.")) {
        self.response = response
    }

    func send(_ request: LocalMCPBridgeRequest) -> LocalMCPBridgeResponse {
        requests.append(request)
        return response
    }
}
