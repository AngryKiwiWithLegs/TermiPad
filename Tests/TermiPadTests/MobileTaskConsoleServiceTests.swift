import XCTest
@testable import TermiPad

/// M2b-1 任务会话中心契约测试（docs/m2b-remote-task-console-design.md §5.3/§5.4）：
/// 条目流上限、工具启动无输出、输出档位裁决、驻留时限清扫。全部纯逻辑。
@MainActor
final class MobileTaskConsoleServiceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: MobileTaskConsoleService.outputVisibilityDefaultsKey)
    }

    private func makeEntry(
        id: UUID = UUID(),
        offsetMinutes: TimeInterval = 0,
        output: String? = nil
    ) -> Date {
        Date().addingTimeInterval(-offsetMinutes * 60)
    }

    func testToolLaunchEntryNeverCarriesOutputOrExitCode() {
        let service = MobileTaskConsoleService()
        service.recordToolLaunch(id: UUID(), title: "构建", succeeded: true)
        service.recordToolLaunch(id: UUID(), title: "构建", succeeded: false)
        let snapshot = service.sessionEntries()
        XCTAssertEqual(snapshot.count, 2)
        for entry in snapshot where entry.kind == .toolLaunch {
            XCTAssertNil(entry.outputSnippet, "工具启动（终端交接）永无输出回传")
            XCTAssertNil(entry.exitCode, "终端交接路径无退出码")
        }
        XCTAssertEqual(
            Set(snapshot.map(\.executionState)),
            Set(["launched", "launchFailed"]))
    }

    func testEntryStreamCapsAtLimit() {
        let service = MobileTaskConsoleService()
        let limit = MobileTaskConsoleService.entryLimit
        for index in 0..<(limit + 10) {
            service.recordToolLaunch(id: UUID(), title: "工具\(index)", succeeded: true)
        }
        XCTAssertEqual(service.sessionEntries().count, limit)
        // 最新条目在最前——环内保留的是最近的，最早的被挤掉。
        let titles = service.sessionEntries().map(\.title)
        XCTAssertEqual(titles.first, "工具\(limit + 9)")
    }

    func testTaskStateUpdatesInPlaceById() {
        let service = MobileTaskConsoleService()
        let taskID = UUID()
        service.recordTaskState(
            id: taskID, title: "swift test", executionState: .running,
            exitCode: nil, startedAt: Date(), finishedAt: nil, outputSnippet: nil)
        service.recordTaskState(
            id: taskID, title: "swift test", executionState: .succeeded,
            exitCode: 0, startedAt: Date(), finishedAt: Date(), outputSnippet: nil)
        let snapshot = service.sessionEntries()
        XCTAssertEqual(snapshot.count, 1, "同一任务按 id 原位更新，不重复占位")
        XCTAssertEqual(snapshot.first?.executionState, TaskExecutionState.succeeded.rawValue)
        XCTAssertEqual(snapshot.first?.exitCode, 0)
    }

    func testMinimalVisibilityStripsOutputSnippet() {
        UserDefaults.standard.set(
            MobileTaskConsoleService.OutputVisibility.minimal.rawValue,
            forKey: MobileTaskConsoleService.outputVisibilityDefaultsKey)
        let service = MobileTaskConsoleService()
        let taskID = UUID()
        service.recordTaskState(
            id: taskID, title: "swift test", executionState: .running,
            exitCode: nil, startedAt: Date(), finishedAt: nil,
            outputSnippet: "Test Suite passed")
        XCTAssertNil(service.sessionEntries().first?.outputSnippet, "minimal 档位下输出片段一律不下发")
    }

    func testRestrictedVisibilityKeepsOutputSnippet() {
        // 默认档位即 restricted（设计 §5.4 建议默认）。
        UserDefaults.standard.set(
            MobileTaskConsoleService.OutputVisibility.restricted.rawValue,
            forKey: MobileTaskConsoleService.outputVisibilityDefaultsKey)
        let service = MobileTaskConsoleService()
        let taskID = UUID()
        service.recordTaskState(
            id: taskID, title: "swift test", executionState: .succeeded,
            exitCode: 0, startedAt: Date(), finishedAt: Date(),
            outputSnippet: "Test Suite passed")
        XCTAssertEqual(service.sessionEntries().first?.outputSnippet, "Test Suite passed")
    }

    func testDefaultVisibilityIsRestricted() {
        // 未设置时回落 restricted——设计建议默认值（用户未喊停即按此执行）。
        let service = MobileTaskConsoleService()
        XCTAssertEqual(service.currentVisibility, .restricted)
    }

    func testExpiredOutputIsSweptAfterRetentionInterval() {
        UserDefaults.standard.set(
            MobileTaskConsoleService.OutputVisibility.restricted.rawValue,
            forKey: MobileTaskConsoleService.outputVisibilityDefaultsKey)
        let service = MobileTaskConsoleService()
        let oldFinished = Date().addingTimeInterval(
            -(MobileTaskConsoleService.outputRetentionInterval + 60))
        service.recordTaskState(
            id: UUID(), title: "旧任务", executionState: .succeeded,
            exitCode: 0, startedAt: oldFinished, finishedAt: oldFinished,
            outputSnippet: "stale output")
        XCTAssertNil(service.sessionEntries().first?.outputSnippet, "结束超过驻留时限的输出片段被清扫")
    }

    func testFixedTaskSummariesCarryCatalogLiterals() {
        let service = MobileTaskConsoleService()
        let summaries = service.fixedTaskSummaries(language: .simplifiedChinese)
        XCTAssertEqual(summaries.count, FixedTaskCatalog.definitions.count)
        // 目录字段是 FixedTaskCatalog 公开字面量（kind/用途/命令预览），
        // 不是用户数据——数量与 kind 集合必须与目录一一对应。
        XCTAssertEqual(
            Set(summaries.map(\.kind)),
            Set(FixedTaskCatalog.definitions.map { $0.kind.rawValue }))
        XCTAssertTrue(summaries.allSatisfy { !$0.purpose.isEmpty && !$0.commandPreview.isEmpty })
    }
}
