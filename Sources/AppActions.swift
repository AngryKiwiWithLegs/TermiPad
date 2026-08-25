import Foundation

/// 仅用于应用内导航与现有操作的通知；不携带工具名、命令或其他用户内容。
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
