import XCTest
import SwiftData
@testable import TermiPad

/// M0 移动端入口数据模型 + 撤销行为测试（track-protocol stage 4.3）。
///
/// 对应 docs/m0-m1-mobile-entry-design.md §2.7 完成度门槛第 1 行 "6 字段持久化 +
/// 默认 false/nil/everyTime"。
final class MobileEntryTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var tool: TerminalTool!

    override func setUpWithError() throws {
        continueAfterFailure = false
        container = try TermiPadDataStore.makeContainer(isStoredInMemoryOnly: true)
        context = ModelContext(container)
        tool = TerminalTool(
            name: "merge-cli",
            executablePath: "/usr/local/bin/merge-cli",
            commandTemplate: "merge-cli"
        )
    }

    override func tearDownWithError() throws {
        // in-memory container 丢弃即可
    }

    func testDefaultsAreAllClosed() {
        // docs/m0-m1-mobile-entry-design.md §2.2: "默认全关"
        XCTAssertNil(tool.mobileDisplayName, "mobileDisplayName 默认 nil（用本地 name）。")
        XCTAssertEqual(tool.mobileDescription, "", "mobileDescription 默认空串。")
        XCTAssertFalse(tool.showInMobileEntry, "showInMobileEntry 默认 false。")
        XCTAssertFalse(tool.allowMobileLaunchRequest, "allowMobileLaunchRequest 默认 false。")
        XCTAssertEqual(tool.mobileLocalConfirmPolicy, .everyTime, "mobileLocalConfirmPolicy 默认 .everyTime。")
        XCTAssertNil(tool.revokeMobilePermissionAt, "revokeMobilePermissionAt 默认 nil。")
    }

    func testRoundTripPersistsAllSixFields() throws {
        tool.mobileDisplayName = "项目同步"
        tool.mobileDescription = "运行 git pull --rebase"
        tool.showInMobileEntry = true
        tool.allowMobileLaunchRequest = true
        tool.mobileLocalConfirmPolicy = .perSession
        tool.revokeMobilePermissionAt = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(tool)
        try context.save()

        let fetched = try XCTUnwrap(context.fetch(FetchDescriptor<TerminalTool>()).first)
        XCTAssertEqual(fetched.mobileDisplayName, "项目同步")
        XCTAssertEqual(fetched.mobileDescription, "运行 git pull --rebase")
        XCTAssertTrue(fetched.showInMobileEntry)
        XCTAssertTrue(fetched.allowMobileLaunchRequest)
        XCTAssertEqual(fetched.mobileLocalConfirmPolicy, .perSession)
        XCTAssertEqual(fetched.revokeMobilePermissionAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testRevokeTripleActionSetsAllThreeFields() throws {
        // docs/m0-m1-mobile-entry-design.md §2.4: "撤销 = 写时间戳 + 关 2 个开关"
        // 这里直接 mutate + save 模拟 performMobileRevoke() 的副作用（按钮本身在 UI 测试覆盖）。
        tool.showInMobileEntry = true
        tool.allowMobileLaunchRequest = true
        tool.mobileLocalConfirmPolicy = .lowRiskSessionOnly
        context.insert(tool)
        try context.save()

        // 模拟 performMobileRevoke 的双撤销
        tool.revokeMobilePermissionAt = Date()
        tool.showInMobileEntry = false
        tool.allowMobileLaunchRequest = false
        try context.save()

        let fetched = try XCTUnwrap(context.fetch(FetchDescriptor<TerminalTool>()).first)
        XCTAssertNotNil(fetched.revokeMobilePermissionAt, "撤销后时间戳被写入。")
        XCTAssertFalse(fetched.showInMobileEntry, "撤销后 showInMobileEntry 被关。")
        XCTAssertFalse(fetched.allowMobileLaunchRequest, "撤销后 allowMobileLaunchRequest 被关。")
        // mobileLocalConfirmPolicy 不在撤销范围内——保留用户的偏好以便之后再次开启时复用。
        XCTAssertEqual(fetched.mobileLocalConfirmPolicy, .lowRiskSessionOnly,
                       "撤销不影响 confirm policy——用户偏好保留。")
    }

    func testAllThreePolicyCasesRoundTrip() throws {
        for policy: MobileLocalConfirmPolicy in [.everyTime, .perSession, .lowRiskSessionOnly] {
            let localTool = TerminalTool(
                name: "policy-\(policy.rawValue)",
                executablePath: "/usr/local/bin/p",
                commandTemplate: "p"
            )
            localTool.mobileLocalConfirmPolicy = policy
            context.insert(localTool)
            try context.save()
        }
        let all = try context.fetch(FetchDescriptor<TerminalTool>())
        XCTAssertEqual(Set(all.map(\.mobileLocalConfirmPolicy)),
                       Set([.everyTime, .perSession, .lowRiskSessionOnly]))
    }

    func testMigrationFromOlderRecordWithoutMobileFields() throws {
        // 模拟旧 store 没有 6 字段的记录（forward-compatibility：M0 是叠加层）
        // SwiftData @Model 新增 Optional 字段不应破坏旧 record 加载。
        // 这里直接构造一个没有设过 6 字段的 TerminalTool，模拟旧记录语义。
        let old = TerminalTool(
            name: "legacy",
            executablePath: "/usr/local/bin/legacy",
            commandTemplate: "legacy"
        )
        // 不设 6 字段
        context.insert(old)
        try context.save()

        let fetched = try XCTUnwrap(context.fetch(FetchDescriptor<TerminalTool>()).first(where: { $0.name == "legacy" }))
        XCTAssertNil(fetched.mobileDisplayName)
        XCTAssertEqual(fetched.mobileDescription, "")
        XCTAssertFalse(fetched.showInMobileEntry)
        XCTAssertFalse(fetched.allowMobileLaunchRequest)
        XCTAssertEqual(fetched.mobileLocalConfirmPolicy, .everyTime)
        XCTAssertNil(fetched.revokeMobilePermissionAt)
    }
}
