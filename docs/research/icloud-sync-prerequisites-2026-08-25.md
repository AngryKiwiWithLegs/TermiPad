# iCloud 同步前置条件研究记录

**日期：** 2026-08-25  
**用途：** TermiPad P1 iCloud 同步的设计闸门，不是实现说明。

Apple 的 SwiftData 文档明确指出，自动 iCloud 同步需要 iCloud 与 Background Modes 两项 capability；其中 iCloud capability 需要具有管理员权限的有效 Apple Developer 账户。[1] 应用还需要启用 CloudKit、选择或创建 CloudKit 容器，并开启 Remote notifications 以接收服务器变更。[1]

SwiftData 会根据 entitlements 推断 CloudKit 容器，且模型必须符合 CloudKit 的 schema 限制。官方特别提示：CloudKit 无法强制唯一约束，不支持非可选 relationship；生产 schema 提升后只能做加法，不能删除模型类型或更改既有属性。[1]

TermiPad 当前容器工厂对固定 store 测试显式使用 `cloudKitDatabase: .none`，这对本地优先的开发和恢复测试是正确的。没有 Apple Developer 账户、团队、容器 ID、entitlements 与真机 CloudKit 环境时，不能将其改为“看似同步”的实现，也不能声称 P1 iCloud 已完成。

进入 iCloud 实现前，必须先完成以下决策：

| 决策 | TermiPad 需要确定的内容 |
|---|---|
| 账户与容器 | Apple Developer 团队、bundle identifier、私有 CloudKit container 与开发/生产环境。 |
| 同步对象 | 工具记录、候选、收藏和分类是否同步；API Key、变量值、受控本地图标、工作目录与诊断必须默认留在本地。 |
| 冲突策略 | 工具命令的跨设备冲突如何处理；不得静默覆盖用户本机命令。 |
| 迁移 | 既有本地 SwiftData store 向同步 store 的迁移、备份、回滚和用户选择。 |
| 验收 | 至少两台使用同一 Apple ID 的测试设备、离线变更、冲突、删除、恢复与安全回退。 |

## References

[1]: https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices "Apple: Syncing model data across a person’s devices"
[2]: https://developer.apple.com/documentation/coredata/setting-up-core-data-with-cloudkit "Apple: Setting Up Core Data with CloudKit"
