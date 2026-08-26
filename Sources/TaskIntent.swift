import Foundation
import SwiftData

/// T0 只允许随应用发布的固定任务类型。它们不是手机、MCP 或 AI 传入的 Shell 命令。
enum TaskKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case swiftPackageTests
    case macOSVerification
    case xcodegenGeneration

    var id: String { rawValue }
}

enum TaskRiskLevel: String, Codable, CaseIterable, Sendable {
    case low
    case standard

    func permits(_ proposed: TaskRiskLevel) -> Bool {
        switch (self, proposed) {
        case (.standard, _), (.low, .low): return true
        case (.low, .standard): return false
        }
    }
}

enum TaskIntentState: String, Codable, CaseIterable, Sendable {
    case pendingReview
    case approved
    case rejected
    case expired
    case revoked
    case cancelled
}

/// T1 只保存执行生命周期和退出码；绝不保存、展示或回传终端输出。
enum TaskExecutionState: String, Codable, CaseIterable, Sendable {
    case notStarted
    case running
    case succeeded
    case failed
    case timedOut
    case stopped
    case startRejected
    case startFailed
}

enum TaskExecutionRejectionReason: String, Codable, CaseIterable, Sendable {
    case intentNotApproved
    case intentExpired
    case taskAlreadyStarted
    case projectScopeUnavailable
    case taskDefinitionUnavailable
    case taskPreflightFailed
}

enum TaskRejectionReason: String, Codable, CaseIterable, Sendable {
    case unknownTaskKind
    case projectScopeUnavailable
    case localReviewRequired
    case reviewWindowExpired
    case riskNotPermitted
    case nonceReplayed
    case taskExpired
    case taskNotPending
    case taskCancelled
}

/// 明确绑定到用户本机选择项目目录的本地范围。路径不会进入备份、诊断或任何外部协议。
@Model
final class TaskProjectScope {
    var id: UUID
    var displayName: String
    var rootPath: String
    var isRevoked: Bool
    var createdAt: Date
    var revokedAt: Date?

    init(displayName: String, rootPath: String, createdAt: Date = Date()) {
        id = UUID()
        self.displayName = displayName
        self.rootPath = (rootPath as NSString).standardizingPath
        isRevoked = false
        self.createdAt = createdAt
        revokedAt = nil
    }

    var directoryIsAvailable: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: rootPath, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

/// 用户在 Mac 本机主动开启的短期审阅窗口。T0 不创建远程窗口，也不执行任务。
@Model
final class TaskReviewWindow {
    var id: UUID
    var projectScopeID: UUID
    var maximumRiskRawValue: String
    var openedAt: Date
    var expiresAt: Date
    var revokedAt: Date?

    init(
        projectScopeID: UUID,
        maximumRisk: TaskRiskLevel = .standard,
        openedAt: Date = Date(),
        expiresAt: Date
    ) {
        id = UUID()
        self.projectScopeID = projectScopeID
        maximumRiskRawValue = maximumRisk.rawValue
        self.openedAt = openedAt
        self.expiresAt = expiresAt
        revokedAt = nil
    }

    var maximumRisk: TaskRiskLevel {
        get { TaskRiskLevel(rawValue: maximumRiskRawValue) ?? .low }
        set { maximumRiskRawValue = newValue.rawValue }
    }

    func isActive(at now: Date) -> Bool {
        revokedAt == nil && expiresAt > now
    }
}

/// 一次性任务只持有固定任务类型和本地范围引用；命令正文始终由本地静态目录解释。
@Model
final class TaskIntent {
    var id: UUID
    var projectScopeID: UUID
    var kindRawValue: String
    var riskRawValue: String
    var stateRawValue: String
    var nonce: UUID
    var proposedAt: Date
    var expiresAt: Date
    var approvedAt: Date?
    var resolvedAt: Date?
    var rejectionReasonRawValue: String?
    var executionStateRawValue: String?
    var executionStartedAt: Date?
    var executionFinishedAt: Date?
    var executionExitCode: Int?
    var executionRejectionReasonRawValue: String?

    init(
        projectScopeID: UUID,
        kind: TaskKind,
        risk: TaskRiskLevel,
        nonce: UUID = UUID(),
        proposedAt: Date = Date(),
        expiresAt: Date
    ) {
        id = UUID()
        self.projectScopeID = projectScopeID
        kindRawValue = kind.rawValue
        riskRawValue = risk.rawValue
        stateRawValue = TaskIntentState.pendingReview.rawValue
        self.nonce = nonce
        self.proposedAt = proposedAt
        self.expiresAt = expiresAt
        approvedAt = nil
        resolvedAt = nil
        rejectionReasonRawValue = nil
        executionStateRawValue = TaskExecutionState.notStarted.rawValue
        executionStartedAt = nil
        executionFinishedAt = nil
        executionExitCode = nil
        executionRejectionReasonRawValue = nil
    }

    var kind: TaskKind? {
        TaskKind(rawValue: kindRawValue)
    }

    var risk: TaskRiskLevel {
        TaskRiskLevel(rawValue: riskRawValue) ?? .standard
    }

    var state: TaskIntentState {
        get { TaskIntentState(rawValue: stateRawValue) ?? .rejected }
        set { stateRawValue = newValue.rawValue }
    }

    var rejectionReason: TaskRejectionReason? {
        get { rejectionReasonRawValue.flatMap(TaskRejectionReason.init(rawValue:)) }
        set { rejectionReasonRawValue = newValue?.rawValue }
    }

    var executionState: TaskExecutionState {
        get { executionStateRawValue.flatMap(TaskExecutionState.init(rawValue:)) ?? .notStarted }
        set { executionStateRawValue = newValue.rawValue }
    }

    var executionRejectionReason: TaskExecutionRejectionReason? {
        get { executionRejectionReasonRawValue.flatMap(TaskExecutionRejectionReason.init(rawValue:)) }
        set { executionRejectionReasonRawValue = newValue?.rawValue }
    }
}

/// 只读固定目录。T0 不接受并不保存任意命令、参数、环境变量或网络地址。
struct FixedTaskDefinition: Equatable, Identifiable {
    let kind: TaskKind
    let commandPreview: String
    let executable: FixedTaskExecutable
    let arguments: [String]
    let requiredRelativePaths: [String]
    let timeout: TimeInterval
    let purposeChinese: String
    let purposeEnglish: String
    let risk: TaskRiskLevel

    var id: TaskKind { kind }

    func purpose(language: AppLanguage) -> String {
        switch language {
        case .simplifiedChinese: return purposeChinese
        case .english: return purposeEnglish
        }
    }
}

/// 仅允许固定绝对路径候选或项目范围内固定相对可执行文件，禁止 Shell 和 PATH 搜索。
enum FixedTaskExecutable: Equatable {
    case absoluteCandidates([String])
    case projectRelative(String)
}

enum FixedTaskCatalog {
    static let definitions: [FixedTaskDefinition] = [
        .init(
            kind: .swiftPackageTests,
            commandPreview: "swift test",
            executable: .absoluteCandidates(["/usr/bin/xcrun"]),
            arguments: ["swift", "test"],
            requiredRelativePaths: ["Package.swift"],
            timeout: 120,
            purposeChinese: "运行项目的 Swift Package 单元测试。",
            purposeEnglish: "Run the project's Swift Package unit tests.",
            risk: .low
        ),
        .init(
            kind: .macOSVerification,
            commandPreview: "./scripts/verify-macos.sh",
            executable: .projectRelative("scripts/verify-macos.sh"),
            arguments: [],
            requiredRelativePaths: ["Package.swift", "project.yml", "scripts/verify-macos.sh"],
            timeout: 300,
            purposeChinese: "运行 TermiPad 的集中 macOS 验证脚本。",
            purposeEnglish: "Run TermiPad's one-shot macOS verification script.",
            risk: .standard
        ),
        .init(
            kind: .xcodegenGeneration,
            commandPreview: "xcodegen generate",
            executable: .absoluteCandidates(["/opt/homebrew/bin/xcodegen", "/usr/local/bin/xcodegen"]),
            arguments: ["generate"],
            requiredRelativePaths: ["project.yml"],
            timeout: 60,
            purposeChinese: "从项目定义生成本地 Xcode 工程。",
            purposeEnglish: "Generate the local Xcode project from the project definition.",
            risk: .low
        )
    ]

    static func definition(for kind: TaskKind) -> FixedTaskDefinition? {
        definitions.first { $0.kind == kind }
    }
}
