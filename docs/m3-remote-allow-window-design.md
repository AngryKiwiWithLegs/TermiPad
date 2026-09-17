# M3 远程允许窗口设计——每日解锁 + 免确认信任窗

**状态：** 设计评审稿（2026-09-14）。先评审后实现；本文不宣称任何能力已实现。

**上位文档：** `docs/product-roadmap.md` §5 阶段 6（M3）；`docs/m2b-remote-task-console-design.md` §4 防线 3（本设计是其"每日本机解锁"项的落地）与 §9 衔接预告。

**要解决的问题：** M2b 真机使用确认了北极星场景成立，但每次远程操作都要 Mac 端确认——人不在 Mac 前时这条防线反而是死锁（这正是 M2a 设计文档 §1 预言的"死锁问题"）。M3 给**清醒的在 Mac 前的用户**一个一次性授权手段：今天出门前点一下，之后整天手机操作免确认。

## 1. 核心语义：每日解锁（Daily Unlock）

```
用户在 Mac 前（早上出门前）：
  设置 → 手机伴侣 → 「开启今日远程窗口」→ 触摸 ID/密码确认 → 窗口开启
  ├─ 有效期：到当日 24:00（自然日界）或用户手动关闭，先到者
  ├─ 窗口内：手机 requestLaunch / requestTaskProposal **免 Mac 确认**直接执行
  │   （仍受：锁屏拒绝、30 天时效、速率限制、白名单、T0 策略全核验）
  └─ 即时失效条件（任一触发窗口立即关闭）：
     Mac 锁屏 / 睡眠 / app 退出 / 用户点关闭 / 设备撤销
```

**与 M1.1 perSession 的关系**：`MobileLaunchSession`（5 分钟白名单）保留并升级为其内部实现——每日解锁把"5 分钟"换成"到当日 24:00"，语义同构（进程内存、不落盘、随时作废）。M3 是 `MobileLaunchSession` 的推广而非替换。

## 2. 明确不做（红线）

- **不落盘**：窗口状态只存进程内存（同 M1.1）。app 重启即关——"重启后重新开一次窗口"是可接受的摩擦，换来"磁盘上永远不存在长期免确认凭据"
- **不随 tailnet 端点下发**：手机端不知道窗口状态，Mac 是唯一权威——窗口关了手机下次请求自然被拒（文案明确"今日远程窗口未开启"）
- **不做"永久免确认"**：窗口最长到当日 24:00，跨天必须重新解锁
- **lowRisk 白名单不受影响**：M1.1 的 lowRiskSessionOnly 5 分钟窗与每日窗口并存，取并集

## 3. Mac 端设计

### 3.1 `RemoteAllowWindow`（新文件 Sources/RemoteAllowWindow.swift）

```swift
@MainActor
final class RemoteAllowWindow: ObservableObject {
    static let shared = RemoteAllowWindow()
    /// 窗口开启时刻；nil = 关闭。进程内存，不落盘。
    @Published private(set) var openedAt: Date?
    /// 解锁时刻（单独记录——锁屏即失效，解锁后需重新开门，见 §3.2）
    private var unlockedAt: Date?

    var isOpen: Bool          // openedAt != nil 且未跨自然日
    func open(authenticated: Bool)   // authenticated=false 直接拒绝——调用方负责 LAContext
    func close()                     // 用户手动/锁屏/撤销时调用
    func invalidateOnLock()          // 锁屏钩子
}
```

### 3.2 生命周期钩子

| 事件 | 动作 |
|---|---|
| 用户点「开启今日远程窗口」 | LAContext `.deviceOwnerAuthentication`（触摸 ID/密码）通过 → `open()`；诊断 `remoteAllowWindowOpened` |
| 用户点「关闭」 | `close()`；诊断 `remoteAllowWindowClosed` |
| Mac 锁屏（`CGSessionCopyCurrentDictionary` 变化，轮询 5s） | `invalidateOnLock()`——**锁屏即关窗**（偷Mac者锁不了你的窗口） |
| app 启动 | 不恢复（内存态自然丢失） |
| 设备撤销 / 配对关闭 | `close()`（挂入既有撤销链） |

### 3.3 执行链接入（两处各 +3 行）

`handleLaunchRequest` 与 `handleTaskProposal` 的确认环节改为：

```
确认档位判定 → 命中 M1.1 白名单？→ 免确认（不变）
            → RemoteAllowWindow.isOpen？→ 免确认（新，诊断 remoteAllowWindowUsed）
            → else 弹 60s 确认（不变）
```

**锁屏检查保持在前**：窗口开着但 Mac 锁屏 → 仍然拒绝（防线不因窗口降级）。

### 3.4 UI（PreferencesView 手机伴侣 Section）

```
[今日远程窗口：已关闭 / 剩余 6h12m]
[开启今日远程窗口]（触摸 ID）   [关闭]
hint: 开启后今天内手机操作免本机确认。Mac 锁屏或重启后自动关闭。
       首次解锁仍需触摸 ID——窗口只是免去"每次操作都确认"。
```

## 4. 协议与手机端

**零协议变更**：窗口状态不下发、不进 MacResumeHello。手机端唯一变化是**拒绝文案**新增一种："今日远程窗口未开启，请在 Mac 上开启后重试"（复用现有 reason 字段，固定文案）。UI 上手机无需任何改动——行为透明。

## 5. 安全分析（窗口开着时的暴露面）

| 防线 | 窗口开启时是否仍有效 |
|---|---|
| Face ID app 锁（手机） | ✅ 不变 |
| 凭据 30 天时效 | ✅ 不变 |
| 锁屏拒绝 | ✅ **加强**：锁屏即关窗 |
| 速率限制（每分钟 10 次） | ✅ 不变 |
| T0 策略全核验（范围/风险/窗口/超时） | ✅ 不变（跳过的只是"本机确认"这一步） |
| 白名单/确认档位 | lowRisk 并集语义 |
| 撤销 | ✅ 关窗 + 吊销 |
| 输出档位/脱敏 | ✅ 不变 |

**残余风险（用户知情接受）**：窗口开启期间，拿到已解锁手机 + Mac 未锁屏的人可免确认执行固定目录内任务。缓解：自然日界 + 锁屏即关 + 撤销即时。这正是"每日解锁"的产品语义。

## 6. 验收清单（G7，真机）

| # | 验证项 | 通过标准 |
|---|---|---|
| 1 | 开窗 | 触摸 ID 后窗口显示剩余时长；诊断事件落盘 |
| 2 | 免确认 | 窗口内手机提交任务/点工具 → 直接执行（无确认弹窗）|
| 3 | 仍受防线 | 窗口内 Mac 锁屏 → 操作被拒且窗口关闭；重新解锁后窗口不再开启（需重开）|
| 4 | 关窗 | 手动关闭后手机操作回到每操作确认 |
| 5 | 跨天 | 窗口开启状态跨 24:00 → 次日请求被拒（文案"今日远程窗口未开启"）|
| 6 | 重启失效 | Mac app 重启 → 窗口已关（内存态丢失）|
| 7 | 撤销联动 | 撤销设备 → 窗口关闭 |
| 8 | 红线复核 | 窗口状态不落盘、不进备份、不进诊断内容；协议无新增字段 |
