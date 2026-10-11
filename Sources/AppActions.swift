import Foundation

/// Used only for in-app navigation and notifications of existing actions; carries no tool names, commands, or other user content.
enum TermiPadAppAction: String {
    case openLibrary
    case showFavorites
    case showRecent
    case discoverTools
    case addManualTool
}

extension Notification.Name {
    static let termiPadAppAction = Notification.Name("TermiPad.appAction")
}

extension TermiPadAppAction {
    func send() {
        NotificationCenter.default.post(
            name: .termiPadAppAction,
            object: nil,
            userInfo: ["action": rawValue]
        )
    }

    static func from(_ notification: Notification) -> TermiPadAppAction? {
        guard let rawValue = notification.userInfo?["action"] as? String else { return nil }
        return TermiPadAppAction(rawValue: rawValue)
    }
}
