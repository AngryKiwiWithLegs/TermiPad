# T0：本地受限任务策略核心

**状态：** 已进入实现批次；本阶段不执行任务、不创建进程、不接入网络、MCP、手机、PWA、Telegram 或 PTY。

## 目标

T0 为后续的临时测试任务建立一个本地、可审计的策略核心。它解决的不是“在应用里新建一个 Shell”，而是先回答：一条一次性任务是否属于随应用发布的固定目录、是否绑定到用户本机选择的项目范围、是否在有效本地审阅窗口内、是否被重放、过期、取消或撤销。

## 数据契约

| 类型 | 保存内容 | 不保存或不外传的内容 |
|---|---|---|
| `TaskProjectScope` | 本地显示名、项目根目录、撤销状态、时间 | 不进 JSON 备份、隐私诊断、聊天或网页入口。 |
| `TaskReviewWindow` | 项目范围引用、最大风险、开始/结束/撤销时间 | 不代表远程许可，不打开网络连接。 |
| `TaskIntent` | 项目范围 ID、固定任务类型、风险、nonce、时限、状态与拒绝类别 | 不带自由命令、参数、环境变量、路径、网络地址、输入或输出。 |
| `FixedTaskCatalog` | 随应用发布的固定任务类型、命令预览和用途 | 不从 AI、README、网页、Bot 或 MCP 接收命令。 |

## 本地状态机

```text
创建提案 → pendingReview
       │
       ├─ 本机范围 + 有效审阅窗口 + nonce 未重放 → approved
       ├─ 过期 → expired
       ├─ 取消 → cancelled
       └─ 范围/窗口撤销 → revoked 或 rejected
```

`approved` 在 T0 中不触发任何执行。它只证明未来 T1 的本地任务运行器可以接收到一条已经按策略审阅的任务。T0 绝不把 `approved` 当作永久后台授权。

## 固定目录

初始目录仅包含：`swift test`、`./scripts/verify-macos.sh` 与 `xcodegen generate`。目录条目有完整命令预览和风险级别；智能体、手机、MCP 和远程元数据无法创建或修改条目。

用户若日后想把一次性任务固化为图标工具，必须在 Mac 本机通过一个单独、明确的确认动作完成；T0 不支持自动提升。

## 拒绝规则

| 条件 | 结果 |
|---|---|
| 任务类型不在固定目录 | `unknownTaskKind` |
| 项目范围缺失、目录不可用或已撤销 | `projectScopeUnavailable` |
| 从未开启本地审阅窗口 | `localReviewRequired` |
| 已配置窗口全部过期 | `reviewWindowExpired` |
| 窗口风险等级不足 | `riskNotPermitted` |
| nonce 已用于另一条未拒绝任务 | `nonceReplayed` |
| 提案已过期、已取消或不再等待审阅 | 相应固定拒绝状态 |

## 隐私与诊断

诊断只记录固定事件类别：创建提案、打开审阅窗口、策略批准/拒绝、取消和范围撤销。事件不包含项目名、路径、命令、变量、输出、密钥或网络地址；当前 JSON 备份也不包含任务范围或任务历史。

## 静态防护

集中验证脚本对 T0 源文件禁止 `URLSession`、网络连接、WebSocket、AppleScript、`TerminalLauncher`、`Process`、PTY、`/bin/sh`、URL、`stdin`、`stdout` 和 `stderr`。它还要求固定任务目录存在。后续阶段如要引入执行器、MCP 或移动连接，必须创建独立设计、测试和审阅批次，不能通过移除 T0 防护静默扩大能力。
