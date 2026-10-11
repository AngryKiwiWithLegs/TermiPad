import Foundation

/// The only trusted channel for P2-B controlled install plans. Currently only statically reviewed Homebrew core formulae are allowed;
/// taps, casks, URLs, Git repositories, package-manager scripts, and commands assembled from network metadata are not supported.
enum ControlledInstallChannel: String, CaseIterable, Codable, Sendable {
    case homebrewCore

    func displayName(_ language: AppLanguage) -> String {
        switch (self, language) {
        case (.homebrewCore, .simplifiedChinese): return "Homebrew core formula"
        case (.homebrewCore, .english): return "Homebrew core formula"
        }
    }
}

/// An install plan built only from the static catalog shipped with the app.
/// `command` never comes from GitHub, a README, AI, or user input; showing the plan itself executes nothing.
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

/// Statically reviewed catalog. Remote candidates can only be compared by full repository name; even if the name is identical, there is no fallback to dynamic commands or fuzzy matching.
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
                catalogRevision: "2026.08.29.1",
                auditedAt: "2026-08-29",
                command: "brew install \(formula)"
            )
        }
    }

    /// Contains only interactive CLIs that were checked by hand; no package managers, system commands, background services, or script parts.
    private static let definitions: [Definition] = [
        .init(toolName: "bat", formula: "bat", repositoryFullName: "sharkdp/bat", expectedExecutableNames: ["bat"]),
        .init(toolName: "btop", formula: "btop", repositoryFullName: "aristocratos/btop", expectedExecutableNames: ["btop"]),
        .init(toolName: "bottom", formula: "bottom", repositoryFullName: "ClementTsang/bottom", expectedExecutableNames: ["btm"]),
        .init(toolName: "delta", formula: "git-delta", repositoryFullName: "dandavison/delta", expectedExecutableNames: ["delta"]),
        .init(toolName: "eza", formula: "eza", repositoryFullName: "eza-community/eza", expectedExecutableNames: ["eza"]),
        .init(toolName: "fzf", formula: "fzf", repositoryFullName: "junegunn/fzf", expectedExecutableNames: ["fzf"]),
        .init(toolName: "GitHub CLI", formula: "gh", repositoryFullName: "cli/cli", expectedExecutableNames: ["gh"]),
        .init(toolName: "gitui", formula: "gitui", repositoryFullName: "gitui-org/gitui", expectedExecutableNames: ["gitui"]),
        .init(toolName: "glow", formula: "glow", repositoryFullName: "charmbracelet/glow", expectedExecutableNames: ["glow"]),
        .init(toolName: "htop", formula: "htop", repositoryFullName: "htop-dev/htop", expectedExecutableNames: ["htop"]),
        .init(toolName: "lazygit", formula: "lazygit", repositoryFullName: "jesseduffield/lazygit", expectedExecutableNames: ["lazygit"]),
        .init(toolName: "yazi", formula: "yazi", repositoryFullName: "sxyazi/yazi", expectedExecutableNames: ["yazi"]),
        .init(toolName: "zoxide", formula: "zoxide", repositoryFullName: "ajeetdsouza/zoxide", expectedExecutableNames: ["zoxide"])
    ]

    /// Built once: the catalog is static, and the review page reads this list on every render.
    static let reviewedPlans: [ControlledInstallPlan] = definitions.compactMap { $0.makePlan() }

    static func isValidFormula(_ formula: String) -> Bool {
        let pattern = "^[a-z0-9][a-z0-9@+._-]*$"
        return formula.range(of: pattern, options: .regularExpression) != nil
    }

    /// Matches only the exact full GitHub repository name; a similar name, a README suggestion, or remote install copy never produces a plan.
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

/// The non-bypassable boundary of P2-B, referenced jointly by tests, the UI, and static verification.
enum ControlledInstallBoundary {
    static let doesNotRunInApp = true
    static let doesNotAutoCollectResult = true
    static let doesNotUseRemoteCommands = true
    static let doesNotSupportThirdPartyTaps = true
}
