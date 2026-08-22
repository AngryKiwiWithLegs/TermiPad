import Foundation

/// 终端工具扫描与过滤引擎
class ToolScanner {
    
    /// 需要排除的系统自带/包管理器/后台服务黑名单
    private static let blacklistedCommands: Set<String> = [
        // 系统自带/基础命令
        "grep", "curl", "ls", "ssh", "git", "cd", "pwd", "echo", "cat", "rm", "mv", "cp", "sudo", "awk", "sed", "jq",
        // 包管理器
        "npm", "pnpm", "yarn", "pip", "pip3", "brew", "cargo", "gem", "apt", "apt-get", "brew", "go",
        // 后台服务/守护进程
        "docker", "docker-compose", "redis-server", "postgres", "mysqld", "nginx", "mongod",
        // 常见 shell 内部/脚本工具
        "sh", "bash", "zsh", "fish", "python", "python3", "node", "ruby", "perl", "swift"
    ]
    
    /// 常见的开发者二进制路径
    private static let searchPaths: [String] = [
        "/opt/homebrew/bin",
        "/opt/homebrew/sbin",
        "/usr/local/bin",
        "/usr/local/sbin",
        NSHomeDirectory() + "/.local/bin",
        NSHomeDirectory() + "/.bin",
        NSHomeDirectory() + "/bin"
    ]
    
    /// 扫描 $PATH 及常见目录，返回候选工具名称及路径
    static func scanInstalledTools() -> [(name: String, path: String)] {
        var discoveredTools: [(name: String, path: String)] = []
        let fileManager = FileManager.default
        
        // 获取环境变量 PATH
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        var allPaths = envPath.components(separatedBy: ":")
        allPaths.append(contentsOf: searchPaths)
        
        // 去重
        let uniquePaths = Array(Set(allPaths))
        
        for dirPath in uniquePaths {
            guard fileManager.fileExists(atPath: dirPath) else { continue }
            guard let enumerator = fileManager.enumerator(atPath: dirPath) else { continue }
            
            while let fileName = enumerator.nextObject() as? String {
                // 不递归深层子目录，只看第一层或直接在 bin 下的可执行文件
                if fileName.contains("/") { continue }
                
                let fullPath = (dirPath as NSString).appendingPathComponent(fileName)
                
                // 检查是否在黑名单中
                if shouldExclude(commandName: fileName) { continue }
                
                // 检查是否可执行
                if fileManager.isExecutableFile(atPath: fullPath) {
                    // 排除符号链接指向系统目录或重复收录
                    discoveredTools.append((name: fileName, path: fullPath))
                }
            }
        }
        
        // 按工具名称去重
        var uniqueDict: [String: String] = [:]
        for tool in discoveredTools {
            if uniqueDict[tool.name] == nil {
                uniqueDict[tool.name] = tool.path
            }
        }
        
        return uniqueDict.map { (name: $0.key, path: $0.value) }.sorted { $0.name < $1.name }
    }
    
    /// 判断命令是否应从图标化启动器中排除。
    /// 包含系统基础命令、包管理器、守护进程和脚本运行时。
    static func shouldExclude(commandName: String) -> Bool {
        blacklistedCommands.contains(commandName.lowercased())
    }

    /// 智能初筛：根据名称或特征分配合适的默认分类
    static func guessCategory(for toolName: String) -> ToolCategory {
        let aiKeywords = ["claude", "gpt", "gemini", "ollama", "openai", "llama", "chat", "agent", "ai"]
        let mediaKeywords = ["ffmpeg", "yt-dlp", "sox", "imagemagick", "convert", "mplayer"]
        let devKeywords = ["git", "gh", "cargo", "rustc", "go", "gcc", "make", "cmake", "docker", "kubectl", "terraform", "node", "python"]
        let efficiencyKeywords = ["ripgrep", "rg", "fzf", "bat", "eza", "fd", "tmux", "screen", "htop", "btop", "zoxide"]
        
        let lowerName = toolName.lowercased()
        
        if aiKeywords.contains(where: { lowerName.contains($0) }) {
            return .ai
        } else if mediaKeywords.contains(where: { lowerName.contains($0) }) {
            return .media
        } else if devKeywords.contains(where: { lowerName.contains($0) }) {
            return .development
        } else if efficiencyKeywords.contains(where: { lowerName.contains($0) }) {
            return .efficiency
        } else {
            return .other
        }
    }
}
