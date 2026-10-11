import Foundation

/// T2 local MCP is turned on only by the user, deliberately, on the Mac. It is not a network service and does not constitute client identity authentication.
enum TaskMCPSettings {
    static let localMCPEnabledKey = "TermiPad.localMCPEnabled"

    static var isLocalMCPEnabled: Bool {
        UserDefaults.standard.bool(forKey: localMCPEnabledKey)
    }
}
