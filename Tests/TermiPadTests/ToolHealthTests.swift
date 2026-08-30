import XCTest
@testable import TermiPad

/// ToolHealth 单元测试（track-protocol 阶段 6 测试补强）。
///
/// ToolHealth 是 `LaunchpadView.requestLaunch` 启动工具前的最后一道闸门：
///  1. 检查可执行路径是否还在 + 是否可执行
///  2. 决定是否允许 launch（`.permitsLaunch`） + 显示对应错误恢复文案
///
/// 任意误改（弱化 permitsLaunch 条件 / 修错 recoveryMessage）会绕过启动检查
/// 或让用户看不到如何修复。这 4 个 case 锁住当前 4 状态 + 关键计算。
final class ToolHealthTests: XCTestCase {
    func testAvailablePermitsLaunch() {
        XCTAssertTrue(ToolHealth.available.permitsLaunch)
    }

    func testNotInspectablePermitsLaunch() {
        // 相对路径 / 不在白名单绝对路径下，OS 没法检查但也不应该拦截。
        XCTAssertTrue(ToolHealth.notInspectable.permitsLaunch,
                      "非可检查路径应放行——OS 后续会自己报错。")
    }

    func testMissingDoesNotPermitLaunch() {
        XCTAssertFalse(ToolHealth.missing.permitsLaunch,
                       "可执行文件不存在必须拦截——弱化这里会启动不存在的二进制。")
    }

    func testNotExecutableDoesNotPermitLaunch() {
        XCTAssertFalse(ToolHealth.notExecutable.permitsLaunch,
                       "不可执行权限必须拦截——启动会失败，浪费用户时间。")
    }

    func testRecoveryMessagePointsToEditToolForMissingFile() {
        // missing 的恢复文案必须**明确**指向「编辑工具」入口，否则用户不知道怎么办。
        let zh = ToolHealth.missing.recoveryMessage(.simplifiedChinese)
        let en = ToolHealth.missing.recoveryMessage(.english)
        XCTAssertTrue(zh.contains("编辑工具") || zh.contains("工具库"),
                       "中文 recovery 应指向编辑工具/工具库。got: \(zh)")
        XCTAssertTrue(en.contains("Edit Tool") || en.contains("Edit the tool"),
                       "English recovery should point to Edit Tool. got: \(en)")
    }

    func testRecoveryMessageEmptyForPassableStates() {
        // available / notInspectable 既然能 launch，就不该弹错。
        XCTAssertEqual(ToolHealth.available.recoveryMessage(.simplifiedChinese), "")
        XCTAssertEqual(ToolHealth.available.recoveryMessage(.english), "")
        XCTAssertEqual(ToolHealth.notInspectable.recoveryMessage(.simplifiedChinese), "")
        XCTAssertEqual(ToolHealth.notInspectable.recoveryMessage(.english), "")
    }
}
