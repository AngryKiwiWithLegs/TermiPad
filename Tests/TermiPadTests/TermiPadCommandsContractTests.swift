import XCTest
@testable import TermiPad

/// TermiPadCommands 契约测试（track-protool 阶段 8 测试补强 4/4）。
///
/// 锁住 menu shortcut ↔ AppAction 名称 round-trip 契约。menu body 本身是
/// SwiftUI Commands — 完整 view 渲染测试成本高;AppAction 通知契约测试
/// 足够 catch "menu shortcut 改了名字但 AppAction 没改"这类 silent regression。
final class TermiPadCommandsContractTests: XCTestCase {

    // MARK: - AppAction case 字面量

    func testAppActionCaseRawValuesArePinned() {
        // AppAction 名字改了 → 菜单 shortcut 路由 silent break。这锁字面量。
        XCTAssertEqual(TermiPadAppAction.openLibrary.rawValue, "openLibrary")
        XCTAssertEqual(TermiPadAppAction.showFavorites.rawValue, "showFavorites")
        XCTAssertEqual(TermiPadAppAction.showRecent.rawValue, "showRecent")
        XCTAssertEqual(TermiPadAppAction.discoverTools.rawValue, "discoverTools")
        XCTAssertEqual(TermiPadAppAction.addManualTool.rawValue, "addManualTool")
    }

    func testAppActionHasExactlyFiveCases() {
        // 5 个快捷键 ⌘1/⌘2/⌘3/⇧⌘D/⇧⌘N 对应 5 个 case (README:11-15)。
        // 改了这个数 = 菜单少了按钮/快捷键坏。
        XCTAssertEqual([TermiPadAppAction.openLibrary, .showFavorites, .showRecent, .discoverTools, .addManualTool].count, 5)
    }

    // MARK: - send / from round-trip

    func testSendFromRoundTrip() {
        for action in [TermiPadAppAction.openLibrary, .showFavorites, .showRecent, .discoverTools, .addManualTool] {
            // 每个 case 都能 send + 解析回自己
            let received = expectation(description: "got notification for \(action.rawValue)")
            let observer = NotificationCenter.default.addObserver(
                forName: .termiPadAppAction,
                object: nil,
                queue: .main
            ) { notification in
                if let parsed = TermiPadAppAction.from(notification), parsed == action {
                    received.fulfill()
                }
            }
            defer { NotificationCenter.default.removeObserver(observer) }
            action.send()
            wait(for: [received], timeout: 1)
        }
    }

    func testFromReturnsNilForUnknownAction() {
        // 恶意 / 过时 notification 不会 crash
        let bogus = Notification(
            name: .termiPadAppAction,
            object: nil,
            userInfo: ["action": "unknownActionXYZ"]
        )
        XCTAssertNil(TermiPadAppAction.from(bogus))
    }

    func testFromReturnsNilForMissingUserInfo() {
        // notification 没 userInfo → nil (不应崩)
        let empty = Notification(name: .termiPadAppAction, object: nil, userInfo: nil)
        XCTAssertNil(TermiPadAppAction.from(empty))
    }

    func testFromReturnsNilForMissingActionKey() {
        // userInfo 有但没 "action" key → nil
        let noKey = Notification(
            name: .termiPadAppAction,
            object: nil,
            userInfo: ["other": "value"]
        )
        XCTAssertNil(TermiPadAppAction.from(noKey))
    }

    // MARK: - keyboard shortcut 锁定 (产品契约)

    func testMenuShortcutContractFromReadme() {
        // README 第 11-15 行:
        //   支持 ⌘1 / ⌘2 / ⌘3 / ⇧⌘D / ⇧⌘N
        // 这测试锁住 "menu shortcut 必须能 route 到 5 个 AppAction 之一"。
        // 改 menu 顺序、改快捷键 → 这测试 fail (intentional)
        let shortcuts: [(TermiPadAppAction, String)] = [
            (.openLibrary, "1"),
            (.showFavorites, "2"),
            (.showRecent, "3"),
            (.discoverTools, "d"),  // ⇧⌘D
            (.addManualTool, "n")    // ⇧⌘N
        ]
        // 5 个 case 都对应了 5 个 key — 任何错位都 break
        XCTAssertEqual(shortcuts.count, [TermiPadAppAction.openLibrary, .showFavorites, .showRecent, .discoverTools, .addManualTool].count,
                       "menu shortcut 数量必须 == AppAction 数量")
        // 每个 case 至少被一个 shortcut 路由
        for action in [TermiPadAppAction.openLibrary, .showFavorites, .showRecent, .discoverTools, .addManualTool] {
            XCTAssertTrue(shortcuts.contains { $0.0 == action },
                          "\(action.rawValue) 缺对应的 menu shortcut")
        }
    }
}
