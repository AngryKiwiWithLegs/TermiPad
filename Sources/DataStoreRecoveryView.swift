import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Controlled recovery notice shown when the default SwiftData store cannot be opened.
/// Recovery mode uses a local database isolated from the default store and never deletes the original data automatically.
struct DataStoreRecoveryView: View {
    let primaryStoreErrorDescription: String

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TerminalTool.name) private var tools: [TerminalTool]
    @Query(sort: \CandidateTool.discoveredAt, order: .reverse) private var candidates: [CandidateTool]
    @AppStorage("TermiPad.language") private var languageRawValue = AppLanguage.defaultLanguage.rawValue

    @State private var isImportingBackup = false
    @State private var recoveryMessage: String?

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRawValue) ?? .defaultLanguage
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(.orange)

            Text(AppCopy.text("dataRecoveryTitle", language: language))
                .font(.title2.weight(.semibold))

            Text(AppCopy.text("dataRecoveryDetail", language: language))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 520)

            GroupBox(AppCopy.text("dataRecoveryStore", language: language)) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(AppCopy.text("dataRecoveryFallback", language: language))
                    Text(AppCopy.text("dataRecoveryHint", language: language))
                        .foregroundStyle(.secondary)
                    Text(primaryStoreErrorDescription)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: 620)

            Button(AppCopy.text("importBackup", language: language)) {
                isImportingBackup = true
            }
            .accessibilityIdentifier("data-recovery-import-backup")

            if let recoveryMessage {
                Text(recoveryMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .frame(minWidth: 680, minHeight: 560)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("data-recovery-screen")
        .fileImporter(
            isPresented: $isImportingBackup,
            allowedContentTypes: [.json]
        ) { result in
            importBackup(result)
        }
    }

    private func importBackup(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess { url.stopAccessingSecurityScopedResource() }
            }
            let backup = try BackupService.decode(Data(contentsOf: url))
            let summary = BackupService.restore(
                backup,
                existingTools: tools,
                existingCandidates: candidates,
                modelContext: modelContext
            )
            try modelContext.save()
            recoveryMessage = String(
                format: AppCopy.text("restoreSummary", language: language),
                summary.addedTools,
                summary.updatedTools,
                summary.addedCandidates,
                summary.updatedCandidates
            )
        } catch {
            recoveryMessage = AppCopy.text("backupImportFailed", language: language)
        }
    }
}
