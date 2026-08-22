import Foundation

/// 终端工具扫描与过滤引擎。扫描只负责找出候选；最终是否收录由用户在候选收件箱中决定。
enum ToolScanner {
    /// 需要排除的系统自带、包管理器、后台服务和脚本零件。
    private static let blacklistedCommands: Set<String> = [
        "grep", "curl", "ls", "ssh", "git", "cd", "pwd", "echo", "cat", "rm", "mv", "cp", "sudo", "awk", "sed", "jq", "find", "xargs", "sort", "head", "tail", "tee", "tar", "gzip", "unzip",
        "npm", "pnpm", "yarn", "pip", "pip3", "brew", "cargo", "gem", "apt", "apt-get", "go", "conda", "uv",
        "docker", "docker-compose", "redis-server", "postgres", "mysqld", "nginx", "mongod", "httpd",
        "sh", "bash", "zsh", "fish", "python", "python3", "node", "ruby", "perl", "swift", "env", "which"
    ]

    private static let systemDirectories: Set<String> = ["/bin", "/sbin", "/usr/bin", "/usr/sbin"]

    /// 常见第三方 CLI 安装路径；PATH 仍是最高优先级来源。
    private static var supplementalSearchPaths: [String] {
        let home = NSHomeDirectory()
        return [
            "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/local/sbin",
            "\(home)/.local/bin", "\(home)/.bin", "\(home)/bin", "\(home)/.cargo/bin",
            "\(home)/.bun/bin", "\(home)/.npm-global/bin", "\(home)/.local/share/pnpm"
        ]
    }

    static func scanInstalledTools() -> [(name: String, path: String)] {
        let fileManager = FileManager.default
        let environmentPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let orderedPaths = orderedUnique(environmentPaths + supplementalSearchPaths)
        var discovered: [String: String] = [:]

        for directory in orderedPaths {
            let normalizedDirectory = (directory as NSString).standardizingPath
            guard !systemDirectories.contains(normalizedDirectory),
                  fileManager.fileExists(atPath: normalizedDirectory),
                  let children = try? fileManager.contentsOfDirectory(atPath: normalizedDirectory) else {
                continue
            }

            for name in children where isCandidateFileName(name) {
                let path = (normalizedDirectory as NSString).appendingPathComponent(name)
                guard !shouldExclude(commandName: name), fileManager.isExecutableFile(atPath: path) else { continue }
                if discovered[name] == nil { discovered[name] = path }
            }
        }

        return discovered
            .map { (name: $0.key, path: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func shouldExclude(commandName: String) -> Bool {
        let normalized = commandName.lowercased()
        return blacklistedCommands.contains(normalized)
            || normalized.hasPrefix(".")
            || normalized.hasSuffix(".d")
            || normalized.hasSuffix(".py")
            || normalized.hasSuffix(".js")
    }

    static func guessCategory(for toolName: String) -> ToolCategory {
        let keywordGroups: [(ToolCategory, [String])] = [
            (.ai, ["claude", "gpt", "gemini", "ollama", "openai", "llama", "chat", "agent", "aider", "codex"]),
            (.media, ["ffmpeg", "yt-dlp", "sox", "imagemagick", "convert", "mplayer", "video", "audio"]),
            (.efficiency, ["ripgrep", "rg", "fzf", "bat", "eza", "fd", "tmux", "screen", "htop", "btop", "zoxide", "yazi"]),
            (.system, ["network", "http", "dns", "vpn", "sshuttle", "tailscale", "nmap", "ping"]),
            (.development, ["gh", "rustc", "gcc", "make", "cmake", "kubectl", "terraform", "vagrant", "vercel", "netlify"])
        ]
        let lowercaseName = toolName.lowercased()
        return keywordGroups.first(where: { group in
            group.1.contains(where: lowercaseName.contains)
        })?.0 ?? .other
    }

    private static func orderedUnique(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.compactMap { rawPath in
            let path = (rawPath as NSString).standardizingPath
            return seen.insert(path).inserted ? path : nil
        }
    }

    private static func isCandidateFileName(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix(".") && !name.contains("/")
    }
}
