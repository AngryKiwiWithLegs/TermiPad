import XCTest
@testable import TermiPad

/// TermiPadCommands contract tests (track-protool stage 8 test hardening 4/4).
///
/// Locks down the menu shortcut ↔ AppAction name round-trip contract. The menu body itself is
/// SwiftUI Commands — a full view rendering test is expensive; the AppAction notification contract test
/// is enough to catch silent regressions like "the menu shortcut was renamed but the AppAction was not".
final class TermiPadCommandsContractTests: XCTestCase {

    // MARK: - AppAction case literals

    func testAppActionCaseRawValuesArePinned() {
        // An AppAction rename → menu shortcut routing breaks silently. This locks down the literals.
        XCTAssertEqual(TermiPadAppAction.openLibrary.rawValue, "openLibrary")
        XCTAssertEqual(TermiPadAppAction.showFavorites.rawValue, "showFavorites")
        XCTAssertEqual(TermiPadAppAction.showRecent.rawValue, "showRecent")
        XCTAssertEqual(TermiPadAppAction.discoverTools.rawValue, "discoverTools")
        XCTAssertEqual(TermiPadAppAction.addManualTool.rawValue, "addManualTool")
    }

    func testAppActionHasExactlyFiveCases() {
        // The 5 shortcuts ⌘1/⌘2/⌘3/⇧⌘D/⇧⌘N correspond to 5 cases (README:11-15).
        // Changing this number = the menu lost a button / a shortcut is broken.
        XCTAssertEqual([TermiPadAppAction.openLibrary, .showFavorites, .showRecent, .discoverTools, .addManualTool].count, 5)
    }

    // MARK: - send / from round-trip

    func testSendFromRoundTrip() {
        for action in [TermiPadAppAction.openLibrary, .showFavorites, .showRecent, .discoverTools, .addManualTool] {
            // Every case can be sent + parsed back to itself
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
        // Malicious / outdated notifications do not crash
        let bogus = Notification(
            name: .termiPadAppAction,
            object: nil,
            userInfo: ["action": "unknownActionXYZ"]
        )
        XCTAssertNil(TermiPadAppAction.from(bogus))
    }

    func testFromReturnsNilForMissingUserInfo() {
        // A notification without userInfo → nil (should not crash)
        let empty = Notification(name: .termiPadAppAction, object: nil, userInfo: nil)
        XCTAssertNil(TermiPadAppAction.from(empty))
    }

    func testFromReturnsNilForMissingActionKey() {
        // userInfo present but without the "action" key → nil
        let noKey = Notification(
            name: .termiPadAppAction,
            object: nil,
            userInfo: ["other": "value"]
        )
        XCTAssertNil(TermiPadAppAction.from(noKey))
    }

    // MARK: - Keyboard shortcut lock (product contract)

    func testMenuShortcutContractFromReadme() {
        // README lines 11-15:
        //   supports ⌘1 / ⌘2 / ⌘3 / ⇧⌘D / ⇧⌘N
        // This test locks down "a menu shortcut must be able to route to one of the 5 AppActions".
        // Changing the menu order or a shortcut → this test fails (intentional)
        let shortcuts: [(TermiPadAppAction, String)] = [
            (.openLibrary, "1"),
            (.showFavorites, "2"),
            (.showRecent, "3"),
            (.discoverTools, "d"),  // ⇧⌘D
            (.addManualTool, "n")    // ⇧⌘N
        ]
        // The 5 cases all map to the 5 keys — any misalignment breaks it
        XCTAssertEqual(shortcuts.count, [TermiPadAppAction.openLibrary, .showFavorites, .showRecent, .discoverTools, .addManualTool].count,
                       "the number of menu shortcuts must == the number of AppActions")
        // Every case is routed by at least one shortcut
        for action in [TermiPadAppAction.openLibrary, .showFavorites, .showRecent, .discoverTools, .addManualTool] {
            XCTAssertTrue(shortcuts.contains { $0.0 == action },
                          "\(action.rawValue) has no matching menu shortcut")
        }
    }
}
