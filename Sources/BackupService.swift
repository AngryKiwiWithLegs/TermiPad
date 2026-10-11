import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// A portable snapshot of local data. Keychain credentials are never written to a backup; whether saved template variable values are included is decided separately by the user at export time.
struct TermiPadBackup: Codable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let exportedAt: Date
    let includesSavedVariableValues: Bool
    let tools: [ToolRecord]
    let candidates: [CandidateRecord]

    struct ToolRecord: Codable, Identifiable {
        let id: UUID
        let name: String
        let executablePath: String
        let commandTemplate: String
        let toolDescription: String
        let categoryRawValue: String
        let iconSymbol: String
        let iconStyleIdentifier: String?
        let iconURLString: String?
        let repositoryFullName: String?
        let installationSourceRawValue: String?
        let metadataProvenanceRawValue: String?
        let metadataMatchConfidence: Int?
        let metadataUpdatedAt: Date?
        let isFavorite: Bool?
        let isUserCustomized: Bool
        let isHidden: Bool
        let variableValuesJSON: String?
        let lastLaunchedAt: Date?
        let createdAt: Date

        init(tool: TerminalTool, includeSavedVariableValues: Bool) {
            id = tool.id
            name = tool.name
            executablePath = tool.executablePath
            commandTemplate = tool.commandTemplate
            toolDescription = tool.toolDescription
            categoryRawValue = tool.categoryRawValue
            iconSymbol = tool.iconSymbol
            iconStyleIdentifier = tool.iconStyleIdentifier
            // Older versions may have stored a GitHub owner avatar; it is not a verifiable tool icon and must no longer be exported.
            iconURLString = nil
            repositoryFullName = tool.repositoryFullName
            installationSourceRawValue = tool.installationSourceRawValue
            metadataProvenanceRawValue = tool.metadataProvenanceRawValue
            metadataMatchConfidence = tool.metadataMatchConfidence
            metadataUpdatedAt = tool.metadataUpdatedAt
            isFavorite = tool.isFavorite
            isUserCustomized = tool.isUserCustomized
            isHidden = tool.isHidden
            variableValuesJSON = includeSavedVariableValues ? tool.variableValuesJSON : nil
            lastLaunchedAt = tool.lastLaunchedAt
            createdAt = tool.createdAt
        }

        func apply(to tool: TerminalTool, includesSavedVariableValues: Bool) {
            tool.name = name
            tool.executablePath = executablePath
            tool.commandTemplate = commandTemplate
            tool.toolDescription = toolDescription
            tool.categoryRawValue = categoryRawValue
            tool.iconSymbol = iconSymbol
            tool.iconStyleIdentifier = iconStyleIdentifier
            // Ignore remote icon URLs in old backups so historical owner avatars cannot re-enter the tool wall.
            tool.iconURLString = nil
            tool.repositoryFullName = repositoryFullName
            tool.installationSourceRawValue = installationSourceRawValue ?? ToolInstallationSource.detect(for: executablePath).rawValue
            tool.metadataProvenanceRawValue = metadataProvenanceRawValue ?? ToolMetadataProvenance.local.rawValue
            tool.metadataMatchConfidence = metadataMatchConfidence ?? 0
            tool.metadataUpdatedAt = metadataUpdatedAt
            if let isFavorite { tool.isFavorite = isFavorite }
            tool.isUserCustomized = isUserCustomized
            tool.isHidden = isHidden
            if includesSavedVariableValues {
                tool.variableValuesJSON = variableValuesJSON
            }
            tool.lastLaunchedAt = lastLaunchedAt
            tool.createdAt = createdAt
        }

        func makeTool(includesSavedVariableValues: Bool) -> TerminalTool {
            let tool = TerminalTool(
                name: name,
                executablePath: executablePath,
                commandTemplate: commandTemplate,
                toolDescription: toolDescription,
                category: ToolCategory(rawValue: categoryRawValue) ?? .other,
                iconSymbol: iconSymbol,
                installationSource: ToolInstallationSource(rawValue: installationSourceRawValue ?? ""),
                isUserCustomized: isUserCustomized
            )
            tool.id = id
            tool.iconStyleIdentifier = iconStyleIdentifier
            // Stay compatible with schema 1 backups, but do not restore the remote icon URLs that had no verified source back then.
            tool.iconURLString = nil
            tool.repositoryFullName = repositoryFullName
            tool.metadataProvenanceRawValue = metadataProvenanceRawValue ?? ToolMetadataProvenance.local.rawValue
            tool.metadataMatchConfidence = metadataMatchConfidence ?? 0
            tool.metadataUpdatedAt = metadataUpdatedAt
            tool.isFavorite = isFavorite ?? false
            tool.isHidden = isHidden
            if includesSavedVariableValues {
                tool.variableValuesJSON = variableValuesJSON
            }
            tool.lastLaunchedAt = lastLaunchedAt
            tool.createdAt = createdAt
            return tool
        }
    }

    struct CandidateRecord: Codable, Identifiable {
        let id: UUID
        let name: String
        let executablePath: String
        let categoryRawValue: String
        let statusRawValue: String
        let installationSourceRawValue: String?
        let discoveredAt: Date

        init(candidate: CandidateTool) {
            id = candidate.id
            name = candidate.name
            executablePath = candidate.executablePath
            categoryRawValue = candidate.categoryRawValue
            statusRawValue = candidate.statusRawValue
            installationSourceRawValue = candidate.installationSourceRawValue
            discoveredAt = candidate.discoveredAt
        }

        func apply(to candidate: CandidateTool) {
            candidate.name = name
            candidate.executablePath = executablePath
            candidate.categoryRawValue = categoryRawValue
            candidate.statusRawValue = statusRawValue
            candidate.installationSourceRawValue = installationSourceRawValue ?? ToolInstallationSource.detect(for: executablePath).rawValue
            candidate.discoveredAt = discoveredAt
        }

        func makeCandidate() -> CandidateTool {
            let candidate = CandidateTool(
                name: name,
                executablePath: executablePath,
                category: ToolCategory(rawValue: categoryRawValue) ?? .other,
                installationSource: ToolInstallationSource(rawValue: installationSourceRawValue ?? ""),
                status: CandidateStatus(rawValue: statusRawValue) ?? .pending
            )
            candidate.id = id
            candidate.discoveredAt = discoveredAt
            return candidate
        }
    }

    static func make(
        tools: [TerminalTool],
        candidates: [CandidateTool],
        includeSavedVariableValues: Bool
    ) -> TermiPadBackup {
        TermiPadBackup(
            schemaVersion: currentSchemaVersion,
            exportedAt: Date(),
            includesSavedVariableValues: includeSavedVariableValues,
            tools: tools.map { ToolRecord(tool: $0, includeSavedVariableValues: includeSavedVariableValues) },
            candidates: candidates.map(CandidateRecord.init(candidate:))
        )
    }
}

struct BackupFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct BackupRestoreSummary: Equatable {
    var addedTools = 0
    var updatedTools = 0
    var addedCandidates = 0
    var updatedCandidates = 0

    var totalChanges: Int { addedTools + updatedTools + addedCandidates + updatedCandidates }
}

enum BackupService {
    static func encode(_ backup: TermiPadBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }

    static func decode(_ data: Data) throws -> TermiPadBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(TermiPadBackup.self, from: data)
        guard backup.schemaVersion == TermiPadBackup.currentSchemaVersion else {
            throw BackupServiceError.unsupportedSchema(backup.schemaVersion)
        }
        return backup
    }

    @discardableResult
    static func restore(
        _ backup: TermiPadBackup,
        existingTools: [TerminalTool],
        existingCandidates: [CandidateTool],
        modelContext: ModelContext
    ) -> BackupRestoreSummary {
        var summary = BackupRestoreSummary()
        var toolsByID: [UUID: TerminalTool] = [:]
        var toolsByPath: [String: TerminalTool] = [:]
        for tool in existingTools {
            toolsByID[tool.id] = tool
            toolsByPath[normalizedPath(tool.executablePath)] = tool
        }

        for record in backup.tools {
            if let existing = toolsByID[record.id] ?? toolsByPath[normalizedPath(record.executablePath)] {
                record.apply(to: existing, includesSavedVariableValues: backup.includesSavedVariableValues)
                summary.updatedTools += 1
            } else {
                let tool = record.makeTool(includesSavedVariableValues: backup.includesSavedVariableValues)
                modelContext.insert(tool)
                toolsByID[tool.id] = tool
                toolsByPath[normalizedPath(tool.executablePath)] = tool
                summary.addedTools += 1
            }
        }

        var candidatesByID: [UUID: CandidateTool] = [:]
        var candidatesByPath: [String: CandidateTool] = [:]
        for candidate in existingCandidates {
            candidatesByID[candidate.id] = candidate
            candidatesByPath[normalizedPath(candidate.executablePath)] = candidate
        }
        for record in backup.candidates {
            if let existing = candidatesByID[record.id] ?? candidatesByPath[normalizedPath(record.executablePath)] {
                record.apply(to: existing)
                summary.updatedCandidates += 1
            } else {
                let candidate = record.makeCandidate()
                modelContext.insert(candidate)
                candidatesByID[candidate.id] = candidate
                candidatesByPath[normalizedPath(candidate.executablePath)] = candidate
                summary.addedCandidates += 1
            }
        }

        return summary
    }

    static func suggestedFileName(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "TermiPad-backup-\(formatter.string(from: now)).json"
    }

    private static func normalizedPath(_ value: String) -> String {
        (value as NSString).standardizingPath.lowercased()
    }
}

enum BackupServiceError: LocalizedError, Equatable {
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            return "This backup uses an unsupported data version: \(version)."
        }
    }
}
