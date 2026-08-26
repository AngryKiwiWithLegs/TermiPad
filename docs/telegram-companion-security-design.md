# TermiPad Telegram Companion 安全设计

**状态：** 可行性与受限试点设计完成；未进入代码实现。

## 1. 结论

Telegram Bot **可以**成为 TermiPad 的手机入口，但只能作为一个由第三方云端转发的、受限的遥控界面，不能作为终端接口。它比同网本地配对更方便：人在异地、手机不与 Mac 位于同一局域网时也能发起请求；但它也引入 Telegram 云端、Bot token、持续运行的 Mac 连接、Telegram 账号允许列表和消息元数据等新信任边界。

因此，推荐把 Telegram 定义为 **“Telegram Companion Preview”**，而不是默认产品能力。首发试点只允许一个或多个明确绑定的私人 Telegram 账号，在私聊中点击由 Bot 提供的固定按钮。按钮只代表本机已经允许的工具 UUID，Mac 仍是最终策略执行者。机器人文本、用户消息、命令参数、文件、图片、语音、链接、转发内容和自由输入一律不进入启动流程。

> Telegram 不是端到端的 TermiPad 控制通道。任何发送给 Bot 的信息都经过 Telegram 的服务；因此绝不能在 Bot 消息、按钮 payload 或回复中承载命令、变量、路径、工作目录、API Key、终端输出或备份数据。

## 2. 传输选择：只用长轮询，不开公网 Webhook

Telegram Bot API 有两种互斥的接收更新方式：`getUpdates` 长轮询或 Webhook。[1] 对 TermiPad 试点，应选择 **长轮询**：运行中的 Mac 应用从本机主动通过 HTTPS 连接 Telegram 取得更新，不暴露任何公网监听端口、域名或反向代理。

Webhook 不适合首发试点。Webhook 要求 Telegram 向一个 HTTPS URL 推送更新，官方文档还说明它需要有效 TLS 证书、受支持端口与正确域名配置。[2] 这会迫使 TermiPad 或用户维护公网入口，扩大了被扫描、伪造请求、运维失误和服务暴露的面积。即使 API 支持 `secret_token` 请求头校验，也不应把它当作远程终端控制的首选架构。[1]

长轮询也有明确代价：TermiPad 必须在 Mac 上保持运行（可作为菜单栏常驻应用），且 Mac 必须有网络连接。若 App 退出、Mac 休眠、断网或注销，Bot 应只显示固定的“Mac 不在线”，不能排队积累可延迟执行的终端请求。Telegram 官方指出更新最多在服务端保留 24 小时；本产品不得把这段窗口当作延迟执行队列。[1]

## 3. 首发交互：私聊、固定键盘、固定动作

Bot 只支持 Telegram 私聊，拒绝群组、频道、inline mode、深链接携带动作、文件/媒体、文本命令和语音输入。Telegram 的 Bot 特性允许使用 inline keyboard；按下这类按钮不会发送普通聊天消息，而会产生 callback 交互。[3] 这适合展示一个由 Mac 主动发布的工具按钮列表，但按钮数据必须是短期、一次性、不可猜测的 opaque action token，而不是工具名、命令或参数。

每条 Bot 更新都必须经过以下验证，任何一步失败都只返回固定拒绝状态：

1. Bot token 所属会话已由 Mac 用户明确启用，并仅存于 Mac Keychain。
2. 更新来自私聊，且 `from.id` 与 Mac 本地允许列表匹配；不以 Telegram 昵称、用户名或聊天标题做身份判断。
3. 更新类型只能是预期的 callback；所有文本 message、编辑消息、文件、图片、链接和未知 update type 直接忽略。
4. callback action token 必须存在于 Mac 内存中的短期 action 表，绑定允许的 Telegram 用户、工具 UUID、策略版本、消息 ID、nonce 与过期时间。
5. token 使用一次即失效；Mac 保存近期 callback ID/nonce 以拒绝重放，并限速拒绝连续请求。
6. Mac 按本地工具 UUID 重新读取工具，重新检查健康状态、远程授权、无变量限制和目标终端可用性；永不信任按钮数据中的任何业务字段。
7. 终端交接仍走 `TerminalLauncher`；若自动化权限拒绝则只报告“需要 Mac 本地处理/已安全复制”，不向 Telegram 返回命令或终端输出。

Telegram 官方也明确提醒，后端必须自行验证收到的命令是否有效、发送者是否被授权，不能仅依赖 Bot 的 command scope。[3]

## 4. 权限模型与固定状态

| 模式 | 默认值 | Telegram 能做 | Mac 端必经保护 |
|---|---|---|---|
| 状态查看 | 默认关闭，用户启用后可用 | 查看最小化的在线状态、已授权工具图标和固定状态 | 不显示命令、路径、变量或终端输出 |
| 请求启动 | 默认可选 | 点击一个已授权工具按钮 | Mac 弹出本地确认；未确认不交接终端 |
| 短期远程启动窗口 | 默认关闭 | 启动逐项授权、无变量的工具 | 时限、设备/账号允许列表、健康检查、nonce、速率限制、立即撤销 |

Bot 回复只能采用固定状态类别：`Mac 不在线`、`等待 Mac 确认`、`请求被策略拒绝`、`工具不可用`、`已交给所选终端`、`已复制，需要在 Mac 处理`。不得返回命令、变量、工作目录、路径、版本、stdout/stderr、退出码或错误堆栈。

受控安装计划、环境报告、工具编辑、候选收件箱、扫描、备份恢复、设置变更和图标上传在 Telegram 试点中均永久禁用。它们涉及供应链、隐私或本地数据变更，必须留在 Mac 的本地 UI。

## 5. 密钥、隐私与撤销

Bot token 相当于 Bot API 的认证凭据；Telegram 文档说明每个 Bot 都有唯一认证 token，所有 Bot API 请求都以该 token 作为 URL 的一部分。[1] 因此 token 只存 Mac Keychain，不写入 `UserDefaults`、SwiftData、JSON 备份、诊断包、日志、截图、UI 文案或 Git 仓库。用户应能在 Mac 上一键关闭 Bot、清除 token、撤销单个 Telegram 用户、撤销全部用户，以及让所有短期 action token 立即失效。

TermiPad 的本地诊断只记录固定计数类别：Bot 启用/停用、连接建立/中断、授权拒绝、callback 接受/拒绝、过期/replay 拒绝和启动交接结果类别。它不记录 Telegram user ID、chat ID、Bot token、工具名、命令、路径或消息正文。

## 6. 与同网本地配对方案对比

| 维度 | 同网本地配对 | Telegram Companion Preview |
|---|---|---|
| 异地可用 | 否 | 是，只要 Mac 应用运行且联网 |
| 公网入站端口 | 不需要 | 不需要（长轮询） |
| 第三方云端依赖 | 无 | 有，Telegram 负责消息传输与账号体系 |
| 手机 App | 需要开发原生 App | 不必开发，直接使用 Telegram |
| 设备认证 | 本地设备密钥与配对 | Telegram 用户允许列表 + Mac 本地 action token；仍需本地策略校验 |
| 机密信息边界 | 可使用本地 TLS 保护 | 只允许最小化、非敏感状态；不传命令和输出 |
| Mac 常驻要求 | 本地监听/受控模式 | App 必须运行并长轮询；退出或睡眠即离线 |
| 适合场景 | 隐私优先、同一地点 | 个人远程触发少量已授权工具 |

## 7. 可验证的试点阶段

| 阶段 | 范围 | 必须通过的验收 |
|---|---|---|
| **T0：无网络策略原型** | action token、允许列表、过期、nonce、重放拒绝、工具级授权状态机 | 单元测试覆盖伪造 callback、未知用户、群聊、文本输入、过期、重放、变量工具和安装计划拒绝 |
| **T1：个人 Bot 长轮询预览** | Mac 菜单栏受控开关、Keychain token、仅私聊 callback、固定状态回复 | Token 不出 Keychain/备份/诊断；退出/休眠不延迟执行；关闭即撤销所有 token |
| **T2：逐次 Mac 确认** | Telegram 请求只在 Mac 本地确认后交接终端 | 用户未点击确认、工具不健康、自动化拒绝或终端不可用时安全失败 |
| **T3：短期远程启动窗口** | 明确选择的无变量工具、有限时段、每项工具独立授权 | 过期、撤销、账户变更、重放、网络重连后均拒绝或要求重新授权 |
| **T4：多用户/群组/云服务** | 不在当前路线 | 必须重新审计隐私、运营、滥用、审计和外部发行责任 |

## 8. 当前建议

如果目标是你个人在外出时偶尔点击已知工具，Telegram 方案可以作为**受限个人预览**，且比自建 iPhone App 更快验证产品价值。但不建议直接实现“点什么就运行什么”。应先完成 **T0**，确认 action token 和本地策略层能够拒绝所有文本、参数、变量、安装和重放攻击，再决定是否开始 T1。

如果你优先考虑隐私、离线局域网和最小第三方依赖，应优先继续此前的同网本地配对 R0/R1。两种方案可以共享“本地启动意图策略层”，但不能共享认证方式或把 Telegram Bot 当作可信命令源。

## References

[1]: https://core.telegram.org/bots/api "Telegram Bot API"
[2]: https://core.telegram.org/bots/faq "Telegram Bots FAQ"
[3]: https://core.telegram.org/bots/features "Telegram Bot Features"
