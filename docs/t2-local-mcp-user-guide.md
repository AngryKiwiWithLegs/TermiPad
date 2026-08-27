# TermiPad T2 本机受限 MCP 使用指南

**适用版本：** TermiPad Mendocino T2；真实 macOS 集中验证归档 `20260826-212137`；文档状态：已验证的本机配置说明。

> **用途边界。** T2 使同一台 Mac 上的 MCP 客户端能够向正在运行的 TermiPad 查询固定任务与项目范围、提出一项待本机审阅的固定任务、读取最小状态，或取消尚未开始的任务。它不是终端替代品，也不是远程控制服务：没有网络地址、HTTP、WebSocket、任意 Shell、文件浏览、路径/参数/环境变量传入、PTY 或完整终端输出。

## 1. 开始前：确认这是不是适合的使用方式

T2 适用于已经在**同一台 Mac、同一登录用户**下运行的本机 MCP 客户端。该客户端会启动 TermiPad 的一个受限 `stdio` 子进程；子进程只处理 JSON-RPC 与严格输入校验，实际的本地数据与策略操作仍由已打开的 TermiPad 主应用通过本机进程间桥接处理。

| 必要条件 | 说明 | 不满足时的行为 |
|---|---|---|
| 正常启动的 TermiPad 主应用 | 主应用负责安装本机桥接并持有本地任务数据。 | MCP 返回 `local_bridge_unavailable`。 |
| 用户已在 Mac 上开启本机 MCP | 在“本地任务工作台”打开“允许本机 MCP 提出任务”。默认关闭。 | MCP 返回 `local_mcp_disabled`。 |
| 已选择至少一个项目范围 | 每项提案都必须指向已存在、未撤销且可用的本机项目范围。 | 提案返回 `project_scope_unknown` 或 `project_scope_unavailable`。 |
| 支持 `stdio` 的本机 MCP 客户端 | 客户端必须能用绝对路径启动子进程并传递固定参数。 | 不能连接；不要改为 HTTP 或公网端口。 |

本指南不需要也不应创建 Manus 自定义 MCP 连接器、填写 token、配置 URL 或添加环境变量。这里的 MCP 是一个本机子进程协议，而不是云端连接器或移动设备服务。

## 2. 先启动并准备 TermiPad

先以**正常 App 模式**打开 TermiPad，而不是带 `--termipad-mcp-stdio` 参数启动它。若你正在从仓库构建调试版本，可使用下列固定的独立构建目录；这一步只生成并打开本机 App，不会启动网络服务，也不会授予 MCP 执行权限。

```bash
cd ~/TermiPad
xcodegen generate
xcodebuild \
  -project TermiPad.xcodeproj \
  -scheme TermiPad \
  -destination 'platform=macOS' \
  -derivedDataPath "$PWD/.mcp-derived-data" \
  build
open "$PWD/.mcp-derived-data/Build/Products/Debug/TermiPad.app"
```

随后在 TermiPad 的**本地任务工作台**中完成以下本机操作。项目文件夹路径只保留在这台 Mac 上；MCP 客户端只能得到不透明的范围 ID、显示名和可用性状态，不能得到路径。

1. 在“项目范围”选择一个项目文件夹；如已有范围，确认它显示为可用且未撤销。
2. 在“允许本机 MCP 提出任务”打开开关。该开关只允许受限操作，并不将客户端、端口名或 `clientInfo` 视为身份凭据。
3. 保持 TermiPad 主窗口或应用进程运行。关闭 App 后，MCP 子进程没有可访问的本机桥接，不能自行打开或竞争 SwiftData 数据库。

如果未来使用经签名分发的 App，请把下文配置中的 `command` 改为该 App 实际的绝对可执行文件路径（通常是 `TermiPad.app/Contents/MacOS/TermiPad`）。不要配置仓库目录、Shell 包装脚本、`PATH` 搜索或动态参数。

## 3. 在本机 MCP 客户端中登记服务

不同 MCP 客户端的配置文件位置与顶层字段可能不同；请使用该客户端官方文档确定文件位置。无论宿主如何命名服务器项，TermiPad 的关键值固定为：**绝对可执行文件路径**加上唯一参数 `--termipad-mcp-stdio`。

下面是常见 MCP 客户端配置结构的**模板**。将 `/Users/你的账户名` 替换为这台 Mac 的真实绝对路径；不要加入 `env`、`url`、`headers`、token、Shell 字符串或额外参数。

```json
{
  "mcpServers": {
    "termipad-local": {
      "command": "/Users/你的账户名/TermiPad/.mcp-derived-data/Build/Products/Debug/TermiPad.app/Contents/MacOS/TermiPad",
      "args": ["--termipad-mcp-stdio"]
    }
  }
}
```

配置保存后，由 MCP 客户端启动该子进程。按照 MCP `stdio` 规则，客户端向子进程标准输入逐行写入 UTF-8 JSON-RPC，服务端只在标准输出逐行写入有效 MCP 消息；因此任何会向 stdout 额外打印调试文字的包装器都会破坏协议。[1] TermiPad 不要求、也不接受网络 URL 或密钥。

> **不要把 `--termipad-mcp-stdio` 用在正常打开 App 的快捷方式中。** 该参数会使可执行文件进入无界面 stdio 服务模式；它需要由 MCP 客户端作为子进程启动。主应用必须单独保持运行，以便提供受限本机桥接。

## 4. 连接后的最小验证顺序

标准 MCP 生命周期要求客户端先发送 `initialize`、收到响应后再发送 `notifications/initialized`，随后才进入常规工具调用。[2] 大多数成熟 MCP 客户端会自动完成这一过程；如果客户端在工具列表尚未出现时显示初始化错误，应先检查它是否请求并支持本服务精确接受的 `2025-03-26` 或 `2025-11-25` 协议版本。

建议按以下顺序验证，避免一开始就创建任务。

| 顺序 | 在 MCP 客户端中进行的动作 | 预期最小结果 | 不会发生的事 |
|---|---|---|---|
| 1 | 重新加载或连接 `termipad-local`。 | 客户端发现工具能力。 | 不会打开网络连接或读取项目文件。 |
| 2 | 调用 `list_task_scopes`。 | 不透明 `scope_id`、显示名、`available` / `unavailable` / `revoked` 状态。 | 不会返回项目路径。 |
| 3 | 调用 `list_fixed_tasks`。 | 固定任务种类、风险等级和用途。 | 不会返回命令、参数、执行文件或工作目录。 |
| 4 | 仅在确有需要时调用 `propose_task`。 | 新的 `task_id`，其状态为待本机审阅，并可能含到期时间。 | 不会批准或执行任务。 |
| 5 | 回到 Mac 上的 TermiPad 工作台审阅。 | 用户可看到提案、打开本地审阅窗口并按本地策略批准或取消。 | MCP 客户端不能替代这一步。 |
| 6 | 只在需要进度确认时调用 `get_task_status`。 | 最小状态、执行状态、可选退出码或拒绝原因。 | 不会返回 stdout、stderr、文件内容或项目内容。 |

TermiPad 在收到 `notifications/initialized` 前拒绝普通工具操作；它还对每个 MCP 服务进程限制为每 60 秒最多 30 个普通请求。速率限制是保护机制，不应通过重试循环、并发子进程或多个包装器规避。

## 5. 五个可用工具

所有工具都使用严格 JSON Schema，`additionalProperties` 为 `false`。换言之，未列出的字段即使看起来无害也会在到达本机桥接前被拒绝。UUID 必须使用标准字符串形式。

| 工具 | 必需输入 | 返回内容 | 关键限制 |
|---|---|---|---|
| `list_task_scopes` | 无 | `scope_id`、`display_name`、`status`。 | 不返回路径或文件信息。 |
| `list_fixed_tasks` | 无 | `task_kind`、`risk`、`purpose`。 | 不返回命令、参数、可执行文件或目录。 |
| `propose_task` | `scope_id`、`task_kind`。 | 待审阅 `task_id`、风险、状态、执行状态、可选到期时间。 | 只能提出固定任务；不能夹带 `command`、`cwd`、`env` 或 URL，也不能批准或执行。 |
| `get_task_status` | `task_id`。 | 最小任务与执行状态、可选退出码、拒绝原因、到期时间。 | 不返回终端输出或文件内容。 |
| `cancel_task` | `task_id`。 | 取消后的最小任务状态。 | 不能终止正在运行的任务；必须回到 Mac 本地工作台停止。 |

`propose_task` 的正确输入形状只有下例中的两个字段：

```json
{
  "scope_id": "11111111-2222-3333-4444-555555555555",
  "task_kind": "swiftPackageTests"
}
```

上例中的 ID 只是格式示例，不能复用。实际值必须先由 `list_task_scopes` 和 `list_fixed_tasks` 返回。请勿添加诸如 `command`、`path`、`arguments`、`environment`、`url` 或自然语言指令等字段。

## 6. 审阅、执行、取消与撤销

MCP 创建的任务只能处于待审阅状态。真正的批准与启动只在 Mac 的 TermiPad 工作台中由用户完成：先为相应范围打开 15 分钟本地审阅窗口，再按本地策略批准，最后由用户选择是否开始固定任务。T1 即使启动任务，也只使用固定可执行文件、固定参数、已选项目范围和空的 stdin/stdout/stderr；不会把完整终端输出保存或回传。

| 你的目标 | 正确做法 | 不应尝试的做法 |
|---|---|---|
| 暂停新的 MCP 操作 | 在本地任务工作台关闭“允许本机 MCP 提出任务”。 | 不要试图用客户端 `clientInfo`、端口名或配置 token 充当撤销机制。 |
| 停止 MCP 子进程 | 在 MCP 客户端中断开或移除该服务器配置。客户端应关闭子进程 stdin 并等待其退出；必要时依次终止进程。[2] | 不要让后台 Shell 包装器保持服务常驻。 |
| 撤销某项目的任务权限 | 在 TermiPad 的本地任务工作台对该项目范围选择“撤销范围”。 | 不要向 MCP 请求传递替代路径或新目录。 |
| 取消尚未运行的提案 | 使用 `cancel_task(task_id)` 或本地工作台的取消按钮。 | 不要删除或篡改本地数据库文件。 |
| 停止正在运行的 T1 任务 | 回到同一台 Mac 的任务卡，点击“停止”。 | 不要反复调用 `cancel_task`；它会返回 `task_running_local_stop_required`。 |

关闭 MCP 开关会使后续桥接请求被拒绝；关闭主应用会让桥接不可用。两者都不等同于强制终止一个已经在 T1 本地运行的进程，因此运行中任务仍必须用工作台的“停止”按钮处理。

## 7. 常见错误与安全排查

| 现象或错误代码 | 可能原因 | 安全的处理方式 |
|---|---|---|
| `local_bridge_unavailable` | TermiPad 未正常运行、主应用处于恢复模式，或客户端不在同一台 Mac/登录上下文。 | 正常打开 TermiPad，确认主数据容器可用，再重新连接。不要改用 HTTP、localhost 端口或共享网络目录。 |
| `local_mcp_disabled` | 本地工作台开关仍关闭。 | 仅在你本人需要本机协作时手动打开；使用结束后关闭。 |
| `invalid_arguments` | 有额外字段、UUID 无效，或 `task_kind` 不属于固定目录。 | 删除全部未列字段；重新从列出工具获得 ID 与枚举值。 |
| `project_scope_unknown` | `scope_id` 不存在。 | 重新调用 `list_task_scopes`，不要猜测 ID 或提交本地路径。 |
| `project_scope_unavailable` | 范围已撤销或其目录暂不可用。 | 在 Mac 工作台检查范围状态；如需恢复，由用户重新选择项目文件夹。 |
| `task_unknown` | `task_id` 不存在或不再可用。 | 只使用本次提案返回的 ID；不要扫描本地文件寻找任务信息。 |
| `task_running_local_stop_required` | 任务已在本机执行。 | 回到 TermiPad 工作台停止；MCP 不具备远程进程终止能力。 |
| `rate_limited` | 单个服务进程在一分钟内超过 30 个普通请求。 | 等待后再进行必要的单次调用，并修正客户端轮询策略。 |
| `Unsupported protocol version` 或初始化前操作被拒绝 | 客户端未请求或不支持 TermiPad 精确接受的 `2025-03-26`、`2025-11-25`，或未按生命周期发送初始化通知。 | 更新/改用支持已接受版本的 stdio MCP 本机客户端；不要手工放宽 TermiPad 协议校验或添加兼容网络代理。 |

如果客户端界面要求填写服务器 URL、API Key、OAuth、浏览器授权或远程端点，说明它所选的连接类型不是本指南的 `stdio` 子进程模式。不要为迁就该界面而把 TermiPad 暴露为 HTTP 服务；请选择支持命令型 `stdio` MCP 配置的本机客户端。

## 8. 已验证范围与未验证范围

T2 已在用户真实 Apple Silicon Mac、Xcode 26.6、Swift 6.3.3 与 XcodeGen 2.46.0 环境下通过集中验证。验证覆盖协议与严格 schema 单元测试、Swift 源码安全防护、原生 macOS 构建与 UI 冒烟测试；结果目录为 `20260826-212137`。这证明当前仓库中的本机 T2 范围已通过该环境的回归验证，不代表任何特定第三方 MCP 主机已经被实际接入或认证。

| 已验证 | 尚未实施或尚未验证 |
|---|---|
| 同机 `stdio` JSON-RPC、固定协议版本、初始化顺序与五个受限工具。 | 任何特定第三方 MCP 客户端的品牌专属配置文件或 UI 流程。 |
| 应用内默认关闭开关、CFMessagePort 本机桥接、T0 本地审阅和 T1 最小执行结果。 | iPhone 伴侣、PWA、Telegram、异地网络会话、HTTP MCP 或公共端口。 |
| 禁止网络、XPC、任意进程启动、Shell、PTY、终端交接、文件浏览和完整输出。 | Developer ID、公证、Gatekeeper 冷启动、iCloud/CloudKit 与外部分发。 |

在下一步实际连接某个 MCP 客户端前，应先确认该客户端支持“command + args”的本机 stdio 配置，并在不调用 `propose_task` 的情况下完成 `tools/list`、`list_task_scopes` 与 `list_fixed_tasks` 的只读演练。只有这些步骤符合预期后，才考虑提出一项低风险、可由用户在 Mac 本地审阅的固定任务。

## 9. OpenCode：已兼容的本机客户端接入方式

**结论：OpenCode 可以作为 T2 的 MCP 客户端。** OpenCode 官方支持本地 MCP 服务；它要求在 `mcp` 对象中使用 `type: "local"`，并将可执行文件与固定参数写成一个 `command` 数组。[4] OpenCode 1.14.33 已实际证实使用 `2025-11-25` 发起初始化；TermiPad 仅精确接受该版本与原有 `2025-03-26`，并在成功握手中回显接受的客户端版本，符合 MCP 的版本协商规则。[6] 这与 TermiPad 的唯一入口“绝对可执行文件路径 + `--termipad-mcp-stdio`”严格匹配，不需要 URL、远程服务器、OAuth、header、token 或环境变量。

OpenCode 同时拥有自己的 `bash`、读写文件和网络工具。**TermiPad 的受限 MCP 边界不会自动限制这些 OpenCode 内置工具。** OpenCode 默认允许大部分工具，因此本节的权限配置把 OpenCode 的 Shell 与文件修改能力显式拒绝，并让其余操作默认要求确认。[5] 不要使用 OpenCode 的 `--auto` 模式；该模式会自动批准未被明确拒绝的操作。[5]

### 9.1 最小配置文件

建议把这项个人本机配置放在 `~/.config/opencode/opencode.jsonc`，而不是提交到任何项目的 Git 仓库。OpenCode 会合并全局与项目配置；编辑时只添加或合并下方的 `mcp` 与 `permission` 字段，不能覆盖你已有的 provider 或个人设置。[4]

初始状态将 `enabled` 保持为 `false`。只有在 TermiPad 已正常运行、范围已准备好且你本人准备做只读演练时，才把它临时改为 `true`；演练结束后改回 `false`。

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "termipad-local": {
      "type": "local",
      "command": [
        "/Users/你的账户名/TermiPad/.mcp-derived-data/Build/Products/Debug/TermiPad.app/Contents/MacOS/TermiPad",
        "--termipad-mcp-stdio"
      ],
      "enabled": false,
      "timeout": 6000
    }
  },
  "permission": {
    "*": "ask",
    "bash": "deny",
    "edit": "deny",
    "webfetch": "deny",
    "websearch": "deny",
    "task": "deny"
  }
}
```

将示例中的 `/Users/你的账户名` 替换为 Mac 的真实账户目录，并确认该路径指向你在第 2 节构建得到的 `TermiPad.app/Contents/MacOS/TermiPad`。**每次拉取涉及 MCP 的新提交后，都必须重新运行第 2 节的定向构建命令，覆盖 `.mcp-derived-data` 中的二进制文件；`./scripts/verify-macos.sh` 的验证产物不会替代该固定路径。** `command` 必须保持为数组：不要改成 `zsh -c`、`bash -c`、字符串拼接或包装脚本；也不要添加 `cwd`、`environment`、`url`、`headers`、OAuth 字段或任何秘密值。`timeout: 6000` 只是为 OpenCode 的工具发现预留略高于 TermiPad 本机桥接请求上限的时间，不会扩大 TermiPad 能力。

### 9.2 只读优先演练

先正常打开 TermiPad，在“本地任务工作台”确认已有可用项目范围，并打开“允许本机 MCP 提出任务”。然后把上面 `enabled` 临时改为 `true`，重新启动 OpenCode，并运行：

```bash
opencode mcp list
```

该命令用于显示已配置 MCP 服务及其连接状态。[4] 如果 `termipad-local` 可用，再在 OpenCode 的普通对话中输入以下**只读提示**：

```text
仅使用 termipad-local MCP 工具，依次调用 list_task_scopes 和 list_fixed_tasks。
不要调用 propose_task、get_task_status 或 cancel_task；不要使用 bash、编辑、文件、网络、子代理或其他工具。
只概述返回的显示名、状态、固定任务用途和风险等级；不要猜测路径、命令或参数。
```

预期结果仅包含不透明范围 ID、范围显示名和状态，以及固定任务种类、用途与风险等级。它不应显示项目路径、命令正文、参数、环境变量、终端输出或文件内容。确认这一轮只读结果符合预期后，应将 `enabled` 改回 `false`，并在 TermiPad 工作台关闭“允许本机 MCP 提出任务”。

### 9.3 不要这样配置或使用

| 不安全或不兼容做法 | 原因 | 正确替代 |
|---|---|---|
| 将服务写成 `type: "remote"` 或填写 URL。 | T2 没有 HTTP/Streamable HTTP 服务，也不会认证远程客户端。 | 使用 `type: "local"` 与本机绝对路径。 |
| 为 TermiPad 填写 token、OAuth、headers 或 `environment`。 | T2 不需要、也不会读取这些值；额外秘密会扩大不必要的暴露面。 | 配置中不写任何秘密或环境变量。 |
| 用 `zsh -c`、`bash -c`、`npx` 或包装脚本启动服务。 | 会引入额外 Shell 解析、PATH 依赖或 stdout 污染风险。 | `command` 数组只含 TermiPad 可执行文件绝对路径与唯一固定参数。 |
| 在 OpenCode 使用 `--auto`，或维持默认宽松权限。 | OpenCode 的其他内置工具可能独立执行 Shell、编辑或网络动作；这不受 TermiPad MCP 限制。 | 使用本节 `permission` 配置，保持确认模式。 |
| 第一次演练就请求 `propose_task`。 | 容易跳过对连接、范围和最小返回的观察。 | 先只读列出范围和固定任务；以后另行确认低风险提案。 |

OpenCode 的 `opencode serve`、`opencode web`、`--hostname`、`--mdns` 与远程 attach 是 OpenCode 的独立功能，不是启用 TermiPad T2 所必需的步骤。它们不应出现在此演练中，也不应被当作将 TermiPad 暴露到局域网或公网的手段。

## 参考资料

[1]: https://modelcontextprotocol.io/specification/2025-03-26/basic/transports "Model Context Protocol：Transports（stdio）"
[2]: https://modelcontextprotocol.io/specification/2025-03-26/basic/lifecycle "Model Context Protocol：Lifecycle"
[3]: https://developer.apple.com/documentation/corefoundation/cfmessageport "Apple：CFMessagePort"
[4]: https://opencode.ai/docs/mcp-servers/ "OpenCode：MCP servers"
[5]: https://opencode.ai/docs/permissions/ "OpenCode：Permissions"
[6]: https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle "Model Context Protocol：Lifecycle and version negotiation"
