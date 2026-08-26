# TermiPad Telegram Mini App 图标化入口设计

**状态：** 可行性与受限试点设计完成；未进入代码实现。

## 1. 结论

Telegram Mini App 可以在 Telegram 内呈现真正的图标化工具面板。它是一个嵌入 Telegram 的 HTML/CSS/JavaScript 界面，不是普通 Bot 的文本键盘。Telegram 官方将 Mini Apps 定义为可在 Telegram 内启动的灵活 JavaScript 界面；它们能够使用移动端主题、颜色、安全区域和全屏布局，因此可以制作紧凑的 TermiPad 工具图标网格。[1]

这能保留 TermiPad 最重要的体验：手机上看到图标、名称与最小化状态，点击图标请求 Mac 启动已授权工具。普通 Bot 的 inline/reply keyboard 可以提供文字或 emoji 按钮，但不能提供真实品牌/本地图标网格；因此若“图标化”是硬需求，Mini App 是 Telegram 路线中唯一合适的界面层。

不过 Mini App 增加了一个新的、不可省略的外部组件：它必须从受信的 HTTPS Web 地址加载。该网页绝不能成为 Mac 的远程终端 API；也不能接触终端命令、路径、变量、工作目录、密钥或输出。Mini App 只显示一个经过最小化处理的、短期可撤销的图标目录，并只产生不透明的启动请求。

## 2. 三种手机入口的体验与架构差异

| 入口 | 图标化程度 | 外部基础设施 | 是否能异地使用 | 推荐定位 |
|---|---|---|---|---|
| 纯 Telegram Bot | 低：文字/emoji 按钮 | Telegram Bot token；Mac 长轮询 | 可以 | 最快的安全动作原型 |
| Telegram Mini App | 高：可做图标网格、分组、状态卡 | Telegram Bot + HTTPS 静态网页 + 最小化会话服务 | 可以 | **若坚持 Telegram 图标体验，推荐的受限路线** |
| 原生 iPhone Companion | 最高：真正原生 iOS 图标库与离线能力 | iOS App + 配对/服务 | 取决于网络架构 | 长期产品体验最佳 |

## 3. 推荐交互：Mini App 只发“启动意图”，Mac 仍是权威执行者

```text
用户在 Telegram 打开 Mini App
          │
          ▼
HTTPS 页面显示最小化图标目录
（图标、短名称、可用/不可用；不含命令）
          │
          ▼
点击图标 → 发送短期 opaque action token
          │
          ▼
Telegram Bot / 最小化会话服务验证 Mini App initData
          │
          ▼
Mac 的长轮询仅接收已验证的“启动意图”
          │
          ▼
Mac 本地重新验证账号、token、工具 UUID、健康状态与授权
          │
          ▼
Mac 本地确认或短期远程窗口 → TerminalLauncher
```

Mini App 不直接连接 Mac，也不接收 Mac 的任何监听地址。Mac 不开放端口，不注册 Webhook，只通过 `getUpdates` 进行向外长轮询。Telegram Bot API 将长轮询与 Webhook 规定为互斥方式；这种设计选择避免为了 Mini App 而暴露 Mac 公网服务。[2]

## 4. 图标目录的最小化数据模型

Mini App 页面只能取得一份短期、只读的目录快照。每一项只有以下字段：

| 允许字段 | 禁止字段 |
|---|---|
| 随机化的临时 catalog item ID | 完整工具 UUID（如可被枚举） |
| 本地图标库的 symbol/颜色标识，或经缩放后的受控 PNG 引用 | 图标原始文件路径、EXIF、原始高分辨率文件 |
| 短名称（用户可选择隐藏或改为别名） | 命令、参数、模板、描述中可能含路径/机密的文字 |
| 固定类别、固定状态（可用/需要 Mac 确认/离线） | 工作目录、健康检查详情、版本、终端目标、API Key、诊断信息 |
| 短期 action token | 任何可重放的永续启动标识 |

目录快照应由 Mac 在明确启用 Telegram Companion 后生成，生命周期不超过短期会话；Mac 关闭 Companion、休眠、撤销账号、切换 Bot token 或策略变化时立即使目录和所有 token 失效。网页不得存储目录到 analytics、日志、浏览器 local storage、第三方 CDN 或任意跨站脚本。

## 5. HTTPS 网页和身份验证边界

Mini App 是网页，因此必须接受“网页源是新的攻击面”这一事实。首发应采用单一、固定、无第三方脚本的 HTTPS 域名，内容安全策略禁止第三方 `script`、`connect`、`frame` 和遥测。网页不使用广告、分析 SDK、像素、远程头像或未经审核的 UI 库。

Telegram Mini App 在启动时提供 `initData`。Telegram 官方明确警告，客户端字段不能被直接信任；服务端必须按 Bot token 验证 `initData`，并检查 `auth_date` 的新鲜度。[1] 因此验证只能发生在最小化会话服务中，不能在 JavaScript 前端做“自行验证”。验证成功后服务端才发放短期、绑定 Telegram 用户 ID 与 catalog revision 的会话 cookie/令牌。

Mini App 不是 Token 的终点：即使网页、浏览器缓存或 Telegram 用户会话被攻破，Mac 仍然在本地执行最后的 account allowlist、action token、nonce、过期、重放、工具健康和授权窗口验证。所有网页请求都应被视为不可信输入。

## 6. 允许的 Mini App 动作与固定回复

页面只允许：刷新图标目录、点击一个图标请求启动、撤销自己的短期会话、查看固定隐私说明。禁止自由文本框、搜索词上传、参数编辑、变量输入、文件上传、粘贴命令、URL 打开器、Markdown/HTML 远程内容、工具编辑和任何安装/设置入口。

Bot 和 Mini App 的回复只显示固定状态：`Mac 不在线`、`等待 Mac 确认`、`请求被策略拒绝`、`工具不可用`、`已交给所选终端`、`已复制，需在 Mac 处理`。不得回显命令、stdout/stderr、退出码、路径、版本、错误细节或用户目录。

## 7. 分阶段试点

| 阶段 | 范围 | 验收条件 |
|---|---|---|
| **M0：本地策略层** | 复用 Telegram Companion T0：opaque action、账户允许列表、nonce、过期、重放、工具级授权 | 无网络测试即可拒绝文本、参数、变量工具、安装计划、未知账号、过期和重放 |
| **M1：静态图标原型** | 固定 HTTPS 页面，只展示非敏感示例图标，不接 Bot/不连 Mac | 页面无第三方脚本/analytics；CSP、子资源完整性和主题适配审查通过 |
| **M2：已验证目录会话** | 服务端验证 `initData`，向允许用户发短期目录快照 | 不可信 `initData`、过期 `auth_date`、跨用户 token、缓存重放均拒绝 |
| **M3：Mac 长轮询意图交接** | Bot 仅传不透明启动请求；Mac 二次确认 | 无 Webhook/无入站端口；Mac 不在线时不排队执行；不回传敏感数据 |
| **M4：短期远程启动窗口** | 对逐项授权的无变量工具生效 | 每项授权、时限、账号撤销、网络重连与工具健康失败均安全拒绝 |

## 8. 重要取舍

Mini App 解决的是**图标化交互问题**，不是远程执行授权问题。它可让 Telegram 内的体验接近一个紧凑版 TermiPad，但不能完整复制 macOS 原生 UI，也不应复制所有功能。若未来产品目标是完整图标库、离线浏览、通知、Face ID、本地配对及更低的第三方依赖，原生 iPhone Companion 仍是长期正确方向。

对于个人预览，建议先做 M0，然后 M1；只有你明确愿意维护 HTTPS 域名和最小化会话服务时，再进入 M2。Mini App 不应因为界面好看而绕开“没有 Apple 账号前不做真正 iOS App”的外部条件，也不应因为 Telegram 易用而降低 TermiPad 对命令和终端执行的本地控制权。

## References

[1]: https://core.telegram.org/bots/webapps "Telegram Mini Apps"
[2]: https://core.telegram.org/bots/api "Telegram Bot API"
[3]: https://core.telegram.org/bots/features "Telegram Bot Features"
