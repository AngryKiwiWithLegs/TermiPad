import Foundation

enum ToolWorkingDirectoryHealth: Equatable {
    case notConfigured
    case available
    case unavailable

    func displayName(_ language: AppLanguage) -> String {
        switch (self, language) {
        case (.notConfigured, .simplifiedChinese): return "未设置"
        case (.available, .simplifiedChinese): return "可用"
        case (.unavailable, .simplifiedChinese): return "找不到目录"
        case (.notConfigured, .english): return "Not set"
        case (.available, .english): return "Available"
        case (.unavailable, .english): return "Folder not found"
        }
    }

    func recoveryMessage(_ language: AppLanguage) -> String {
        switch (self, language) {
        case (.unavailable, .simplifiedChinese):
            return "已选择的工作目录已不可用。请在“编辑工具”中重新选择目录或清除该设置。"
        case (.unavailable, .english):
            return "The selected working directory is unavailable. Edit the tool to choose another folder or clear this setting."
        case (.notConfigured, _), (.available, _):
            return ""
        }
    }
}

enum ToolLaunchContext {
    static func workingDirectoryHealth(
        for path: String?,
        fileManager: FileManager = .default
    ) -> ToolWorkingDirectoryHealth {
        guard let normalizedPath = normalizedDirectoryPath(path) else { return .notConfigured }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: normalizedPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .unavailable
        }
        return .available
    }

    static func normalizedDirectoryPath(_ path: String?) -> String? {
        guard let path else { return nil }
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPath.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: trimmedPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }

    static func command(_ command: String, inWorkingDirectory path: String?) -> String {
        guard let normalizedPath = normalizedDirectoryPath(path) else { return command }
        return "cd -- \(CommandTemplate.shellEscape(normalizedPath)) && \(command)"
    }
}
