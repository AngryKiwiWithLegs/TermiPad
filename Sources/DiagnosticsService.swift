import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Local diagnostic events that may be recorded. Every field is a fixed enum or a count; storing commands, paths, tool names, variable values, or secrets is forbidden.
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
    /// Recorded once whenever any T1/T2 entry point (T0 workbench UI, T1 executor read, T2 MCP) reads a task's execution result.
    /// Complements `.mcpTaskStatusRead`: that one is a protocol-level audit, this one is a task-domain audit. A single read
    /// may produce two events: the user/agent calling through the MCP protocol + the task domain recording the minimal result return.
    case taskExecutionResultRead
    /// Recorded once when a task proposal is about to expire (remaining < 60s but > 0s), giving
    /// the workbench's "expiring soon" hint an audit trail.
    case taskProposalExpiringSoon
    /// M0 mobile entry: recorded once when the user clicks "Revoke Mobile Permission" in the tool edit panel.
    /// At the same time the ToolTool.revokeMobilePermissionAt timestamp is written and showInMobileEntry and
    /// allowMobileLaunchRequest are set back to false; the iPhone deactivates as soon as its next heartbeat reads the new values.
    case mobilePermissionRevoked
    /// Recorded once when the M1.1 perSession/lowRisk session allowlist is hit and the tool launches directly without local confirmation.
    /// Timestamp and terminal target only (read together with launchSucceeded to see which launches skipped confirmation);
    /// the privacy discipline forbids recording tool or device names.
    case mobileLaunchAutoConfirmed
    /// Recorded once when the M2a remote tunnel loopback listener becomes ready (the tailnet IP is not recorded — privacy discipline).
    case remoteTunnelOpened
    /// Recorded once when the M2a remote tunnel is closed.
    case remoteTunnelClosed
    /// M2b task sessions: recorded once when the entry feed gains or updates an entry (tool launch or task status).
    /// Timestamp only — the privacy discipline records no tool/task/device names.
    case mobileConsoleEntryRecorded
    /// Recorded once when an M2b-3 task submission is rejected by the T0 local policy (review window / risk / scope, etc.).
    case remoteTaskRejectedByPolicy
    /// Recorded once when an M2b-3 task submission is rejected by the local Mac user (60s confirmation).
    case remoteTaskRejectedByUser
    /// Recorded once when the M2b-3 lowRisk allowlist is hit and the task starts directly without local confirmation.
    case mobileTaskAutoConfirmed
    /// Recorded once when a remote task is rejected while the Mac is locked (defense line 3), M2b-3.
    case remoteTaskBlockedScreenLocked
    /// Recorded once when the M3 user opens "Today's Remote Window" with Touch ID (timestamp only).
    case remoteAllowWindowOpened
    /// Recorded once when the M3 user closes the remote window manually.
    case remoteAllowWindowClosed
    /// Recorded once when locking the Mac invalidates the M3 remote window.
    case remoteAllowWindowLocked
    /// Recorded once when an M3 remote action runs through the window without confirmation (same privacy discipline as
    /// mobileLaunchAutoConfirmed: no tool or device names).
    case remoteAllowWindowUsed
    /// Recorded once when the phone makes a choice at an M4-3 task interaction point (timestamp only, not the option content).
    case mobileInteractionResponded
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

/// A minimal diagnostic report the user can export themselves; contains no tool, command, or credential content.
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

/// A small local ring log. Diagnostics leave this Mac only when the user exports them.
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
