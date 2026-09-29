// M3 每日远程允许窗口（docs/m3-remote-allow-window-design.md）。
// 用户早上出门前在 Mac 上触摸 ID 开一次"今日远程窗口"，当天手机操作
// 免本机确认——解决"人不在 Mac 前每操作确认"的死锁（M2a §1 预言）。
// 红线：窗口状态**纯进程内存**不落盘（磁盘上永远不存在长期免确认凭据）；
// 跨自然日必须重新解锁；Mac 锁屏即关窗；Mac 是唯一权威（协议零变更，
// 手机端无感知——窗口关闭后请求自然被拒，回执文案明确）。
import Foundation

@MainActor
final class RemoteAllowWindow: ObservableObject {
    static let shared = RemoteAllowWindow()

    /// 窗口开启时刻；nil = 关闭。进程内存，不落盘。
    @Published private(set) var openedAt: Date?

    /// 窗口最长跨度：到当日 24:00（自然日界）。
    static let dayBoundary: Calendar = .current

    var isOpen: Bool {
        guard let openedAt else { return false }
        // 跨自然日即失效（即便 app 跨午夜一直运行）。
        return Self.dayBoundary.isDate(openedAt, inSameDayAs: Date())
    }

    /// 距当日 24:00 的剩余秒数（UI 显示"剩余 X 小时"）；关闭态为 0。
    var secondsRemaining: TimeInterval {
        guard isOpen, let openedAt else { return 0 }
        let endOf = Self.dayBoundary.startOfDay(for: openedAt)
            .addingTimeInterval(24 * 3600)
        return max(0, endOf.timeIntervalSince(Date()))
    }

    /// 开窗。authenticated=false 直接拒绝——调用方负责本机认证验证，
    /// 本方法不做认证（单一职责：认证在 UI 层，窗口只管状态）。
    func open(authenticated: Bool, now: Date = Date()) {
        guard authenticated else { return }
        openedAt = now
        DiagnosticsStore.shared.record(.remoteAllowWindowOpened)
    }

    /// 关窗（用户手动 / 设备撤销 / 配对关闭）。
    func close() {
        guard openedAt != nil else { return }
        openedAt = nil
        DiagnosticsStore.shared.record(.remoteAllowWindowClosed)
        // M6：窗口关闭即杀 PTY shell（设计 §3 生命周期绑定）。
        TerminalRemoteService.shared.invalidateOnWindowClose()
    }

    /// 锁屏钩子：锁屏即关窗（防"偷 Mac 者锁不了你的窗口"）。
    /// 与开窗事件区分诊断；重复调用无害。
    func invalidateOnLock() {
        guard openedAt != nil else { return }
        openedAt = nil
        DiagnosticsStore.shared.record(.remoteAllowWindowLocked)
        // M6：锁屏即杀 PTY（设计 §3）。
        TerminalRemoteService.shared.invalidateOnWindowClose()
    }

    /// 免确认裁决：执行链调用。窗口开 + 当日 = 免本机确认。
    /// T0 策略核验/锁屏拒绝/速率限制/时效**不在本裁决内**——调用方
    /// 顺序：锁屏检查 → 速率限制 → T0 核验 → 确认档位（此处）。
    func allowsSkipConfirmation(now: Date = Date()) -> Bool {
        guard let openedAt else { return false }
        return Self.dayBoundary.isDate(openedAt, inSameDayAs: now)
    }
}
