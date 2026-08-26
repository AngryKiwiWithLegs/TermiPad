import SwiftUI

/// P2-A 发现预览。页面只显示本地缓存或用户手动触发的公开仓库元数据；不会把远程条目写入工具库、候选收件箱或终端命令。
struct DiscoveryPreviewView: View {
    let language: AppLanguage

    @AppStorage("TermiPad.discoveryPreviewEnabled") private var isEnabled = false
    @State private var snapshot: DiscoveryCacheSnapshot?
    @State private var isRefreshing = false
    @State private var statusMessage: String?

    private var visibleItems: [DiscoveryItem] {
        guard let snapshot else { return [] }
        return DiscoveryRanking.visibleItems(from: snapshot.items)
    }

    var body: some View {
        Group {
            if !isEnabled {
                ContentUnavailableView {
                    Label(AppCopy.text("discoveryPreview", language: language), systemImage: "safari")
                } description: {
                    Text(AppCopy.text("discoveryDisabledDescription", language: language))
                } actions: {
                    Button(AppCopy.text("enableDiscoveryPreview", language: language)) {
                        isEnabled = true
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("discovery-enable-preview")
                }
                .accessibilityIdentifier("discovery-preview-disabled")
            } else if snapshot == nil {
                ContentUnavailableView {
                    Label(AppCopy.text("discoveryPreview", language: language), systemImage: "safari")
                } description: {
                    Text(AppCopy.text("discoveryEmptyDescription", language: language))
                } actions: {
                    refreshButton
                }
            } else {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(AppCopy.text("discoveryPreviewHint", language: language))
                                .font(.subheadline)
                            Text(AppCopy.text("discoveryNoInstallHint", language: language))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let snapshot {
                                Text(cacheStatus(for: snapshot))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if let statusMessage {
                                Text(statusMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    if snapshot?.isIncomplete == true {
                        Section {
                            Label(AppCopy.text("discoveryIncomplete", language: language), systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                                .font(.caption)
                        }
                    }

                    Section(AppCopy.text("discoveryResults", language: language)) {
                        ForEach(visibleItems) { item in
                            DiscoveryItemRow(item: item, language: language)
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .background(.clear)
            }
        }
        .navigationTitle(AppCopy.text("discoveryPreview", language: language))
        .toolbar {
            if isEnabled {
                ToolbarItem(placement: .primaryAction) {
                    refreshButton
                }
            }
        }
        .task {
            snapshot = DiscoveryCacheStore.load()
        }
        .accessibilityIdentifier("discovery-preview")
    }

    private var refreshButton: some View {
        Button {
            refresh()
        } label: {
            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Label(AppCopy.text("refreshDiscovery", language: language), systemImage: "arrow.clockwise")
            }
        }
        .disabled(isRefreshing || !isEnabled)
        .accessibilityIdentifier("discovery-refresh")
    }

    @MainActor
    private func refresh() {
        guard isEnabled, !isRefreshing else { return }
        isRefreshing = true
        statusMessage = nil
        let existingCache = DiscoveryCacheStore.load()

        Task {
            do {
                let result = try await DiscoveryService.refresh(cache: existingCache)
                switch result {
                case .refreshed(let updated):
                    DiscoveryCacheStore.save(updated)
                    snapshot = updated
                    DiagnosticsStore.shared.record(.discoveryRefreshed, itemCount: updated.items.count)
                    statusMessage = AppCopy.text("discoveryRefreshed", language: language)
                case .notModified(let cached):
                    snapshot = cached
                    DiagnosticsStore.shared.record(.discoveryCacheReused, itemCount: cached.items.count)
                    statusMessage = AppCopy.text("discoveryCacheCurrent", language: language)
                }
            } catch let error as DiscoveryService.Error {
                DiagnosticsStore.shared.record(.discoveryRefreshFailed)
                statusMessage = errorMessage(for: error)
            } catch {
                DiagnosticsStore.shared.record(.discoveryRefreshFailed)
                statusMessage = AppCopy.text("discoveryFailed", language: language)
            }
            isRefreshing = false
        }
    }

    private func cacheStatus(for snapshot: DiscoveryCacheSnapshot) -> String {
        let date = snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened)
        switch language {
        case .simplifiedChinese:
            return "本地缓存：\(date)"
        case .english:
            return "Local cache: \(date)"
        }
    }

    private func errorMessage(for error: DiscoveryService.Error) -> String {
        switch (error, language) {
        case (.rateLimited(let retryAfter), .simplifiedChinese):
            if let retryAfter {
                return "GitHub 暂时限制了刷新；请在 \(retryAfter.formatted(date: .omitted, time: .shortened)) 后重试。"
            }
            return "GitHub 暂时限制了刷新；请稍后手动重试。"
        case (.rateLimited(let retryAfter), .english):
            if let retryAfter {
                return "GitHub is temporarily rate limiting discovery. Try again after \(retryAfter.formatted(date: .omitted, time: .shortened))."
            }
            return "GitHub is temporarily rate limiting discovery. Try again manually later."
        default:
            return AppCopy.text("discoveryFailed", language: language)
        }
    }
}

private struct DiscoveryItemRow: View {
    let item: DiscoveryItem
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "terminal")
                    .foregroundStyle(.tint)
                Text(item.name)
                    .fontWeight(.semibold)
                Spacer()
                Text("★ \(item.starCount.formatted())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(item.summary?.isEmpty == false ? item.summary! : AppCopy.text("discoveryNoSummary", language: language))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Text(DiscoveryRanking.explanation(for: item, language: language))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if let licenseName = item.licenseName, !licenseName.isEmpty {
                    Label(licenseName, systemImage: "doc.text")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Label(AppCopy.text("discoveryNoLicense", language: language), systemImage: "questionmark.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Link(AppCopy.text("openRepository", language: language), destination: item.repositoryURL)
                    .font(.caption)
            }
        }
        .padding(.vertical, 5)
        .accessibilityIdentifier("discovery-item-\(item.repositoryID)")
    }
}
