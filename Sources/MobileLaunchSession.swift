// M1.1 会话白名单（docs/m0-m1-mobile-entry-design.md §3.3.2 增补 2026-09-08）。
// perSession / lowRiskSessionOnly 策略的免确认判定：Mac 内存中的 [toolID: 确认时间]，
// 不落盘、不进备份，生命周期绝不超出 Mac 主进程。
// 纯逻辑、无网络无持久化——时钟可注入，单测无需等待真实时间。
import Foundation

@MainActor
final class MobileLaunchSession {
    /// 会话窗长度：超时未刷新即失效（设计文档固定 5 分钟，无永不过期选项）。
    static let sessionWindow: TimeInterval = 5 * 60

    static let shared = MobileLaunchSession()

    private var confirmedAt: [UUID: Date] = [:]
    private let now: () -> Date

    init(now: @escaping () -> Date = { Date() }) {
        self.now = now
    }

    /// 判定是否可免确认直启。调用方已保证资格预检通过（含 revokeMobilePermissionAt == nil）。
    /// - Parameters:
    ///   - policy: 工具的本地确认策略
    ///   - toolID: 目标工具
    ///   - commandTemplate: 该工具的命令模板——lowRiskSessionOnly 额外要求
    ///     无 shell 元字符（资格预检已保证无模板变量；这里是第二道防线）
    func canSkipConfirmation(
        policy: MobileLocalConfirmPolicy,
        toolID: UUID,
        commandTemplate: String
    ) -> Bool {
        guard let lastConfirmed = confirmedAt[toolID],
              now().timeIntervalSince(lastConfirmed) <= Self.sessionWindow else {
            return false
        }
        switch policy {
        case .everyTime:
            return false
        case .perSession:
            return true
        case .lowRiskSessionOnly:
            return !Self.containsShellMetacharacters(commandTemplate)
        }
    }

    /// 本机确认通过后刷新该工具的会话时间戳（每次 everyTime 弹窗成功都调用——
    /// 刷新而非插入，保证 perSession 与 lowRisk 从同一次确认起算）。
    func recordConfirmation(toolID: UUID) {
        confirmedAt[toolID] = now()
    }

    /// 立即失效：Mac 撤销工具手机权限、用户关闭配对监听时调用。
    func invalidate(toolID: UUID) {
        confirmedAt[toolID] = nil
    }

    func invalidateAll() {
        confirmedAt.removeAll()
    }

    /// lowRisk 第二道防线：出现 shell 元字符即不再视为低风险。
    /// 与资格预检的无变量检查互补——预检挡变量，这里挡注入用元字符。
    private static func containsShellMetacharacters(_ template: String) -> Bool {
        let metacharacters: Set<Character> = [";", "|", "&", "`", "$", ">", "<", "\\", "'", "\"", "("]
        return template.contains { metacharacters.contains($0) }
    }
}
