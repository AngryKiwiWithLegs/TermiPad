import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// 当默认 SwiftData store 无法打开时显示的受控恢复说明。
/// 恢复模式使用与默认 store 隔离的本地数据库，绝不会自动删除原数据。
struct DataStoreRecoveryView: View {
    let primaryStoreErrorDescription: String

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TerminalTool.name) private var tools: [TerminalTool]
    @Query(sort: \CandidateTool.discoveredAt, order: .reverse) private var candidates: [CandidateTool]
    @AppStorage("TermiPad.language") private var languageRawValue = AppLanguage.simplifiedChinese.rawValue

    @State private var isImportingBackup = false
    @State private var recoveryMessage: String?

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRawValue) ?? .simplifiedChinese
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
                summary.toolsAdded,
                summary.toolsUpdated,
                summary.candidatesAdded,
                summary.candidatesUpdated
            )
        } catch {
            recoveryMessage = AppCopy.text("backupImportFailed", language: language)
        }
    }
}
