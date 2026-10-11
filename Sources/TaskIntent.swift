import Foundation
import SwiftData

/// T0 only allows the fixed task types shipped with the app. They are not shell commands passed in by a phone, MCP, or AI.
///
/// A new case must also get a matching entry in `FixedTaskCatalog.definitions`;
/// `TaskIntentPolicyTests.testTaskCatalogContainsOnlyFixedLocalDefinitions` automatically
/// checks that the two case sets are strictly equal.
enum TaskKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case swiftPackageTests
    case swiftBuild
    case swiftPackageCheck
    case macOSVerification
    case xcodegenGeneration
    /// M4-3 interaction point demo: the script asks → choice card on the phone → written back via stdin.
    case interactionDemo

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

/// T1 stores only the execution lifecycle and exit code; it never stores, shows, or returns terminal output.
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

/// A local scope explicitly bound to the project directory the user chose on this Mac. The path never enters backups, diagnostics, or any external protocol.
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

/// A short-lived review window the user opens deliberately on the Mac. T0 creates no remote windows and runs no tasks.
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

/// A one-off task holds only a fixed task type and a local scope reference; the command body is always interpreted by the local static catalog.
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

/// Read-only fixed catalog. T0 neither accepts nor stores arbitrary commands, arguments, environment variables, or network addresses.
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
    /// M4-3 interaction points (docs/m4-interactive-session-design.md §2.2): structured questions declared
    /// by the task — when stdout matches triggerPattern, prompt+options are pushed to
    /// the phone and the selection is written back via stdin. All literals (catalog-level, not generated at runtime);
    /// T1 opens a stdin pipe only for tasks that declare interaction points; the rest keep empty input.
    var interactionPoints: [TaskInteractionPoint]? = nil

    var id: TaskKind { kind }

    func purpose(language: AppLanguage) -> String {
        switch language {
        case .simplifiedChinese: return purposeChinese
        case .english: return purposeEnglish
        }
    }
}

/// Interaction point definition: the task's declaration of "when to ask, how to ask, and which options there are".
struct TaskInteractionPoint: Equatable {
    /// An interaction is triggered when stdout matches this pattern (a regex literal).
    let triggerPattern: String
    /// The question copy pushed to the phone.
    let prompt: String
    /// Fixed options (rendered as buttons on the phone; the selected label is written back via stdin).
    let options: [String]
}

/// Only fixed absolute-path candidates or fixed relative executables inside the project scope are allowed; shells and PATH searches are forbidden.
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
            kind: .swiftBuild,
            commandPreview: "swift build",
            executable: .absoluteCandidates(["/usr/bin/xcrun"]),
            arguments: ["swift", "build"],
            requiredRelativePaths: ["Package.swift"],
            timeout: 180,
            purposeChinese: "编译项目的 Swift Package。",
            purposeEnglish: "Build the project's Swift Package.",
            risk: .standard
        ),
        .init(
            kind: .swiftPackageCheck,
            commandPreview: "swift package describe",
            executable: .absoluteCandidates(["/usr/bin/xcrun"]),
            arguments: ["swift", "package", "describe"],
            requiredRelativePaths: ["Package.swift"],
            timeout: 30,
            purposeChinese: "只读检查 Swift Package 描述，不修改任何文件。",
            purposeEnglish: "Read-only inspect the Swift Package description, no file modification.",
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
            kind: .interactionDemo,
            commandPreview: "./scripts/interaction-demo.sh",
            executable: .projectRelative("scripts/interaction-demo.sh"),
            arguments: [],
            requiredRelativePaths: ["scripts/interaction-demo.sh"],
            timeout: 120,
            purposeChinese: "交互演示：脚本会提问，在手机上选择回答。",
            purposeEnglish: "Interaction demo: script asks, answer on the phone.",
            risk: .low,
            interactionPoints: [
                TaskInteractionPoint(
                    triggerPattern: "INTERACT_CONTINUE[?]",
                    prompt: "The demo script is paused, waiting for your decision:",
                    options: ["yes", "no"])
            ]
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
