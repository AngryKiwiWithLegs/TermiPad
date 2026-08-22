import AppKit
import Foundation

enum TerminalTarget: String, CaseIterable, Identifiable {
    case systemTerminal = "Terminal.app"
    case iTerm = "iTerm"
    case warp = "Warp"
    case copyOnly = "仅复制命令"

    var id: String { rawValue }

    var bundleIdentifier: String? {
        switch self {
        case .systemTerminal: return "com.apple.Terminal"
        case .iTerm: return "com.googlecode.iterm2"
        case .warp: return "dev.warp.Warp-Stable"
        case .copyOnly: return nil
        }
    }

    var helpText: String {
        switch self {
        case .systemTerminal: return "在 macOS Terminal 的新标签或窗口中执行命令。"
        case .iTerm: return "在 iTerm 的当前窗口或新窗口中输入命令。"
        case .warp: return "打开 Warp 并将命令复制到剪贴板，您可自行粘贴并检查后执行。"
        case .copyOnly: return "只将完整命令复制到剪贴板，不启动任何终端。"
        }
    }
}

enum TerminalLaunchResult: Equatable {
    case launched(message: String)
    case copied(message: String)
}

enum TerminalLauncher {
    static func launch(command: String, target: TerminalTarget) throws -> TerminalLaunchResult {
        switch target {
        case .systemTerminal:
            try launchInTerminal(command)
            return .launched(message: "已在 Terminal 中执行命令。")
        case .iTerm:
            try launchInITerm(command)
            return .launched(message: "已在 iTerm 中输入命令。")
        case .warp:
            try launchInWarp(command)
            return .copied(message: "已打开 Warp，并将命令复制到剪贴板。")
        case .copyOnly:
            copy(command)
            return .copied(message: "完整命令已复制到剪贴板。")
        }
    }

    private static func launchInTerminal(_ command: String) throws {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") != nil else {
            throw TerminalLauncherError.applicationUnavailable(TerminalTarget.systemTerminal.rawValue)
        }

        let script = """
        tell application "Terminal"
            activate
            do script "\(appleScriptEscape(command))"
        end tell
        """
        try execute(script)
    }

    private static func launchInITerm(_ command: String) throws {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.googlecode.iterm2") != nil else {
            throw TerminalLauncherError.applicationUnavailable(TerminalTarget.iTerm.rawValue)
        }

        let escapedCommand = appleScriptEscape(command)
        let script = """
        tell application "iTerm"
            activate
            if (count of windows) = 0 then
                create window with default profile
            end if
            tell current session of current window
                write text "\(escapedCommand)"
            end tell
        end tell
        """
        try execute(script)
    }

    private static func launchInWarp(_ command: String) throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "dev.warp.Warp-Stable") else {
            throw TerminalLauncherError.applicationUnavailable(TerminalTarget.warp.rawValue)
        }
        copy(command)
        NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
    }

    private static func execute(_ source: String) throws {
        guard let script = NSAppleScript(source: source) else {
            throw TerminalLauncherError.scriptCreationFailed
        }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            throw TerminalLauncherError.appleScriptFailed(error.description)
        }
    }

    private static func copy(_ command: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)
    }

    private static func appleScriptEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}

enum TerminalLauncherError: LocalizedError {
    case applicationUnavailable(String)
    case scriptCreationFailed
    case appleScriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .applicationUnavailable(let name):
            return "未检测到 \(name)。请在设置中选择其他终端，或改为仅复制命令。"
        case .scriptCreationFailed:
            return "无法创建终端启动脚本。"
        case .appleScriptFailed(let message):
            return "终端未能接收命令：\(message)"
        }
    }
}
