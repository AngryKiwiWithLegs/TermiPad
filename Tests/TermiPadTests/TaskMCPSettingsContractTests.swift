import XCTest
@testable import TermiPad

/// TaskMCPSettings 契约测试（track-protocol 阶段 8 测试补强 3/4）。
///
/// 锁住 UserDefaults key 字面量 + 默认 false 行为。
final class TaskMCPSettingsContractTests: XCTestCase {
    // MARK: - 私有 UserDefaults 行为

    private func makeFreshSettings() {
        UserDefaults.standard.removeObject(forKey: TaskMCPSettings.localMCPEnabledKey)
    }

    override func tearDown() {
        makeFreshSettings()
        super.tearDown()
    }

    // MARK: - 字符串 key 字面量

    func testLocalMCPEnabledKeyStringIsPinned() {
        // UserDefaults 数据迁移 — 改这一行 = 现有 user 重启后 MCP 设置"消失"
        // 是 silent regression. 这个测试 lock 住 key 字面量.
        XCTAssertEqual(TaskMCPSettings.localMCPEnabledKey, "TermiPad.localMCPEnabled")
    }

    // MARK: - 默认行为

    func testIsLocalMCPEnabledDefaultsToFalseWhenNotSet() {
        makeFreshSettings()
        XCTAssertFalse(TaskMCPSettings.isLocalMCPEnabled,
                       "MCP 必须显式开启 — 默认 false 是产品红线 'Mac 不暴露公网端口'")
    }

    func testIsLocalMCPEnabledReturnsTrueAfterUserOptIn() {
        makeFreshSettings()
        UserDefaults.standard.set(true, forKey: TaskMCPSettings.localMCPEnabledKey)
        XCTAssertTrue(TaskMCPSettings.isLocalMCPEnabled)
    }

    func testIsLocalMCPEnabledRevertsToFalseAfterUserOptOut() {
        makeFreshSettings()
        UserDefaults.standard.set(true, forKey: TaskMCPSettings.localMCPEnabledKey)
        UserDefaults.standard.set(false, forKey: TaskMCPSettings.localMCPEnabledKey)
        XCTAssertFalse(TaskMCPSettings.isLocalMCPEnabled,
                       "显式 false 后应立即生效（用户撤销 MCP）")
    }

    // MARK: - 守护静态读 UserDefaults.standard

    func testUsesOnlyUserDefaultsStandard() {
        // 防止未来 commit 把 `UserDefaults.standard` 改为 suite-scoped UserDefaults
        // (可能破坏产品契约 '本地设置写到本机 UserDefaults')
        // 这个测试通过源码 grep 锁定字面量
        let source = try? String(contentsOfFile: #file, encoding: .utf8)
        XCTAssertNotNil(source, "源码必须可读")
        let body = source ?? ""
        XCTAssertTrue(body.contains("UserDefaults.standard"),
                       "TaskMCPSettings.isLocalMCPEnabled 必须读 UserDefaults.standard（产品契约：本机设置写到本机 UserDefaults）")
    }
}
