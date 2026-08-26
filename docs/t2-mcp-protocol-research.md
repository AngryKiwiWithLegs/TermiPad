# T2：本机受限 MCP 协作协议依据

**状态：** 研究完成，尚未实现服务端或配置任何 MCP 连接器。

## 当前会话与产品边界

当前 Manus 会话没有可用的自定义 MCP 连接器；检查结果为零个用户自定义连接器。T2 不创建、启用或修改连接器，也不让当前会话直接访问用户 Mac。TermiPad 的第一版 MCP 只设计为用户在**同一台 Mac**上主动配置的 `stdio` 服务端。

## 官方协议结论

| 协议事实 | T2 设计含义 |
|---|---|
| MCP 初始化必须先于正常操作，并由客户端发送 `initialize`，成功后发送 `notifications/initialized`。 | 服务端在初始化完成前拒绝工具调用；仅协商 `tools` 能力。 |
| `stdio` 关闭由客户端关闭子进程输入并等待进程退出；所有请求都应有超时。 | T2 使用按行 JSON-RPC stdio，客户端断开时退出；不维持后台或网络会话。 |
| 工具需声明 JSON Schema；服务端必须验证输入、实施访问控制、限速并净化输出。 | 所有工具 `additionalProperties: false`；仅接受 UUID/固定枚举；结果只返回状态与固定说明。 |
| MCP 强烈建议敏感调用保持人类可拒绝。 | `propose_task` 只能创建 T0 审阅状态，永不自动批准或执行；`cancel_task` 只取消本机任务。 |
| 官方 Swift SDK 当前为 Tier 3。 | 第一版优先实现一个小型、可测试的协议子集，不将未验证 SDK 行为放入 TermiPad 主执行链。 |

## 本机桥接结论

`stdio` MCP 服务端作为 MCP 客户端的子进程，不能可靠地与正在运行的 SwiftUI 应用直接竞争同一份 SwiftData store。T2 的桥接优先采用应用进程持有的命名 `CFMessagePort`：stdio 进程只处理 JSON-RPC 与严格 schema，再通过本机端口向已运行的应用请求受限操作。Apple 将 `CFMessagePort` 定义为可在同一台机器的线程或进程间传输任意数据的通信通道；它不是 HTTP、WebSocket 或公网监听。[5]

本机端口名不是认证凭据。TermiPad 仍默认关闭 MCP，并在 app 内显式开启；MCP 客户端提交的 `clientInfo` 只用于兼容性信息，绝不作为身份或授权证明。第一版仅面向同一登录用户的本机使用；跨用户、sandbox 场景、远程连接与高权限 helper 都不属于 T2。

| 进程 | 责任 | 禁止事项 |
|---|---|---|
| MCP stdio 可执行文件 | JSON-RPC 生命周期、schema 校验、最小化协议结果 | 不开数据库、不执行任务、不接网络、不打印非协议 stdout。 |
| 应用内 `CFMessagePort` | 对本地模型和 T0/T1 策略的单一受限桥接 | 不暴露给网络、不接受命令/路径/变量、不回传完整输出。 |
| TermiPad 主应用 | 用户可见的本机许可、任务审阅和策略管理 | 不把 MCP 客户端信息视为认证凭据。 |

## T2 明确不实现

- 不提供 `execute(command, cwd, env)`、终端、PTY、文件浏览、资源读取、prompt、sampling 或完整输出工具。
- 不提供 HTTP、Streamable HTTP、WebSocket、监听端口、外部网络、token 或手机桥接。
- 不把 stdio 日志写入 stdout；stdout 只能输出 JSON-RPC 协议消息。

## 参考资料

[1]: https://modelcontextprotocol.io/specification/2025-03-26/basic/lifecycle "Model Context Protocol：Lifecycle"
[2]: https://modelcontextprotocol.io/specification/2026-07-28/server/tools "Model Context Protocol：Tools"
[3]: https://modelcontextprotocol.io/docs/2026-07-28/develop/build-server "Model Context Protocol：Build an MCP server"
[4]: https://modelcontextprotocol.io/docs/2026-07-28/sdk "Model Context Protocol：SDKs"
[5]: https://developer.apple.com/documentation/corefoundation/cfmessageport "Apple：CFMessagePort"
