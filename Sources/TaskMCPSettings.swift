import Foundation

/// T2 本机 MCP 只由用户在 Mac 上主动开启。它不是网络服务，也不构成客户端身份认证。
enum TaskMCPSettings {
    static let localMCPEnabledKey = "TermiPad.localMCPEnabled"

    static var isLocalMCPEnabled: Bool {
        UserDefaults.standard.bool(forKey: localMCPEnabledKey)
    }
}
