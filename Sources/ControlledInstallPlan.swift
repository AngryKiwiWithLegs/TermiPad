import Foundation

/// P2-B 受控安装计划的唯一受信渠道。当前仅允许静态审核的 Homebrew core formula，
/// 不支持 tap、cask、URL、Git 仓库、包管理器脚本或由网络元数据拼接的命令。
enum ControlledInstallChannel: String, CaseIterable, Codable, Sendable {
    case homebrewCore

    func displayName(_ language: AppLanguage) -> String {
        switch (self, language) {
        case (.homebrewCore, .simplifiedChinese): return "Homebrew core formula"
        case (.homebrewCore, .english): return "Homebrew core formula"
        }
    }
}

/// 仅由随应用发布的静态目录构造的安装计划。
/// `command` 永远不来自 GitHub、README、AI 或用户输入；展示计划本身不会执行任何内容。
struct ControlledInstallPlan: Identifiable, Equatable, Sendable {
    let id: String
    let toolName: String
    let formula: String
    let repositoryFullName: String
    let channel: ControlledInstallChannel
    let expectedExecutableNames: [String]
    let catalogRevision: String
    let auditedAt: String
    let command: String

    func title(language: AppLanguage) -> String {
        switch language {
        case .simplifiedChinese: return "安装计划：\(toolName)"
        case .english: return "Install plan: \(toolName)"
        }
    }

    func safetySummary(language: AppLanguage) -> String {
        switch language {
        case .simplifiedChinese:
            return "命令来自 TermiPad 内置审核目录。提交到终端后仍由 Homebrew 下载并执行其自身安装流程；TermiPad 不会在应用内执行、也不会自动收录结果。"
        case .english:
            return "The command comes from TermiPad’s built-in reviewed catalog. Once sent to a terminal, Homebrew still downloads and runs its own install flow; TermiPad does not execute it in-app or add the result automatically."
        }
    }
}

/// 静态审核目录。远程候选只能按完整仓库名比对；即使名称相同，也不能回退为动态命令或模糊匹配。
enum ControlledInstallCatalog {
    private struct Definition: Sendable {
        let toolName: String
        let formula: String
        let repositoryFullName: String
        let expectedExecutableNames: [String]

        func makePlan() -> ControlledInstallPlan? {
            guard ControlledInstallCatalog.isValidFormula(formula) else { return nil }
            return ControlledInstallPlan(
                id: "homebrew-core:\(formula)",
                toolName: toolName,
                formula: formula,
                repositoryFullName: repositoryFullName,
                channel: .homebrewCore,
                expectedExecutableNames: expectedExecutableNames,
                catalogRevision: "2026.08.25.1",
                auditedAt: "2026-08-25",
                command: "brew install \(formula)"
            )
        }
    }

    /// 只含已人工核对的交互式 CLI；不包含包管理器、系统命令、后台服务或脚本零件。
    private static let definitions: [Definition] = [
        .init(toolName: "bat", formula: "bat", repositoryFullName: "sharkdp/bat", expectedExecutableNames: ["bat"]),
        .init(toolName: "btop", formula: "btop", repositoryFullName: "aristocratos/btop", expectedExecutableNames: ["btop"]),
        .init(toolName: "bottom", formula: "bottom", repositoryFullName: "ClementTsang/bottom", expectedExecutableNames: ["btm"]),
        .init(toolName: "delta", formula: "git-delta", repositoryFullName: "dandavison/delta", expectedExecutableNames: ["delta"]),
        .init(toolName: "eza", formula: "eza", repositoryFullName: "eza-community/eza", expectedExecutableNames: ["eza"]),
        .init(toolName: "fzf", formula: "fzf", repositoryFullName: "junegunn/fzf", expectedExecutableNames: ["fzf"]),
        .init(toolName: "GitHub CLI", formula: "gh", repositoryFullName: "cli/cli", expectedExecutableNames: ["gh"]),
        .init(toolName: "gitui", formula: "gitui", repositoryFullName: "extrawurst/gitui", expectedExecutableNames: ["gitui"]),
        .init(toolName: "glow", formula: "glow", repositoryFullName: "charmbracelet/glow", expectedExecutableNames: ["glow"]),
        .init(toolName: "htop", formula: "htop", repositoryFullName: "htop-dev/htop", expectedExecutableNames: ["htop"]),
        .init(toolName: "lazygit", formula: "lazygit", repositoryFullName: "jesseduffield/lazygit", expectedExecutableNames: ["lazygit"]),
        .init(toolName: "yazi", formula: "yazi", repositoryFullName: "sxyazi/yazi", expectedExecutableNames: ["yazi"]),
        .init(toolName: "zoxide", formula: "zoxide", repositoryFullName: "ajeetdsouza/zoxide", expectedExecutableNames: ["zoxide"])
    ]

    static var reviewedPlans: [ControlledInstallPlan] {
        definitions.compactMap { $0.makePlan() }
    }

    static func isValidFormula(_ formula: String) -> Bool {
        let pattern = "^[a-z0-9][a-z0-9@+._-]*$"
        return formula.range(of: pattern, options: .regularExpression) != nil
    }

    /// 仅按 GitHub 完整仓库名精确匹配；任何名称相似、README 建议或远程安装文案均不会产生计划。
    static func plan(forRepositoryFullName repositoryFullName: String) -> ControlledInstallPlan? {
        definitions.first {
            $0.repositoryFullName.caseInsensitiveCompare(repositoryFullName) == .orderedSame
        }?.makePlan()
    }

    static func plan(forFormula formula: String) -> ControlledInstallPlan? {
        definitions.first {
            $0.formula.caseInsensitiveCompare(formula) == .orderedSame
        }?.makePlan()
    }
}

/// P2-B 的不可绕过边界，供测试、UI 和静态验证共同引用。
enum ControlledInstallBoundary {
    static let doesNotRunInApp = true
    static let doesNotAutoCollectResult = true
    static let doesNotUseRemoteCommands = true
    static let doesNotSupportThirdPartyTaps = true
}
