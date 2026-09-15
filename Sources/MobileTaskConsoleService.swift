// M2b 任务会话中心（docs/m2b-remote-task-console-design.md §5）。
// 职责：聚合"会话条目流"（工具启动 + 固定任务统一时间线）并处理手机端
// 任务会话操作。数据最小化纪律：手机只见引用、显示名、状态枚举与退出码，
// 永不见 rootPath / 命令 / 参数 / 变量 / 工具启动的终端输出。
// M2b-1 范围：listScopes / listFixedTasks / getTaskStatus 三个只读操作 +
// 工具启动事件的条目记录。M2b-3：requestTaskProposal 核验链 + cancelTask。
import CoreGraphics
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

    // MARK: - M2b-3 任务提交核验链（设计 §5.2——顺序即攻击面检查顺序）

    /// requestTaskProposal 的完整核验与执行。返回给手机的最小回执。
    /// 1 配对有效性由握手层保证（进入这里即已配对）；此处从锁屏开始。
    func handleTaskProposal(
        taskKind: String?,
        projectScopeID: UUID?,
        modelContext: ModelContext,
        confirm: (String) async -> Bool
    ) async -> MobileTaskProposalResponse {
        // 3. 锁屏拒绝（防线 3）：Mac 锁屏期间不接受任何远程任务。
        if Self.isLoginSessionLocked() {
            DiagnosticsStore.shared.record(.remoteTaskBlockedScreenLocked)
            return MobileTaskProposalResponse(
                status: .rejected, reason: "Mac 处于锁屏状态，已拒绝远程任务。", taskIntentID: nil)
        }
        // 4. taskKind 白名单（FixedTaskCatalog 即攻击面）。
        guard let taskKind, let kind = TaskKind(rawValue: taskKind),
              let definition = FixedTaskCatalog.definition(for: kind) else {
            return MobileTaskProposalResponse(
                status: .rejected, reason: "未知的任务类型。", taskIntentID: nil)
        }
        // 5. scope 已登记、未撤销、目录可用。
        let scopeID = projectScopeID ?? UUID()
        var scopeDescriptor = FetchDescriptor<TaskProjectScope>(
            predicate: #Predicate { $0.id == scopeID })
        scopeDescriptor.fetchLimit = 1
        guard let scope = try? modelContext.fetch(scopeDescriptor).first,
              !scope.isRevoked, scope.directoryIsAvailable else {
            return MobileTaskProposalResponse(
                status: .rejected, reason: "项目范围不可用（未登记或已撤销）。", taskIntentID: nil)
        }
        // 6. T0 全策略核验：风险/窗口/nonce/过期。
        let intent = TaskIntentPolicy.makeIntent(scope: scope, kind: kind)
        let windows = (try? modelContext.fetch(FetchDescriptor<TaskReviewWindow>())) ?? []
        let existing = (try? modelContext.fetch(FetchDescriptor<TaskIntent>())) ?? []
        let decision = TaskIntentPolicy.review(
            intent, scope: scope, windows: windows, existingIntents: existing)
        guard case .allowed = decision else {
            // 拒绝原因映射为固定文案；具体 reason 写 diagMac（review() 是
            // 纯判定不落 rejectionReason——直接从 decision 取，2026-09-15：
            // 之前读 intent.rejectionReason 恒 nil）。
            let reason: TaskRejectionReason?
            if case .rejected(let r) = decision { reason = r } else { reason = nil }
            let text = Self.rejectionText(reason)
            DiagnosticsStore.shared.record(.remoteTaskRejectedByPolicy)
            MobilePairingService.diagMac("手机任务被 T0 策略拒绝：\(reason?.rawValue ?? "未知")")
            return MobileTaskProposalResponse(
                status: .rejected, reason: text, taskIntentID: nil)
        }
        // 7. 确认档位（M1.1 三档推广）：lowRisk 且 risk==.low 命中白名单
        //    免确认；其余弹 60 秒本机确认。
        let needsConfirmation: Bool
        switch definition.risk {
        case .low:
            needsConfirmation = !(MobileLaunchSession.shared.canSkipConfirmation(
                policy: .lowRiskSessionOnly, toolID: intent.id, commandTemplate: definition.commandPreview))
        case .standard:
            needsConfirmation = true
        }
        if needsConfirmation {
            let accepted = await confirm(definition.purpose(language: .simplifiedChinese))
            guard accepted else {
                DiagnosticsStore.shared.record(.remoteTaskRejectedByUser)
                return MobileTaskProposalResponse(
                    status: .rejected, reason: "Mac 上拒绝了本次任务。", taskIntentID: nil)
            }
            MobileLaunchSession.shared.recordConfirmation(toolID: intent.id)
        } else {
            DiagnosticsStore.shared.record(.mobileTaskAutoConfirmed)
        }
        // 8. approve → T1 执行（固定 executable/参数/超时/可停止/空 stdin）。
        _ = TaskIntentPolicy.approve(intent, scope: scope, windows: windows, existingIntents: existing)
        try? modelContext.insert(intent)
        let title = definition.purpose(language: .simplifiedChinese)
        let started = TaskExecutionCoordinator.shared.start(intent: intent, scope: scope) {}
        if case .rejected(let rejection) = started {
            // 精确反馈（2026-09-10 用户要求）：预检失败必须说明缺什么——
            // 红线允许回传"任务的固定目录要求"（FixedTaskCatalog 字面量，
            // 非用户数据），不允许回传 scope 路径本身。
            let missingPaths = definition.requiredRelativePaths.filter { relative in
                !FileManager.default.fileExists(
                    atPath: URL(fileURLWithPath: scope.rootPath, isDirectory: true)
                        .appendingPathComponent(relative).path)
            }
            let reason: String
            if !missingPaths.isEmpty {
                reason = "目标目录缺少该任务必需的文件：\(missingPaths.joined(separator: "、"))。请登记一个包含这些文件的项目目录。"
            } else {
                reason = "任务启动预检未通过（所需可执行文件在本机不存在，或目标目录不可用）。"
            }
            MobilePairingService.diagMac("手机任务启动预检拒绝：\(rejection.rawValue)，缺文件=\(missingPaths.count)")
            return MobileTaskProposalResponse(status: .rejected, reason: reason, taskIntentID: intent.id)
        }
        recordTaskState(
            id: intent.id, title: title, executionState: intent.executionState,
            exitCode: nil, startedAt: intent.executionStartedAt, finishedAt: nil,
            outputSnippet: nil)
        return MobileTaskProposalResponse(
            status: .accepted, reason: nil, taskIntentID: intent.id)
    }

    /// T0 拒绝原因 → 手机端固定文案（无路径无命令——枚举语义，不是数据）。
    private static func rejectionText(_ reason: TaskRejectionReason?) -> String {
        switch reason {
        case .localReviewRequired: return "Mac 上没有开启活跃的项目审阅窗口。"
        case .reviewWindowExpired: return "项目审阅窗口已过期，请在 Mac 上重新开启。"
        case .riskNotPermitted: return "任务风险等级超出审阅窗口允许范围。"
        case .projectScopeUnavailable: return "项目范围不可用（未登记或已撤销）。"
        case .unknownTaskKind: return "未知的任务类型。"
        case .taskExpired: return "任务建议已过期。"
        case .taskNotPending: return "任务不在待审状态。"
        case .nonceReplayed: return "任务请求重放，已拒绝。"
        case .taskCancelled: return "任务已被取消。"
        default: return "任务被本地策略拒绝（\(reason?.rawValue ?? "未知原因")）。"
        }
    }

    /// Mac 登录会话锁屏检测（防线 3）。CGSessionCopyCurrentDictionary 单点
    /// 守卫（verify-macos.sh 白名单仅本文件）。
    nonisolated static func isLoginSessionLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            // 取不到会话字典（无 GUI/异常环境）按保守处理：视为锁屏。
            return true
        }
        if let locked = session["CGSSessionScreenIsLocked"] as? Bool {
            return locked
        }
        return false
    }

    // MARK: - M2b-3 cancelTask（设计 §5.1：仅手机提交且 running 的任务）

    /// 取消运行中的任务。手机只能停 T1 任务（工具启动是终端交接，停止
    /// 权在终端侧——不新增执行入口）。
    func cancelTask(taskIntentID: UUID) -> MobileTaskProposalResponse {
        let coordinator = TaskExecutionCoordinator.shared
        if coordinator.runningIntentIDs.contains(taskIntentID) {
            // 找回 intent 对象由 coordinator 内部 activeIntents 管理；
            // stop 需要 intent——通过条目登记生命周期即可停进程。
            if let intent = coordinator.intent(forID: taskIntentID) {
                coordinator.stop(intent: intent)
                return MobileTaskProposalResponse(
                    status: .accepted, reason: nil, taskIntentID: taskIntentID)
            }
        }
        return MobileTaskProposalResponse(
            status: .rejected, reason: "任务不在运行中，无法停止。", taskIntentID: nil)
    }
}
