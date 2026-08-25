import Foundation
import SwiftData

/// TermiPad 的 SwiftData 容器工厂。
///
/// 生产环境使用系统默认位置；测试可传入固定 store URL，以验证旧数据在重新打开容器后仍可读取。
enum TermiPadDataStore {
    static let schema = Schema([TerminalTool.self, CandidateTool.self])

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
            // iCloud 同步必须经过独立的账户、容器、冲突与迁移设计；不能因未来出现 entitlement 而隐式开启。
            configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
