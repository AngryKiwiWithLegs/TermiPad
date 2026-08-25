import Foundation
import SwiftData

/// TermiPad 的 SwiftData 容器工厂。
///
/// 生产环境使用系统默认位置；测试可传入固定 store URL，以验证旧数据在重新打开容器后仍可读取。
enum TermiPadDataStore {
    static let schema = Schema([TerminalTool.self, CandidateTool.self])

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
            configuration = ModelConfiguration(schema: schema)
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
