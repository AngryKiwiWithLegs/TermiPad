import AppKit
import SwiftUI

/// Icon strategy: recognized common tools use dedicated semantic icons; unknown tools store a local fallback style identifier; the user's local PNG always takes priority.
struct ToolIconDefinition {
    let styleIdentifier: String
    let symbol: String
    let primaryColor: Color
    let secondaryColor: Color

    static let neutral = ToolIconDefinition(
        styleIdentifier: "neutral.terminal",
        symbol: "terminal",
        primaryColor: .gray,
        secondaryColor: Color(nsColor: .controlAccentColor)
    )
}

struct ToolIconChoice: Identifiable {
    let id: String
    let definition: ToolIconDefinition
    let chineseName: String
    let englishName: String

    func displayName(language: AppLanguage) -> String {
        language == .simplifiedChinese ? chineseName : englishName
    }
}

enum ToolIconCatalog {
    private static let knownTools: [String: ToolIconDefinition] = [
        "claude": definition("known.claude", "brain.head.profile", .orange, .red),
        "codex": definition("known.codex", "wand.and.stars", .green, .teal),
        "gemini": definition("known.gemini", "sparkles", .blue, .purple),
        "ollama": definition("known.ollama", "circle.hexagongrid.fill", .black, .gray),
        "aider": definition("known.aider", "hammer.fill", .indigo, .purple),
        "gh": definition("known.gh", "chevron.left.forwardslash.chevron.right", .black, .gray),
        "lazygit": definition("known.lazygit", "arrow.triangle.branch", .orange, .yellow),
        "gitui": definition("known.gitui", "arrow.triangle.branch", .red, .orange),
        "git": definition("known.git", "arrow.triangle.branch", .red, .brown),
        "delta": definition("known.delta", "text.line.first.and.arrowtriangle.forward", .purple, .indigo),
        "ffmpeg": definition("known.ffmpeg", "film.fill", .purple, .pink),
        "yt-dlp": definition("known.yt-dlp", "arrow.down.to.line.compact", .red, .orange),
        "imagemagick": definition("known.imagemagick", "wand.and.rays", .blue, .purple),
        "magick": definition("known.magick", "wand.and.rays", .blue, .purple),
        "fzf": definition("known.fzf", "scope", .blue, .cyan),
        "ripgrep": definition("known.ripgrep", "magnifyingglass", .red, .orange),
        "rg": definition("known.rg", "magnifyingglass", .red, .orange),
        "eza": definition("known.eza", "folder.fill", .cyan, .blue),
        "bat": definition("known.bat", "doc.text.fill", .orange, .brown),
        "btop": definition("known.btop", "chart.bar.xaxis", .green, .mint),
        "htop": definition("known.htop", "waveform.path.ecg", .green, .teal),
        "tmux": definition("known.tmux", "rectangle.split.3x1", .green, .cyan),
        "kubectl": definition("known.kubectl", "cube.transparent", .blue, .indigo),
        "terraform": definition("known.terraform", "square.stack.3d.up.fill", .purple, .indigo),
        "aws": definition("known.aws", "cloud.fill", .orange, .yellow),
        "vercel": definition("known.vercel", "triangle.fill", .black, .gray),
        "netlify": definition("known.netlify", "network", .teal, .cyan),
        "act": definition("known.act", "play.rectangle.fill", .blue, .indigo),
        "glow": definition("known.glow", "text.book.closed.fill", .orange, .pink),
        "httpie": definition("known.httpie", "network.badge.shield.half.filled", .blue, .cyan),
        "just": definition("known.just", "checklist", .green, .mint),
        "task": definition("known.task", "checkmark.circle.fill", .teal, .cyan),
        "nvim": definition("known.nvim", "text.cursor", .green, .teal),
        "vim": definition("known.vim", "text.cursor", .green, .teal),
        "zed": definition("known.zed", "text.and.command.macwindow", .indigo, .blue),
        "code": definition("known.code", "chevron.left.forwardslash.chevron.right", .blue, .indigo)
    ]

    private static let fallbackSymbols = [
        "terminal.fill", "cube.fill", "command", "slider.horizontal.3", "bolt.fill",
        "wand.and.stars", "gearshape.2.fill", "memorychip.fill", "network", "shippingbox.fill",
        "lock.shield.fill", "doc.zipper", "antenna.radiowaves.left.and.right", "dial.medium"
    ]

    private static let fallbackPalettes: [(Color, Color)] = [
        (.blue, .cyan), (.purple, .indigo), (.teal, .mint), (.orange, .red),
        (.pink, .purple), (.green, .teal), (.brown, .orange), (.indigo, .blue)
    ]

    static let manualChoices: [ToolIconChoice] = [
        choice("manual.terminal", "terminal.fill", .gray, .blue, "终端", "Terminal"),
        choice("manual.command", "command", .indigo, .blue, "命令", "Command"),
        choice("manual.code", "chevron.left.forwardslash.chevron.right", .blue, .indigo, "代码", "Code"),
        choice("manual.ai", "brain.head.profile", .orange, .red, "智能体", "Agent"),
        choice("manual.git", "arrow.triangle.branch", .red, .orange, "版本控制", "Version control"),
        choice("manual.search", "magnifyingglass", .blue, .cyan, "搜索", "Search"),
        choice("manual.media", "film.fill", .purple, .pink, "媒体", "Media"),
        choice("manual.image", "photo.fill", .teal, .mint, "图像", "Image"),
        choice("manual.folder", "folder.fill", .cyan, .blue, "文件夹", "Folder"),
        choice("manual.cloud", "cloud.fill", .orange, .yellow, "云", "Cloud"),
        choice("manual.package", "shippingbox.fill", .brown, .orange, "包", "Package"),
        choice("manual.system", "gearshape.2.fill", .gray, .indigo, "系统", "System"),
        choice("manual.health", "waveform.path.ecg", .green, .teal, "状态", "Status"),
        choice("manual.security", "lock.shield.fill", .indigo, .purple, "安全", "Security"),
        choice("manual.network", "network", .teal, .cyan, "网络", "Network"),
        choice("manual.document", "doc.text.fill", .orange, .brown, "文档", "Document")
    ]

    static func definition(for toolName: String, category: ToolCategory) -> ToolIconDefinition {
        if let directMatch = knownDefinition(for: toolName) { return directMatch }
        return definition(forFallbackStyleIdentifier: fallbackStyleIdentifier(for: toolName))
    }

    static func definition(for tool: TerminalTool) -> ToolIconDefinition {
        if let styleIdentifier = tool.iconStyleIdentifier,
           let choice = manualChoices.first(where: { $0.id == styleIdentifier }) {
            return choice.definition
        }
        if let directMatch = knownDefinition(for: tool.name) { return directMatch }
        if let styleIdentifier = tool.iconStyleIdentifier,
           isFallbackStyleIdentifier(styleIdentifier) {
            return definition(forFallbackStyleIdentifier: styleIdentifier)
        }
        return definition(forFallbackStyleIdentifier: fallbackStyleIdentifier(for: tool.name))
    }

    static func automaticStyleIdentifier(for toolName: String) -> String? {
        knownDefinition(for: toolName) == nil ? fallbackStyleIdentifier(for: toolName) : nil
    }

    static func isAutomaticFallbackTool(_ tool: TerminalTool) -> Bool {
        knownDefinition(for: tool.name) == nil
            && !manualChoices.contains(where: { $0.id == tool.iconStyleIdentifier })
    }

    /// Unknown tools use a stable hash of the name; if a combination is already taken, the next one is chosen in a fixed order.
    static func fallbackStyleIdentifier(for toolName: String, occupiedIdentifiers: Set<String> = []) -> String {
        let seed = stableHash(normalizedToolName(toolName))
        for offset in 0..<fallbackCombinationCount {
            let identifier = fallbackStyleIdentifier(at: (seed + offset) % fallbackCombinationCount)
            if !occupiedIdentifiers.contains(identifier) { return identifier }
        }
        return fallbackStyleIdentifier(at: seed % fallbackCombinationCount)
    }

    /// Old records may have no style field. This method writes a stable identifier only for automatic fallback icons and uses the UUID as the deterministic tie-break order for records with the same name.
    @discardableResult
    static func normalizeFallbackAssignments(for tools: [TerminalTool]) -> Bool {
        let automaticTools = tools
            .filter { isAutomaticFallbackTool($0) }
            .sorted {
                let leftHasExistingStyle = $0.iconStyleIdentifier.map(isFallbackStyleIdentifier) ?? false
                let rightHasExistingStyle = $1.iconStyleIdentifier.map(isFallbackStyleIdentifier) ?? false
                if leftHasExistingStyle != rightHasExistingStyle { return leftHasExistingStyle }
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                let nameOrder = normalizedToolName($0.name).localizedCompare(normalizedToolName($1.name))
                return nameOrder == .orderedSame ? $0.id.uuidString < $1.id.uuidString : nameOrder == .orderedAscending
            }
        var occupied: Set<String> = []
        var changed = false

        for tool in automaticTools {
            let currentIdentifier = tool.iconStyleIdentifier
            let identifier: String
            if let currentIdentifier,
               isFallbackStyleIdentifier(currentIdentifier),
               !occupied.contains(currentIdentifier) {
                identifier = currentIdentifier
            } else {
                identifier = fallbackStyleIdentifier(for: tool.name, occupiedIdentifiers: occupied)
            }
            let expectedSymbol = definition(forFallbackStyleIdentifier: identifier).symbol
            if tool.iconStyleIdentifier != identifier || tool.iconSymbol != expectedSymbol {
                tool.iconStyleIdentifier = identifier
                tool.iconSymbol = expectedSymbol
                changed = true
            }
            occupied.insert(identifier)
        }
        return changed
    }

    private static var fallbackCombinationCount: Int { fallbackSymbols.count * fallbackPalettes.count }

    private static func knownDefinition(for toolName: String) -> ToolIconDefinition? {
        let normalizedName = normalizedToolName(toolName)
        if let directMatch = knownTools[normalizedName] { return directMatch }
        // A name can contain several keys, and dictionary order changes between launches, so "first match"
        // could give the same tool a different icon each time. Always take the longest key, then the alphabetically first.
        let containedKey = knownTools.keys
            .filter { normalizedName.contains($0) }
            .min { left, right in
                left.count != right.count ? left.count > right.count : left < right
            }
        return containedKey.flatMap { knownTools[$0] }
    }

    private static func definition(forFallbackStyleIdentifier identifier: String) -> ToolIconDefinition {
        let parts = identifier.split(separator: ".")
        guard parts.count == 3,
              parts[0] == "fallback",
              let symbolIndex = Int(parts[1]),
              let paletteIndex = Int(parts[2]),
              fallbackSymbols.indices.contains(symbolIndex),
              fallbackPalettes.indices.contains(paletteIndex) else {
            return .neutral
        }
        let palette = fallbackPalettes[paletteIndex]
        return definition(identifier, fallbackSymbols[symbolIndex], palette.0, palette.1)
    }

    private static func fallbackStyleIdentifier(at index: Int) -> String {
        let symbolIndex = index % fallbackSymbols.count
        let paletteIndex = (index / fallbackSymbols.count) % fallbackPalettes.count
        return "fallback.\(symbolIndex).\(paletteIndex)"
    }

    private static func isFallbackStyleIdentifier(_ identifier: String) -> Bool {
        definition(forFallbackStyleIdentifier: identifier).styleIdentifier == identifier
    }

    private static func normalizedToolName(_ toolName: String) -> String {
        toolName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stableHash(_ value: String) -> Int {
        let hash = value.unicodeScalars.reduce(0) { partial, scalar in
            partial &* 31 &+ Int(scalar.value)
        }
        return hash & Int.max
    }

    private static func definition(_ identifier: String, _ symbol: String, _ primary: Color, _ secondary: Color) -> ToolIconDefinition {
        ToolIconDefinition(styleIdentifier: identifier, symbol: symbol, primaryColor: primary, secondaryColor: secondary)
    }

    private static func choice(_ identifier: String, _ symbol: String, _ primary: Color, _ secondary: Color, _ chineseName: String, _ englishName: String) -> ToolIconChoice {
        ToolIconChoice(
            id: identifier,
            definition: definition(identifier, symbol, primary, secondary),
            chineseName: chineseName,
            englishName: englishName
        )
    }
}

/// Icon rendering uses only controlled local PNGs, built-in SF Symbols, and local colors; brand or owner avatars are never loaded from the network.
struct ToolIconView: View {
    let tool: TerminalTool
    let size: CGFloat

    private var definition: ToolIconDefinition {
        ToolIconCatalog.definition(for: tool)
    }

    private var customImage: NSImage? {
        ToolIconStore.shared.image(named: tool.customIconFilename)
    }

    var body: some View {
        ZStack {
            if let customImage {
                Image(nsImage: customImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            } else {
                ToolIconDefinitionView(definition: definition, size: size)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: definition.primaryColor.opacity(0.20), radius: 5, y: 2)
        .accessibilityLabel("\(tool.name) icon")
    }
}

struct ToolIconDefinitionView: View {
    let definition: ToolIconDefinition
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [definition.primaryColor, definition.secondaryColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: definition.symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}
