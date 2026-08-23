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

    func displayName(_ language: AppLanguage) -> String {
        switch (self, language) {
        case (.systemTerminal, _): return "Terminal.app"
        case (.iTerm, _): return "iTerm"
        case (.warp, _): return "Warp"
        case (.copyOnly, .simplifiedChinese): return "仅复制命令"
        case (.copyOnly, .english): return "Copy Command Only"
        }
    }

    func helpText(_ language: AppLanguage) -> String {
        switch (self, language) {
        case (.systemTerminal, .simplifiedChinese): return "在 macOS Terminal 的新标签或窗口中执行命令。"
        case (.iTerm, .simplifiedChinese): return "在 iTerm 的当前窗口或新窗口中输入命令。"
        case (.warp, .simplifiedChinese): return "打开 Warp 并将命令复制到剪贴板，您可自行粘贴并检查后执行。"
        case (.copyOnly, .simplifiedChinese): return "只将完整命令复制到剪贴板，不启动任何终端。"
        case (.systemTerminal, .english): return "Runs the command in a new Terminal tab or window."
        case (.iTerm, .english): return "Types the command into the current or a new iTerm window."
        case (.warp, .english): return "Opens Warp and copies the command so you can review and paste it."
        case (.copyOnly, .english): return "Copies the completed command without opening a terminal."
        }
    }
}

enum TerminalLaunchResult: Equatable {
    case launched(TerminalTarget)
    case copied(TerminalTarget)
    case copiedAfterAutomationPermissionDenied(TerminalTarget)
}

enum TerminalLauncher {
    static func launch(command: String, target: TerminalTarget) throws -> TerminalLaunchResult {
        switch target {
        case .systemTerminal:
            do {
                try launchInTerminal(command)
                return .launched(.systemTerminal)
            } catch TerminalLauncherError.automationPermissionDenied(_) {
                copy(command)
                return .copiedAfterAutomationPermissionDenied(.systemTerminal)
            }
        case .iTerm:
            do {
                try launchInITerm(command)
                return .launched(.iTerm)
            } catch TerminalLauncherError.automationPermissionDenied(_) {
                copy(command)
                return .copiedAfterAutomationPermissionDenied(.iTerm)
            }
        case .warp:
            try launchInWarp(command)
            return .copied(.warp)
        case .copyOnly:
            copy(command)
            return .copied(.copyOnly)
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
        try execute(script, target: .systemTerminal)
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
        try execute(script, target: .iTerm)
    }

    private static func launchInWarp(_ command: String) throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "dev.warp.Warp-Stable") else {
            throw TerminalLauncherError.applicationUnavailable(TerminalTarget.warp.rawValue)
        }
        copy(command)
        NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
    }

    private static func execute(_ source: String, target: TerminalTarget) throws {
        guard let script = NSAppleScript(source: source) else {
            throw TerminalLauncherError.scriptCreationFailed
        }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            let number = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue
            if number == -1743 {
                throw TerminalLauncherError.automationPermissionDenied(target)
            }
            let detail = (error[NSAppleScript.errorBriefMessage] as? String)
                ?? (error[NSAppleScript.errorMessage] as? String)
                ?? "未知 AppleScript 错误"
            throw TerminalLauncherError.appleScriptFailed(detail)
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
    case automationPermissionDenied(TerminalTarget)
    case appleScriptFailed(String)

    func message(language: AppLanguage) -> String {
        switch (self, language) {
        case (.applicationUnavailable(let name), .simplifiedChinese):
            return "未检测到 \(name)。请在设置中选择其他终端，或改为仅复制命令。"
        case (.scriptCreationFailed, .simplifiedChinese):
            return "无法创建终端启动脚本。"
        case (.automationPermissionDenied(let target), .simplifiedChinese):
            return "TermiPad 尚未获准控制 \(target.displayName(.simplifiedChinese))。请前往“系统设置 → 隐私与安全性 → 自动化”，开启 TermiPad 对该终端的权限后重试。"
        case (.appleScriptFailed(let message), .simplifiedChinese):
            return "终端未能接收命令：\(message)"
        case (.applicationUnavailable(let name), .english):
            return "\(name) was not found. Choose another terminal in Settings or copy the command only."
        case (.scriptCreationFailed, .english):
            return "The terminal launch script could not be created."
        case (.automationPermissionDenied(let target), .english):
            return "TermiPad is not allowed to control \(target.displayName(.english)). Go to System Settings → Privacy & Security → Automation, enable TermiPad for this terminal, then try again."
        case (.appleScriptFailed(let message), .english):
            return "The terminal could not accept the command: \(message)"
        }
    }

    var errorDescription: String? {
        message(language: .simplifiedChinese)
    }
}
