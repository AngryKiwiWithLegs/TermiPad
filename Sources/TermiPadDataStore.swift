import Foundation
import SwiftData

/// TermiPad 的 SwiftData 容器工厂。
///
/// 生产环境使用系统默认位置；测试可传入固定 store URL，以验证旧数据在重新打开容器后仍可读取。
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
            // 专用 store URL：绝不使用 SwiftData 的默认位置（~/Library/Application Support/
            // default.store）。同一台 Mac 上的其他 SwiftData 应用（如 sibling 项目 Launchpad）
            // 也使用该默认文件名，双方先后打开会把彼此的 schema 顶掉，导致本应用落入
            // 恢复模式且数据表被丢弃。固定写到 Application Support/TermiPad/ 专属目录。
            let dedicatedURL = try defaultDedicatedStoreURL()
            // iCloud 同步必须经过独立的账户、容器、冲突与迁移设计；不能因未来出现 entitlement 而隐式开启。
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
