import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// 可记录的本地诊断事件。所有字段均为固定枚举或计数，禁止存入命令、路径、工具名、变量值和密钥。
enum DiagnosticEventKind: String, Codable, CaseIterable {
    case scanCompleted
    case launchSucceeded
    case commandCopied
    case automationFallback
    case launchFailed
    case toolHealthBlocked
    case workingDirectoryUnavailable
    case backupExported
    case backupRestored
    case backupFailed
    case updateChecked
    case updateCheckFailed
    case discoveryRefreshed
    case discoveryCacheReused
    case discoveryRefreshFailed
    case environmentReportRequested
    case installPlanReviewed
    case installPlanHandedOff
    case installPlanHandoffFailed
    case taskProposalCreated
    case taskReviewWindowOpened
    case taskPolicyApproved
    case taskPolicyRejected
    case taskCancelled
    case taskScopeRevoked
    case taskExecutionStarted
    case taskExecutionSucceeded
    case taskExecutionFailed
    case taskExecutionStopped
    case taskExecutionTimedOut
    case taskExecutionRejected
    case taskExecutionStartFailed
    /// T1/T2 任何入口（T0 工作台 UI、T1 执行器读取、T2 MCP）读取 task 执行结果时记一次。
    /// 与 `.mcpTaskStatusRead` 互补：后者是协议层审计，前者是 task 域审计。同一次读取
    /// 可能产生两个 event：用户/智能体走 MCP 协议调用 + task 域记录最小结果回传。
    case taskExecutionResultRead
    /// 任务 proposal 即将过期（remaining < 60s 但 > 0s）时记一次，给用户
    /// 在工作台上的"即将过期"提示提供审计依据。
    case taskProposalExpiringSoon
    /// M0 移动端入口：用户在工具编辑面板点"撤销手机权限"按钮时记一次。
    /// 同时 ToolTool.revokeMobilePermissionAt 时间戳被写、showInMobileEntry 与
    /// allowMobileLaunchRequest 被设回 false，iPhone 端下次心跳读到新值即停用。
    case mobilePermissionRevoked
    /// M1.1 perSession/lowRisk 会话白名单命中、免本机确认直启时记一次。
    /// 仅时间戳与终端目标（与 launchSucceeded 并读即知哪些启动跳过了确认）；
    /// 隐私纪律禁止记工具名/设备名。
    case mobileLaunchAutoConfirmed
    /// M2a 异地隧道回环监听就绪时记一次（不记 tailnet IP——隐私纪律）。
    case remoteTunnelOpened
    /// M2a 异地隧道关闭时记一次。
    case remoteTunnelClosed
    /// M2b 任务会话：条目流新增/更新（工具启动或任务状态）时记一次。
    /// 仅时间戳——隐私纪律不记工具名/任务名/设备名。
    case mobileConsoleEntryRecorded
    /// M2b-3 任务提交被 T0 本地策略拒绝（审阅窗口/风险/范围等）时记一次。
    case remoteTaskRejectedByPolicy
    /// M2b-3 任务提交被 Mac 本机用户拒绝（60s 确认）时记一次。
    case remoteTaskRejectedByUser
    /// M2b-3 lowRisk 白名单命中、免本机确认直启任务时记一次。
    case mobileTaskAutoConfirmed
    /// M2b-3 Mac 锁屏期间远程任务被拒（防线 3）时记一次。
    case remoteTaskBlockedScreenLocked
    /// M3 用户触摸 ID 开启"今日远程窗口"时记一次（仅时间戳）。
    case remoteAllowWindowOpened
    /// M3 用户手动关闭远程窗口时记一次。
    case remoteAllowWindowClosed
    /// M3 Mac 锁屏触发远程窗口失效时记一次。
    case remoteAllowWindowLocked
    /// M3 远程操作经窗口免确认执行时记一次（与 mobileLaunchAutoConfirmed
    /// 同隐私纪律：不记工具名/设备名）。
    case remoteAllowWindowUsed
    case mcpToolListed
    case mcpTaskProposed
    case mcpTaskStatusRead
    case mcpTaskCancelled
}

struct DiagnosticEvent: Codable, Equatable, Identifiable {
    let id: UUID
    let occurredAt: Date
    let kind: DiagnosticEventKind
    let terminalTargetRawValue: String?
    let itemCount: Int?

    init(
        occurredAt: Date = Date(),
        kind: DiagnosticEventKind,
        terminalTarget: TerminalTarget? = nil,
        itemCount: Int? = nil
    ) {
        id = UUID()
        self.occurredAt = occurredAt
        self.kind = kind
        terminalTargetRawValue = terminalTarget?.rawValue
        self.itemCount = itemCount
    }
}

/// 可由用户自行导出的最小诊断报告；不含任何工具、命令或凭据内容。
struct PrivacyDiagnosticReport: Codable, Equatable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let generatedAt: Date
    let appVersion: String
    let macOSVersion: String
    let privacyNotice: String
    let events: [DiagnosticEvent]

    init(events: [DiagnosticEvent], generatedAt: Date = Date()) {
        schemaVersion = Self.schemaVersion
        self.generatedAt = generatedAt
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let version, let build {
            appVersion = "\(version) (\(build))"
        } else {
            appVersion = version ?? build ?? "development"
        }
        macOSVersion = ProcessInfo.processInfo.operatingSystemVersionString
        privacyNotice = "Contains fixed event categories, timestamps, terminal target names, and aggregate item counts only. No tool names, executable paths, commands, variable values, API keys, or repository content are included."
        self.events = events
    }
}

/// 小型环形本地日志。诊断仅在用户主动导出时离开这台 Mac。
final class DiagnosticsStore {
    static let shared = DiagnosticsStore()

    private let defaults: UserDefaults
    private let storageKey: String
    private let maximumEventCount: Int
    private let now: () -> Date

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "TermiPad.diagnostics.events",
        maximumEventCount: Int = 200,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.maximumEventCount = max(1, maximumEventCount)
        self.now = now
    }

    func record(_ kind: DiagnosticEventKind, terminalTarget: TerminalTarget? = nil, itemCount: Int? = nil) {
        var stored = events
        stored.append(DiagnosticEvent(occurredAt: now(), kind: kind, terminalTarget: terminalTarget, itemCount: itemCount))
        if stored.count > maximumEventCount {
            stored.removeFirst(stored.count - maximumEventCount)
        }
        save(stored)
    }

    var events: [DiagnosticEvent] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([DiagnosticEvent].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.occurredAt < $1.occurredAt }
    }

    func makePrivacyReport() -> PrivacyDiagnosticReport {
        PrivacyDiagnosticReport(events: events, generatedAt: now())
    }

    func clear() {
        defaults.removeObject(forKey: storageKey)
    }

    private func save(_ events: [DiagnosticEvent]) {
        guard let data = try? JSONEncoder().encode(events) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

struct DiagnosticFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
