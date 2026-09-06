# TermiPad 路线图完成度审计

**审计范围：** 私有 macOS Swift/SwiftUI 应用的功能、可靠性、恢复与本地效率能力。本文不将“代码可运行”混同于“可外部分发”。

## 当前结论

TermiPad 的原始 P0 目标及不依赖开发者账户的 P1 能力已进入实现收口阶段。核心工作流保持为：**扫描用户主动安装的交互式 CLI → 在候选收件箱确认 → 以本地命令与变量表单启动或复制 → 本机管理与恢复**。网络补充、更新检查和诊断包均为用户主动选择的附加能力，不改变该本地优先边界。

| 路线图模块 | 当前状态 | 已实现或明确闸门 |
|---|---|---|
| P0：收录可信 | 已完成 | 首启边界说明、候选收件箱、手动添加、隐藏/删除/恢复、扫描过滤与安装来源。 |
| P0：启动可信 | 已完成 | 变量表单、模板转义、Terminal/iTerm/Warp/仅复制、自动化拒绝时复制回退、用户明确选择的本地工作目录安全包装与目录失效编辑修复，以及绝对可执行路径失效时的本地健康检查。工作目录不会进入备份或诊断包。 |
| P0：信息可信 | 已完成 | 保守 GitHub 匹配、来源/分数可见、AI Keychain 与命令不可改写、本地图标策略。 |
| P0：恢复与验证 | 已完成 | JSON 备份/预览/合并、旧 schema 兼容、SwiftData 固定 store 重开、集中 macOS 验证。 |
| P1：常用动作 | 已完成 | 收藏、最近使用、菜单栏入口与应用内键盘快捷操作。 |
| P1：诊断 | 已完成 | 本地环形事件记录、隐私化 JSON 诊断包、用户主动导出和清除。 |
| P1：更新提示 | 已完成 | 默认关闭、用户手动 HTTPS JSON 读取、只提示不下载/安装/执行。 |
| P1：iCloud 同步 | 外部闸门，设计已完成 | 默认 `cloudKitDatabase: .none`，并已记录账户、CloudKit 容器、冲突、迁移与双设备验收条件；见 `docs/icloud-sync-design-gate.md`。没有账户/容器配置时不伪实现。 |
| P2-A：项目发现预览 | 已完成并通过真实 macOS 验证 | 默认关闭；仅由用户手动刷新固定公开 GitHub CLI 查询；ETag 缓存、限流退避、非 fork/非 archived 筛选、可解释排序与本地缓存均已实现。不会安装软件、生成命令、自动收录项目或上传本地工具数据。 |
| P2-B：受控安装审查 | 已实现并在真实 macOS 验证 | 仅内置静态审核的 Homebrew core formula 目录（13 个 formula，Sources/ControlledInstallPlan.swift:71-85）；精确仓库映射；显示预期 CLI、审核修订、日期与固定命令；用户明确勾选和手动确认后才可交给所选终端或复制。不会应用内安装、读取 README 命令、支持 tap/cask 或自动收录。 |
| P2-C：只读环境报告 | 已实现并在真实 macOS 验证 | 仅在用户点击检查时对 6 个固定绝对路径组件（Homebrew / Cargo / npm / pnpm / Bun / Python）运行 `--version`；不枚举 PATH、不运行 shell、不联网、不安装/升级/卸载/裁决冲突。Sources/EnvironmentReport.swift:80-153。 |
| 正式外部分发 | 外部闸门 | 需要 Apple Developer 账户、Developer ID、Hardened Runtime、公证、stapling 和 Gatekeeper 隔离冷启动。 |

## 私有 beta 的验证要求

每一批增强合入后，唯一需要在真实 Mac 上执行的验证仍是：

```bash
cd ~/TermiPad && git pull --ff-only origin master && ./scripts/verify-macos.sh
```

该流程验证 SwiftPM 单元测试、XcodeGen、原生 macOS build、UI Runner 签名校验、UI 冒烟测试和结果包导出。它不执行、不模拟正式签名、公证或更新下载安装。

## 未完成项的处理原则

iCloud 同步和正式外部分发受外部资质阻塞；它们不能被本地代码替代。P2-A 的发现预览已按独立安全设计实现并通过真实 macOS 集中验证。P2-B 的安装协助和 P2-C 的依赖治理不是简单的“剩余功能”：它们仍须在单独确认下载来源信任、安装授权、可回滚策略、包管理器支持范围和隐私说明后才可启动。
