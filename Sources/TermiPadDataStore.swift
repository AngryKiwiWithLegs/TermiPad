import Foundation
import SwiftData

/// TermiPad's SwiftData container factory.
///
/// Production uses the system default location; tests can pass a fixed store URL to verify that old data is still readable after reopening the container.
enum TermiPadDataStore {
    static let schema = Schema([
        TerminalTool.self,
        CandidateTool.self,
        TaskProjectScope.self,
        TaskReviewWindow.self,
        TaskIntent.self
    ])

    static func makeRecoveryContainer(
        applicationSupportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> ModelContainer {
        let rootDirectory: URL
        if let applicationSupportDirectory {
            rootDirectory = applicationSupportDirectory
        } else {
            rootDirectory = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("TermiPad", isDirectory: true)
        }
        let recoveryDirectory = rootDirectory.appendingPathComponent("Recovery", isDirectory: true)
        try fileManager.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
        return try makeContainer(storeURL: recoveryDirectory.appendingPathComponent("TermiPad-recovery.store"))
    }

    static func makeContainer(
        storeURL: URL? = nil,
        isStoredInMemoryOnly: Bool = false
    ) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if let storeURL {
            configuration = ModelConfiguration(
                nil,
                schema: schema,
                url: storeURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )
        } else if isStoredInMemoryOnly {
            configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        } else {
            // Dedicated store URL: never use SwiftData's default location (~/Library/Application Support/
            // default.store). Other SwiftData apps on the same Mac (such as the sibling project Launchpad)
            // use that default file name too; opening one after the other would overwrite each other's schema, sending this app into
            // recovery mode with its tables dropped. Always write to the dedicated Application Support/TermiPad/ directory.
            let dedicatedURL = try defaultDedicatedStoreURL()
            // iCloud sync must go through a separate account, container, conflict, and migration design; it must not be enabled implicitly just because an entitlement appears in the future.
            configuration = ModelConfiguration(
                nil,
                schema: schema,
                url: dedicatedURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private static func defaultDedicatedStoreURL(fileManager: FileManager = .default) throws -> URL {
        let root = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("TermiPad", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent("TermiPad.store")
    }
}
