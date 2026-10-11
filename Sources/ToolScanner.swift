import Foundation

/// Terminal tool scanning and filtering engine. Scanning only finds candidates; whether they are accepted is decided by the user in the review inbox.
enum ToolScanner {
    /// System built-ins, package managers, background services, and script parts to exclude.
    private static let blacklistedCommands: Set<String> = [
        "grep", "curl", "ls", "ssh", "git", "cd", "pwd", "echo", "cat", "rm", "mv", "cp", "sudo", "awk", "sed", "jq", "find", "xargs", "sort", "head", "tail", "tee", "tar", "gzip", "unzip",
        "npm", "pnpm", "yarn", "pip", "pip3", "brew", "cargo", "gem", "apt", "apt-get", "go", "conda", "uv",
        "docker", "docker-compose", "redis-server", "postgres", "mysqld", "nginx", "mongod", "httpd",
        "sh", "bash", "zsh", "fish", "python", "python3", "node", "ruby", "perl", "swift", "env", "which"
    ]

    /// Directories installed by Apple with the system or Xcode / Command Line Tools. Their contents are build parts or system helper commands,
    /// not the user-installed, interactive CLIs TermiPad should offer to collect.
    private static let excludedPathPrefixes = [
        "/bin", "/sbin", "/usr/bin", "/usr/sbin",
        "/Library/Apple/usr", "/Library/Developer/CommandLineTools", "/Library/Developer/Toolchains",
        "/Applications/Xcode.app/Contents/Developer", "/System/Library"
    ]

    /// Common third-party CLI install paths; PATH is still the highest-priority source.
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
            let normalizedDirectory = normalizedPath(directory)
            guard !isExcludedInstallationPath(normalizedDirectory),
                  fileManager.fileExists(atPath: normalizedDirectory),
                  let children = try? fileManager.contentsOfDirectory(atPath: normalizedDirectory) else {
                continue
            }

            for name in children where isCandidateFileName(name) {
                let path = (normalizedDirectory as NSString).appendingPathComponent(name)
                guard isEligibleExecutable(named: name, at: path, fileManager: fileManager) else { continue }
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
            || normalized.hasSuffix(".sh")
    }

    /// Install-path rules that can be verified directly in unit tests. Paths are standardized so `/usr/bin-tools` is not mistaken for `/usr/bin`.
    static func isExcludedInstallationPath(_ path: String) -> Bool {
        let normalized = normalizedPath(path)
        return excludedPathPrefixes.contains { prefix in
            normalized == prefix || normalized.hasPrefix(prefix + "/")
        }
    }

    /// Resolves symlinks to the real target. A wrapper command in the user's directory that ultimately points to Apple's developer toolchain should not become a candidate either.
    static func resolvedExecutablePath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
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

    private static func isEligibleExecutable(named name: String, at path: String, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        guard !shouldExclude(commandName: name),
              fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              fileManager.isExecutableFile(atPath: path) else {
            return false
        }

        let resolvedPath = resolvedExecutablePath(path)
        return !isExcludedInstallationPath(resolvedPath)
    }

    private static func orderedUnique(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.compactMap { rawPath in
            let path = normalizedPath(rawPath)
            return seen.insert(path).inserted ? path : nil
        }
    }

    private static func normalizedPath(_ path: String) -> String {
        (path as NSString).standardizingPath
    }

    private static func isCandidateFileName(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix(".") && !name.contains("/")
    }
}
