import Foundation

enum ToolHealth: Equatable {
    case available
    case missing
    case notExecutable
    case notInspectable

    var permitsLaunch: Bool {
        switch self {
        case .available, .notInspectable: return true
        case .missing, .notExecutable: return false
        }
    }

    func displayName(_ language: AppLanguage) -> String {
        switch (self, language) {
        case (.available, .simplifiedChinese): return "可用"
        case (.missing, .simplifiedChinese): return "找不到文件"
        case (.notExecutable, .simplifiedChinese): return "不可执行"
        case (.notInspectable, .simplifiedChinese): return "未检查"
        case (.available, .english): return "Available"
        case (.missing, .english): return "File not found"
        case (.notExecutable, .english): return "Not executable"
        case (.notInspectable, .english): return "Not checked"
        }
    }

    func recoveryMessage(_ language: AppLanguage) -> String {
        switch (self, language) {
        case (.missing, .simplifiedChinese):
            return "记录的可执行文件路径已不存在。请在“编辑工具”中更新路径，或删除这个已失效的工具。"
        case (.notExecutable, .simplifiedChinese):
            return "记录的文件不能作为可执行程序启动。请在“编辑工具”中检查路径和文件权限。"
        case (.missing, .english):
            return "The recorded executable path no longer exists. Edit the tool to update its path, or remove this stale tool."
        case (.notExecutable, .english):
            return "The recorded file is not executable. Edit the tool to check its path and file permissions."
        case (.available, .notInspectable, .simplifiedChinese):
            return ""
        case (.available, .notInspectable, .english):
            return ""
        }
    }
}

enum ToolHealthChecker {
    static func check(executablePath: String, fileManager: FileManager = .default) -> ToolHealth {
        let trimmedPath = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPath.hasPrefix("/") else { return .notInspectable }

        let resolvedPath = URL(fileURLWithPath: trimmedPath).resolvingSymlinksInPath().path
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resolvedPath, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return .missing
        }
        return fileManager.isExecutableFile(atPath: resolvedPath) ? .available : .notExecutable
    }
}
