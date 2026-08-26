# TermiPad 私人 Telegram 图标工具与 Bot 创建指南

**状态：设计与用户操作指南，不包含 Telegram 接入、网页托管或远程执行实现。**

## 目的与边界

本指南说明未来如何让 TermiPad 提供一个由用户自己管理的、私人图标工具目录：用户在 Mac 上添加并说明工具、挑选本地图标，并可逐项决定哪些已配置工具能出现在手机入口中。Telegram Mini App 只负责显示经过最小化处理的图标目录和发起固定的启动意图；它不是终端，也不接收、展示或构造任何 Shell 命令。

> **关键规则：Mac 永不开放公网端口；Telegram、Mini App 和网页不接触命令、参数、路径、变量、工作目录、密钥或终端输出。**

Telegram Bot 是一个 Telegram 内的专用账号；Mini App 是从该 Bot 打开的 HTTPS 网页界面；Mac 端桥接器则是最后一层本地授权者。这三个部分不能互相替代。Bot 不需要 Telegram Premium；Telegram 官方将 Bot 平台说明为对用户与开发者均可免费使用，但某个第三方 Bot 可以自行出售订阅或广告服务。[1]

## 三种推进方式

| 方案 | 用户体验 | 成本与复杂度 | 安全边界 |
|---|---|---|---|
| **M0：Mac 本地目录原型** | 在 TermiPad 内管理图标工具与“允许手机入口”开关；没有 Telegram | 无额外托管；最低 | 无网络；可完整验证工具授权、过期和防重放策略 |
| **M1：只读图标 Mini App 原型** | 在私人 Bot 内看到自己的图标网格；点击只显示演示确认，不影响 Mac | 需要一个 HTTPS 静态页面；低到中等 | 仅最小图标目录；没有 Bot token、没有 Mac 通信、没有终端动作 |
| **M2：私人受限启动入口** | 手机对一个已批准图标发起启动请求；Mac 再决定是否交接 | 需要 HTTPS 会话服务和 Mac 的长期出站轮询；中等 | Telegram 私聊允许列表、短期会话、nonce、过期、防重放、工具级授权和 Mac 本地二次确认 |

推荐顺序是 **M0 → M1 → M2**。M0 和 M1 可以先验证“我的图标工具面板是不是你想要的样子”；在用户明确批准之前，绝不配置真正 Bot token、网页服务或 Mac 端连接。

## 未来的“我的手机图标工具”功能

TermiPad 的工具记录仍是唯一真相来源。未来在设置的“手机入口”页面中，每个工具会有独立卡片和以下用户主动控制项：

| 控件 | 含义 | 默认值 |
|---|---|---|
| 本地图标 | 使用自定义 PNG；否则使用固定 SF Symbol 或稳定回退图标 | 沿用现有本地策略 |
| 手机显示名称 | 只用于手机网格，例如“项目同步” | 与本地工具名称一致 |
| 手机说明 | 一句非敏感用途说明，不含命令、路径或变量 | 空 |
| 在手机入口显示 | 决定该工具是否进入最小化目录 | **关闭** |
| 允许发起启动请求 | 仅允许已配对手机为该工具生成不透明 action | **关闭** |
| 本地确认 | 每次或按会话要求 Mac 用户确认，具体策略由用户选择 | **每次确认** |
| 撤销手机权限 | 立即使该工具的手机 action 失效 | 随时可用 |

手机端只会收到：稳定的 `toolID`、图标标识或经允许的缩略图、显示名、用途说明、可用/不可用的笼统状态，以及短期目录修订号。它永远不会收到工具真实命令、环境变量、路径、工作目录、运行日志或终端输出。自定义 PNG 默认仍只保存在 Mac；在用户逐项明确允许前，不上传到网页服务。

## 创建一个私人 Telegram Bot：只创建身份，不接入 Mac

以下步骤只会创建一个属于你的 Bot 身份。创建后 Bot 尚不会控制 TermiPad、不会读取 Mac，也不会自动响应消息。Telegram 官方说明，Bot token 等同于 Bot 的完全控制权，必须视同密码保存。[1]

1. 在自己的 Telegram 中搜索并打开官方 **[@BotFather](https://t.me/BotFather)**。请确认账户名称、认证标识和链接均为 `@BotFather`；不要向任何第三方“建 Bot 服务”发送验证码或 token。
2. 发送 `/newbot`，按提示设置显示名称，例如“TermiPad Private”。显示名称可以以后修改。
3. 按提示设置用户名。用户名通常以 `bot` 结尾；建议避免使用真实姓名、公司名或 Mac 名称，例如选择一个不公开个人信息的随机化用户名。
4. BotFather 会发出 token。**不要把 token 粘贴到聊天、邮件、截图、GitHub、网页表单或本项目 issue。**在尚未进入 M2 时，只需将其保存在你自己的密码管理器或 macOS 钥匙串；不要交给任何人。
5. 回到 BotFather，使用 `/setjoingroups`，选择刚创建的 Bot，再选择 **Disable**。TermiPad 只允许个人私聊，不允许加群。
6. 使用 `/setprivacy`，选择该 Bot，保持严格隐私模式；即使未来误加群，也不应把群消息当作输入来源。
7. 不要配置支付、广告、Telegram Stars、附件菜单、群组权限或 Business Mode。它们都不属于私人 TermiPad 入口的范围。
8. 此时可以对该 Bot 点击“开始”，但若尚未部署 M1 页面，它没有功能是正常且更安全的状态。

Mini App 的“Launch app / 启动应用”入口要等 M1 完成、拥有固定 HTTPS 地址后才设置。Telegram 官方支持在 BotFather 的 **My Bots → Bot Settings → Configure Mini App** 中配置主 Mini App；配置成功后会出现“Launch app”入口。[2] 这一步不能使用临时、陌生或带广告的第三方地址。

## M2 才可启用的连接原则

真正的受限启动入口必须同时满足以下规则：

| 层 | 只允许做什么 | 明确禁止 |
|---|---|---|
| Mini App 网页 | 显示最小目录；发送短期不透明 action 请求 | 自由文本命令、命令预览、参数编辑、终端输出、Mac 地址 |
| 会话服务 | 在服务端验证 Telegram `initData`；绑定允许用户和目录版本；发放短期会话 | 在前端验证 `initData`、存储 Bot token 于网页、向 Mac 发起入站连接 |
| Telegram Bot | 仅接收私聊中固定 callback/action；将请求交给本地轮询端 | 群聊、自由文本、文件、语音、照片、位置作为执行输入 |
| Mac | 使用**出站** `getUpdates` 长轮询并重新验证意图 | Webhook、入站公网端口、直接远程 Shell、PTY、输出回传 |

Telegram 的 `getUpdates` 长轮询与 webhook 互斥；TermiPad 选择前者，以避免为接收 Telegram 事件而在 Mac 上开公网入站服务。[3] Bot 接收到的文本、文件或其它聊天内容一律不构成命令来源。

## 用户可随时撤销

用户可以在 TermiPad 中逐工具关闭“在手机入口显示”或“允许发起启动请求”；此操作应立即使目录和所有未使用 action 失效。用户也可在 BotFather 中使用 `/revoke` 使旧 token 立刻失效，并更新本地密钥记录；完全弃用时使用 `/deletebot`。若手机遗失，应立即撤销对应配对和所有活跃会话，随后再更新 Bot token。

## 启动前检查清单

在真正开始 M2 前，必须逐项确认：只有一个明确允许的 Telegram 用户 ID；Bot 没有被加入群组；Bot token 已写入 Keychain 而非代码或日志；Mini App 使用固定 HTTPS origin 和严格内容安全策略；服务端验证 `initData` 与 `auth_date`；每个 action 都有工具白名单、会话绑定、nonce、过期与单次使用限制；Mac 只有出站轮询；任何失败默认拒绝；诊断记录不写命令、路径、变量、token 或输出。

## 参考资料

[1]: https://core.telegram.org/bots#how-do-i-create-a-bot "Telegram：Bots — 创建 Bot 与 token 安全"
[2]: https://core.telegram.org/bots/webapps#launching-the-main-mini-app "Telegram：Mini App 主入口与配置方式"
[3]: https://core.telegram.org/bots/api#getupdates "Telegram Bot API：getUpdates 与 webhook 互斥"
