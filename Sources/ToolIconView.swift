import SwiftUI

/// 图标策略：已识别的常用工具使用专属语义图标；未知工具从稳定的图形与色彩组合中派生回退图标。
struct ToolIconDefinition {
    let symbol: String
    let primaryColor: Color
    let secondaryColor: Color

    static let neutral = ToolIconDefinition(
        symbol: "terminal",
        primaryColor: .gray,
        secondaryColor: Color(nsColor: .controlAccentColor)
    )
}

enum ToolIconCatalog {
    private static let knownTools: [String: ToolIconDefinition] = [
        "claude": .init(symbol: "brain.head.profile", primaryColor: .orange, secondaryColor: .red),
        "codex": .init(symbol: "wand.and.stars", primaryColor: .green, secondaryColor: .teal),
        "gemini": .init(symbol: "sparkles", primaryColor: .blue, secondaryColor: .purple),
        "ollama": .init(symbol: "circle.hexagongrid.fill", primaryColor: .black, secondaryColor: .gray),
        "aider": .init(symbol: "hammer.fill", primaryColor: .indigo, secondaryColor: .purple),
        "gh": .init(symbol: "chevron.left.forwardslash.chevron.right", primaryColor: .black, secondaryColor: .gray),
        "lazygit": .init(symbol: "arrow.triangle.branch", primaryColor: .orange, secondaryColor: .yellow),
        "gitui": .init(symbol: "arrow.triangle.branch", primaryColor: .red, secondaryColor: .orange),
        "ffmpeg": .init(symbol: "film.fill", primaryColor: .purple, secondaryColor: .pink),
        "yt-dlp": .init(symbol: "arrow.down.to.line.compact", primaryColor: .red, secondaryColor: .orange),
        "imagemagick": .init(symbol: "wand.and.rays", primaryColor: .blue, secondaryColor: .purple),
        "fzf": .init(symbol: "scope", primaryColor: .blue, secondaryColor: .cyan),
        "ripgrep": .init(symbol: "magnifyingglass", primaryColor: .red, secondaryColor: .orange),
        "eza": .init(symbol: "folder.fill", primaryColor: .cyan, secondaryColor: .blue),
        "bat": .init(symbol: "doc.text.fill", primaryColor: .orange, secondaryColor: .brown),
        "btop": .init(symbol: "chart.bar.xaxis", primaryColor: .green, secondaryColor: .mint),
        "htop": .init(symbol: "waveform.path.ecg", primaryColor: .green, secondaryColor: .teal),
        "tmux": .init(symbol: "rectangle.split.3x1", primaryColor: .green, secondaryColor: .cyan),
        "kubectl": .init(symbol: "cube.transparent", primaryColor: .blue, secondaryColor: .indigo),
        "terraform": .init(symbol: "square.stack.3d.up.fill", primaryColor: .purple, secondaryColor: .indigo),
        "aws": .init(symbol: "cloud.fill", primaryColor: .orange, secondaryColor: .yellow),
        "vercel": .init(symbol: "triangle.fill", primaryColor: .black, secondaryColor: .gray),
        "netlify": .init(symbol: "network", primaryColor: .teal, secondaryColor: .cyan)
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

    static func definition(for toolName: String, category: ToolCategory) -> ToolIconDefinition {
        let normalizedName = toolName.lowercased()
        if let directMatch = knownTools[normalizedName] { return directMatch }
        if let partialMatch = knownTools.first(where: { normalizedName.contains($0.key) })?.value { return partialMatch }

        let stableIndex = abs(normalizedName.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) })
        let symbol = fallbackSymbols[stableIndex % fallbackSymbols.count]
        let palette = fallbackPalettes[(stableIndex / fallbackSymbols.count) % fallbackPalettes.count]
        return ToolIconDefinition(symbol: symbol, primaryColor: palette.0, secondaryColor: palette.1)
    }
}

/// 图标渲染优先级：GitHub 仓库组织头像（通常为官方品牌 Logo）→ 内置的工具专属图形 → 具有稳定差异的语义回退。
struct ToolIconView: View {
    let tool: TerminalTool
    let size: CGFloat

    private var definition: ToolIconDefinition {
        ToolIconCatalog.definition(for: tool.name, category: tool.category)
    }

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

            if let url = URL(string: tool.iconURLString ?? "") {
                AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
                    case .failure:
                        fallbackSymbol
                    case .empty:
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    @unknown default:
                        fallbackSymbol
                    }
                }
            } else {
                fallbackSymbol
            }
        }
        .frame(width: size, height: size)
        .shadow(color: definition.primaryColor.opacity(0.20), radius: 5, y: 2)
        .accessibilityLabel("\(tool.name) 图标")
    }

    private var fallbackSymbol: some View {
        Image(systemName: definition.symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
    }
}
