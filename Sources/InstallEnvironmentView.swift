import SwiftUI

/// P2-B/P2-C 的独立审查页。它不接收网络命令、不执行应用内安装，且不自动扫描或收录任何结果。
struct InstallEnvironmentView: View {
    let language: AppLanguage

    @AppStorage("TermiPad.terminalTarget") private var terminalTargetRawValue = TerminalTarget.systemTerminal.rawValue
    @State private var report: EnvironmentReport?
    @State private var isInspecting = false
    @State private var selectedPlan: ControlledInstallPlan?
    @State private var handoffMessage: String?

    private var terminalTarget: TerminalTarget {
        TerminalTarget(rawValue: terminalTargetRawValue) ?? .systemTerminal
    }

    private var homebrewIsAvailable: Bool {
        report?.entries.first(where: { $0.component == .homebrew }).map { entry in
            if case .available = entry.status { return true }
            return false
        } ?? false
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(AppCopy.text("environmentReport", language: language), systemImage: "stethoscope")
                        .font(.headline)
                    Text(AppCopy.text("environmentReportHint", language: language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(AppCopy.text("checkEnvironment", language: language), action: inspectEnvironment)
                        .disabled(isInspecting)
                        .accessibilityIdentifier("environment-report-check")
                    if isInspecting {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)
            }

            if let report {
                Section(AppCopy.text("environmentReportResults", language: language)) {
                    ForEach(report.entries) { entry in
                        HStack {
                            Text(entry.component.displayName(language))
                            Spacer()
                            Text(entry.status.displayText(language: language))
                                .foregroundStyle(statusColor(for: entry.status))
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(AppCopy.text("installReview", language: language), systemImage: "checklist")
                        .font(.headline)
                    Text(AppCopy.text("installReviewHint", language: language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section(AppCopy.text("reviewedInstallPlans", language: language)) {
                ForEach(ControlledInstallCatalog.reviewedPlans) { plan in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(plan.toolName)
                                .font(.headline)
                            Spacer()
                            Text(plan.channel.displayName(language))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(plan.repositoryFullName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(AppCopy.text("reviewInstallPlan", language: language)) {
                            DiagnosticsStore.shared.record(.installPlanReviewed)
                            selectedPlan = plan
                        }
                        .accessibilityIdentifier("install-review-\(plan.formula)")
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                Text(AppCopy.text("installResultNotCollected", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(.clear)
        .navigationTitle(AppCopy.text("installAndEnvironment", language: language))
        .accessibilityIdentifier("install-environment")
        .sheet(item: $selectedPlan) { plan in
            InstallPlanReviewSheet(
                plan: plan,
                language: language,
                terminalTarget: terminalTarget,
                canSendToTerminal: homebrewIsAvailable,
                onHandoff: handoff
            )
        }
        .alert(AppCopy.text("operationResult", language: language), isPresented: Binding(
            get: { handoffMessage != nil },
            set: { if !$0 { handoffMessage = nil } }
        )) {
            Button(AppCopy.text("ok", language: language), role: .cancel) { handoffMessage = nil }
        } message: {
            Text(handoffMessage ?? "")
        }
    }

    private func inspectEnvironment() {
        guard !isInspecting else { return }
        DiagnosticsStore.shared.record(.environmentReportRequested)
        isInspecting = true
        Task {
            let nextReport = await Task.detached(priority: .userInitiated) {
                EnvironmentReporter.inspect()
            }.value
            report = nextReport
            isInspecting = false
        }
    }

    private func handoff(_ plan: ControlledInstallPlan, target: TerminalTarget) {
        do {
            let result = try TerminalLauncher.launch(command: plan.command, target: target)
            DiagnosticsStore.shared.record(.installPlanHandedOff, terminalTarget: target)
            handoffMessage = handoffMessage(for: result)
        } catch let error as TerminalLauncherError {
            DiagnosticsStore.shared.record(.installPlanHandoffFailed, terminalTarget: target)
            handoffMessage = error.message(language: language)
        } catch {
            DiagnosticsStore.shared.record(.installPlanHandoffFailed, terminalTarget: target)
            handoffMessage = AppCopy.text("installHandoffFailed", language: language)
        }
    }

    private func handoffMessage(for result: TerminalLaunchResult) -> String {
        switch (result, language) {
        case (.launched(let target), .simplifiedChinese):
            return "已将固定安装计划交给 \(target.displayName(language))。请在终端中自行查看输出与确认结果。"
        case (.copied(let target), .simplifiedChinese), (.copiedAfterAutomationPermissionDenied(let target), .simplifiedChinese):
            return "固定安装计划已复制。请在 \(target.displayName(language)) 中自行检查后再粘贴执行。"
        case (.launched(let target), .english):
            return "The fixed install plan was sent to \(target.displayName(language)). Review the terminal output and outcome yourself."
        case (.copied(let target), .english), (.copiedAfterAutomationPermissionDenied(let target), .english):
            return "The fixed install plan was copied. Review it before pasting into \(target.displayName(language))."
        }
    }

    private func statusColor(for status: EnvironmentComponentStatus) -> Color {
        switch status {
        case .available: return .secondary
        case .unavailable: return .secondary
        case .inspectionFailed: return .orange
        }
    }
}

private struct InstallPlanReviewSheet: View {
    let plan: ControlledInstallPlan
    let language: AppLanguage
    let terminalTarget: TerminalTarget
    let canSendToTerminal: Bool
    let onHandoff: (ControlledInstallPlan, TerminalTarget) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var hasConfirmedReview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(plan.title(language: language), systemImage: "checklist")
                .font(.title3.weight(.semibold))

            LabeledContent(AppCopy.text("installChannel", language: language), value: plan.channel.displayName(language))
            LabeledContent(AppCopy.text("repository", language: language), value: plan.repositoryFullName)
            LabeledContent(AppCopy.text("expectedExecutables", language: language), value: plan.expectedExecutableNames.joined(separator: ", "))
            LabeledContent(AppCopy.text("catalogRevision", language: language), value: plan.catalogRevision)
            LabeledContent(AppCopy.text("catalogAuditedAt", language: language), value: plan.auditedAt)

            VStack(alignment: .leading, spacing: 6) {
                Text(AppCopy.text("installCommandPreview", language: language))
                    .font(.headline)
                Text(plan.command)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Text(plan.safetySummary(language: language))
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(AppCopy.text("installReviewAcknowledgement", language: language), isOn: $hasConfirmedReview)
                .toggleStyle(.checkbox)
                .accessibilityIdentifier("install-review-acknowledgement")

            Text(AppCopy.text("installExplicitConsent", language: language))
                .font(.caption)
                .foregroundStyle(.secondary)
            if !canSendToTerminal {
                Text(AppCopy.text("installRequiresHomebrewCheck", language: language))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Button(AppCopy.text("cancel", language: language), role: .cancel) {
                    dismiss()
                }
                Spacer()
                Button(AppCopy.text("copyInstallPlan", language: language)) {
                    onHandoff(plan, .copyOnly)
                    dismiss()
                }
                Button(AppCopy.format("sendInstallPlan", terminalTarget.displayName(language), language: language)) {
                    onHandoff(plan, terminalTarget)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasConfirmedReview || !canSendToTerminal)
                .accessibilityIdentifier("install-handoff-\(plan.formula)")
            }
        }
        .padding(24)
        .frame(minWidth: 520)
        .accessibilityIdentifier("install-plan-review")
    }
}
