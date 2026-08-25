# TermiPad iCloud 同步设计闸门

**状态：** 未实现，默认显式禁用。
**适用阶段：** 获得具备管理员权限的 Apple Developer 账户并创建 CloudKit 容器之后。
**目的：** 防止把“打开 iCloud capability”误当成可安全交付的同步功能。

## 1. 当前边界

TermiPad 的默认 SwiftData `ModelConfiguration` 显式指定 `cloudKitDatabase: .none`。即使未来项目出现 iCloud entitlement，也不会因为自动容器发现而意外同步数据。任何 iCloud 实现必须新增独立的、经审计的同步配置，不能修改默认本地优先容器的语义。

> 当前版本的 JSON 备份仍是唯一支持的跨设备迁移方式；它由用户主动导出与导入，并可以预览、合并和恢复。

## 2. Apple 前置条件

Apple 的 SwiftData 自动同步要求 iCloud 与 Background Modes capability、CloudKit 容器和 Remote notifications；iCloud capability 需要具有管理员权限的有效 Apple Developer 账户。[1]

| 前置条件 | 当前状态 | 进入实现前的完成标准 |
|---|---|---|
| Apple Developer 团队 | 未具备 | 获得可管理 capability 的团队权限。 |
| Bundle ID 与签名配置 | 开发用 ad hoc | 建立受团队管理的应用标识和开发签名。 |
| CloudKit 容器 | 未创建 | 创建私有容器，记录 container identifier 与开发/生产环境。 |
| iCloud / Background Modes | 未启用 | 启用 CloudKit 和 Remote notifications，并审计 entitlements。 |
| CloudKit schema | 未初始化 | 在开发环境初始化并审阅，生产提升前完成迁移策略。 |

## 3. 同步范围：默认本地优先

| 数据 | 初始同步策略 | 原因 |
|---|---|---|
| 工具名称、分类、说明、收藏 | 可考虑同步 | 属于跨设备可迁移的低敏感工具元数据。 |
| 用户手动编辑的启动命令 | 需要显式冲突处理 | 命令具备执行影响，不能静默以远端版本覆盖本机版本。 |
| 候选收件箱 | 默认不同步或单独开关 | 发现结果强依赖本机安装环境，跨设备可能无效。 |
| 工作目录 | 不同步 | 路径机器相关，当前也不进入 JSON 备份。 |
| 自定义本地图标 | 不同步 | 仅是受控本地文件，不应通过 CloudKit 传播二进制或路径。 |
| 已保存变量值 | 默认不同步 | 可能包含敏感令牌、私有路径或环境信息。 |
| AI API Key | 永不同步 | 仅存 macOS Keychain。 |
| 诊断记录 | 不同步 | 仅用于当前设备的本地支持信息。 |

## 4. 冲突与迁移要求

CloudKit 对并发变更的处理与 SwiftData 的模型限制意味着，不能依赖“最后写入者静默获胜”来处理命令或用户偏好。进入实现前必须设计至少以下策略：

1. 对本机手动修改的命令、工作目录、变量值、图标和 API Key 保持本地优先，且不把它们加入同步 schema。
2. 对可同步元数据出现冲突时，显示清晰的选择或保留带时间戳的版本，不得静默改变本机启动命令。
3. 在开启同步前，要求用户先导出 JSON 备份；提供关闭同步与继续使用本地 store 的可逆路径。
4. 先在 CloudKit 开发环境演练 schema 初始化、两台设备离线修改、恢复联网、删除、重装和备份恢复；生产 schema 推升后只允许加法变更。[1]

## 5. 不得宣称完成的条件

在以下任一条件缺失时，不得在 UI、README 或发布说明中把 TermiPad 描述为“支持 iCloud 同步”：没有开发者账户、没有 CloudKit 容器、没有真机双设备验证、没有冲突策略、或没有从现有本地 SwiftData store 迁移和回滚演练。

## References

[1]: https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices "Apple: Syncing model data across a person’s devices"
