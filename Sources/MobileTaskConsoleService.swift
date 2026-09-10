// M2b 任务会话中心（docs/m2b-remote-task-console-design.md §5）。
// 职责：聚合"会话条目流"（工具启动 + 固定任务统一时间线）并处理手机端
// 任务会话操作。数据最小化纪律：手机只见引用、显示名、状态枚举与退出码，
// 永不见 rootPath / 命令 / 参数 / 变量 / 工具启动的终端输出。
// M2b-1 范围：listScopes / listFixedTasks / getTaskStatus 三个只读操作 +
// 工具启动事件的条目记录。requestTaskProposal / cancelTask 在后续批次接入
// T0/T1 核验链（设计 §5.2），未接入前操作在分发层拒绝。
import Foundation
import SwiftData

@MainActor
final class MobileTaskConsoleService: ObservableObject {
    static let shared = MobileTaskConsoleService()

    /// 条目环缓冲上限（设计 §5.3）：手机一次 getTaskStatus 拿全量快照，
    /// ≤50 条 × 每条 ≤ 数百字节，远小于 64 KB 帧上限。
    static let entryLimit = 50
    /// 条目仅保留状态摘要的时限（设计 §5.3）：10 分钟后清 outputSnippet
    /// ——输出片段的驻留窗口由内存环自然约束。
    static let outputRetentionInterval: TimeInterval = 600

    struct SessionEntry: Identifiable, Equatable {
        let id: UUID
        let title: String
        let kind: MobileSessionEntry.SessionKind
        /// T1 TaskExecutionState 原样字符串 / 工具启动 launched|launchFailed。
        let executionState: String
        let exitCode: Int?
        let startedAt: Date
        var finishedAt: Date?
        var outputSnippet: String?

        var isFinished: Bool { finishedAt != nil }
    }

    @Published private(set) var entries: [SessionEntry] = []

    /// 与 MobileLaunchSession 同款测试模式：单例走系统时钟，测试注入
    /// 固定时钟获得隔离实例（单例状态不在测试间泄漏）。
    private let now: () -> Date

    init(now: @escaping () -> Date = { Date() }) {
        self.now = now
    }

    // MARK: - 条目流（工具启动事件接入）

    /// M1 requestLaunch 链的启动结果回调在此登记条目（TerminalLauncher
    /// 交接路径无退出码、无输出——这是红线，不是待办）。
    func recordToolLaunch(id: UUID, title: String, succeeded: Bool) {
        append(SessionEntry(
            id: id,
            title: title,
            kind: .toolLaunch,
            executionState: succeeded ? "launched" : "launchFailed",
            exitCode: nil,
            startedAt: now(),
            finishedAt: now(),
            outputSnippet: nil))
        DiagnosticsStore.shared.record(.mobileConsoleEntryRecorded)
    }

    /// T1 任务生命周期事件登记（M2b-3 接入 TaskExecutionCoordinator 后由其
    /// 调用；M2b-1 先落数据面）。输出片段仅档位 ≥ restricted 时由调用方
    /// 传入（§5.4 裁决在服务层，见 outputVisibility）。
    func recordTaskState(
        id: UUID,
        title: String,
        executionState: TaskExecutionState,
        exitCode: Int?,
        startedAt: Date?,
        finishedAt: Date?,
        outputSnippet: String?
    ) {
        let timestamp = now()
        let entry = SessionEntry(
            id: id,
            title: title,
            kind: .fixedTask,
            executionState: executionState.rawValue,
            exitCode: exitCode,
            startedAt: startedAt ?? timestamp,
            finishedAt: finishedAt,
            outputSnippet: currentVisibility == .minimal ? nil : outputSnippet)
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index] = entry
        } else {
            append(entry)
        }
    }

    private func append(_ entry: SessionEntry) {
        entries.insert(entry, at: 0)
        if entries.count > Self.entryLimit {
            entries.removeLast(entries.count - Self.entryLimit)
        }
    }

    /// 输出驻留时限到期即清片段（getTaskStatus 快照前统一回收）。
    private func sweepExpiredOutput(now: Date = Date()) {
        for index in entries.indices {
            guard entries[index].outputSnippet != nil,
                  let finished = entries[index].finishedAt,
                  now.timeIntervalSince(finished) > Self.outputRetentionInterval else {
                continue
            }
            entries[index].outputSnippet = nil
        }
    }

    // MARK: - 输出档位（设计 §5.4；Mac 是权威，UserDefaults 不进备份）

    enum OutputVisibility: String {
        case minimal
        case restricted
        case full
    }

    static let outputVisibilityDefaultsKey = "TermiPad.remoteOutputVisibility"

    var currentVisibility: OutputVisibility {
        OutputVisibility(rawValue: UserDefaults.standard.string(forKey: Self.outputVisibilityDefaultsKey) ?? "")
            ?? .restricted
    }

    // MARK: - 手机操作（分发层已过配对/解密；这里只做数据面）

    /// listScopes：已登记项目范围 → id + 显示名（rootPath 永不下发）。
    func scopeSummaries(modelContext: ModelContext) -> [MobileScopeSummary] {
        let descriptor = FetchDescriptor<TaskProjectScope>(
            predicate: #Predicate { !$0.isRevoked })
        let scopes = (try? modelContext.fetch(descriptor)) ?? []
        return scopes.map { MobileScopeSummary(id: $0.id, displayName: $0.displayName) }
    }

    /// listFixedTasks：固定目录字面量（kind + 用途 + 命令预览——全部是
    /// FixedTaskCatalog 已公开的目录信息，非用户数据）。
    func fixedTaskSummaries(language: AppLanguage) -> [MobileFixedTaskSummary] {
        FixedTaskCatalog.definitions.map { definition in
            MobileFixedTaskSummary(
                kind: definition.kind.rawValue,
                purpose: definition.purpose(language: language),
                commandPreview: definition.commandPreview)
        }
    }

    /// getTaskStatus：条目流全量快照（≤50 条，输出按档位与驻留时限裁决）。
    func sessionEntries(now: Date = Date()) -> [MobileSessionEntry] {
        sweepExpiredOutput(now: now)
        return entries.map { entry in
            MobileSessionEntry(
                id: entry.id,
                title: entry.title,
                kind: entry.kind,
                executionState: entry.executionState,
                exitCode: entry.exitCode,
                startedAt: entry.startedAt,
                finishedAt: entry.finishedAt,
                outputSnippet: currentVisibility == .minimal ? nil : entry.outputSnippet)
        }
    }
}
