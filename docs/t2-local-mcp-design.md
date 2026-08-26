# T2：本机受限 MCP 协作设计

**状态：** 已实现，待真实 macOS 集中验证。

## 产品承诺

T2 让同一台 Mac 上、由用户明确启用的 MCP 客户端查询 TermiPad 固定任务、提出一次性本地任务、查询最小状态或取消尚未开始的任务。它不是通用终端服务，也不允许智能体直接批准或执行任务。

```text
MCP 客户端
  └─ 启动 TermiPad --termipad-mcp-stdio
       └─ JSON-RPC stdio + schema 校验
            └─ 命名 CFMessagePort（仅本机进程间通信）
                 └─ 已运行的 TermiPad 主应用
                      └─ T0/T1 项目范围、审阅、执行和取消策略
```

stdio 子进程不打开 SwiftData store。主应用是唯一读取/修改本地工具、范围、审阅窗口与任务状态的进程，因此不会与 UI 竞争同一份 store。

## 启用与身份边界

本机 MCP 默认关闭。用户必须在“本地任务工作台”主动打开“允许本机 MCP 提出任务”。该开关只许可同一登录用户本机的 stdio 客户端请求受限操作；端口名称、MCP `clientInfo` 和工具调用文本都不是身份凭据，也不能替代本机审阅、项目范围或授权窗口。

## 公开工具

| 工具 | 输入 | 最小返回 | 明确不能做 |
|---|---|---|---|
| `list_task_scopes` | 无 | 不透明范围 ID、显示名、可用状态 | 不返回本地路径。 |
| `list_fixed_tasks` | 无 | 固定任务种类、风险级别、用途 | 不返回命令、参数、执行文件或工作目录。 |
| `propose_task` | `scope_id`、`task_kind` | 待审阅任务 ID、状态、过期时间 | 不批准、不执行、不带命令或变量。 |
| `get_task_status` | `task_id` | 任务/执行最小状态和可选退出码 | 不返回 stdout、stderr、文件或项目内容。 |
| `cancel_task` | `task_id` | 取消后的最小状态 | 不终止已运行进程；运行中任务须在本机工作台停止。 |

每个 JSON schema 设置 `additionalProperties: false`。协议层拒绝额外参数，桥接层再次验证任务种类和范围。任务仍需通过 T0 本地审阅窗口，并由 T1 固定定义执行。

## 当前禁止项

T2 不实现 HTTP、Streamable HTTP、WebSocket、网络监听、手机、PWA、Telegram、任意 Shell、PTY、AppleScript、文件浏览、资源读取、prompt/sampling、命令/路径/变量传入，或完整终端输出的保留与回传。

## 验收重点

真实 macOS 集中验证必须同时覆盖 SwiftPM、Xcode build、单元测试与 UI 冒烟测试。静态防护必须证明：stdio 层无 SwiftData 访问；本机桥接使用 `CFMessagePort`；无网络、XPC、进程、终端交接、PTY 或输出管道；工具 schema 严格且 stdout 仅写 JSON-RPC。
