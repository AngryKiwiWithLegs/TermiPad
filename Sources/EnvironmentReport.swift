import Foundation

/// P2-C 只读环境报告检查的固定组件。它不枚举 PATH，也不接受外部提供的可执行文件或参数。
enum EnvironmentComponent: String, CaseIterable, Identifiable, Sendable {
    case homebrew
    case cargo
    case npm
    case pnpm
    case bun
    case python

    var id: String { rawValue }

    func displayName(_ language: AppLanguage) -> String {
        switch (self, language) {
        case (.homebrew, _): return "Homebrew"
        case (.cargo, _): return "Cargo"
        case (.npm, _): return "npm"
        case (.pnpm, _): return "pnpm"
        case (.bun, _): return "Bun"
        case (.python, .simplifiedChinese): return "Python"
        case (.python, .english): return "Python"
        }
    }

    fileprivate var candidatePaths: [String] {
        switch self {
        case .homebrew:
            return ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        case .cargo:
            return [NSHomeDirectory() + "/.cargo/bin/cargo"]
        case .npm:
            return ["/opt/homebrew/bin/npm", "/usr/local/bin/npm"]
        case .pnpm:
            return ["/opt/homebrew/bin/pnpm", "/usr/local/bin/pnpm"]
        case .bun:
            return [NSHomeDirectory() + "/.bun/bin/bun"]
        case .python:
            return ["/opt/homebrew/bin/python3", "/usr/local/bin/python3"]
        }
    }
}

enum EnvironmentComponentStatus: Equatable, Sendable {
    case available(version: String)
    case unavailable
    case inspectionFailed

    func displayText(language: AppLanguage) -> String {
        switch (self, language) {
        case (.available(let version), _): return version
        case (.unavailable, .simplifiedChinese): return "未在受控路径中检测到"
        case (.inspectionFailed, .simplifiedChinese): return "已发现，但无法完成只读版本检查"
        case (.unavailable, .english): return "Not detected at a controlled path"
        case (.inspectionFailed, .english): return "Found, but the read-only version check failed"
        }
    }
}

struct EnvironmentReportEntry: Identifiable, Equatable, Sendable {
    let component: EnvironmentComponent
    let status: EnvironmentComponentStatus

    var id: EnvironmentComponent { component }
}

struct EnvironmentReport: Equatable, Sendable {
    let generatedAt: Date
    let entries: [EnvironmentReportEntry]

    var availableCount: Int {
        entries.reduce(into: 0) { count, entry in
            if case .available = entry.status { count += 1 }
        }
    }
}

/// 只读本机环境检查。执行面被严格限制为：已存在的固定绝对路径 + 单一 `--version` 参数。
/// 不启动 shell、不继承用户命令、不访问网络、不写入磁盘，也不保留输出中的本地路径。
enum EnvironmentReporter {
    private static let timeout: TimeInterval = 2

    static func inspect(
        now: Date = Date(),
        pathLookup: ((EnvironmentComponent) -> String?)? = nil,
        versionReader: ((String) -> EnvironmentComponentStatus)? = nil
    ) -> EnvironmentReport {
        let lookup = pathLookup ?? executablePath(for:)
        let reader = versionReader ?? readVersion(at:)
        let entries = EnvironmentComponent.allCases.map { component in
            guard let path = lookup(component) else {
                return EnvironmentReportEntry(component: component, status: .unavailable)
            }
            return EnvironmentReportEntry(component: component, status: reader(path))
        }
        return EnvironmentReport(generatedAt: now, entries: entries)
    }

    static func executablePath(for component: EnvironmentComponent, fileManager: FileManager = .default) -> String? {
        component.candidatePaths.first { path in
            fileManager.fileExists(atPath: path) && fileManager.isExecutableFile(atPath: path)
        }
    }

    static func readVersion(at executablePath: String) -> EnvironmentComponentStatus {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executablePath)
        task.arguments = ["--version"]
        task.standardInput = FileHandle.nullDevice

        let output = Pipe()
        task.standardOutput = output
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            return .inspectionFailed
        }

        let deadline = Date().addingTimeInterval(timeout)
        while task.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if task.isRunning {
            task.terminate()
            task.waitUntilExit()
            return .inspectionFailed
        }

        guard task.terminationStatus == 0 else { return .inspectionFailed }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return .inspectionFailed }
        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !firstLine.isEmpty else { return .inspectionFailed }
        return .available(version: String(firstLine.prefix(120)))
    }
}

/// P2-C 的不可绕过边界，供测试、UI 和静态验证共同引用。
enum EnvironmentReportBoundary {
    static let onlyRunsOnExplicitUserAction = true
    static let onlyUsesFixedAbsolutePaths = true
    static let onlyUsesVersionArgument = true
    static let doesNotUseShell = true
    static let doesNotInstallOrModify = true
    static let doesNotPersistPathsOrResults = true
}
