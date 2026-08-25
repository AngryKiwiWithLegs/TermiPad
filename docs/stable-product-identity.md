# Shelldex：稳定产品线标识

**生效日期：** 2026-08-25
**适用对象：** 已完成 P0 + P1 本地实现并在真实 Apple Silicon macOS 上通过集中验证的稳定基线。

## 1. 商品名

稳定产品线的商品名定为 **Shelldex**，中文说明为 **“终端工具库”**。

> **Shelldex** 是一款原生 macOS 终端工具库：它将用户主动安装、需要直接交互使用的 CLI 整理为候选收件箱与图标化工具库，并只在用户确认后交给其选择的终端启动。

该名称由 **Shell**（用户已有终端环境）与 **Index**（可审查、可整理的工具索引）构成。它强调产品是一个“看得见、找得到、可确认启动”的工具库，而不是另一个终端、包管理器或自动化代理。

`TermiPad` 继续作为当前私有仓库、Swift 模块和历史技术代号，直至正式重命名迁移另行批准。这样可以避免在已验证基线中临时修改 bundle identifier、SwiftData 容器、测试宿主或本地数据路径。商品名与代码代号分离，不会改变现有用户数据，也不会暗示已完成外部分发。

## 2. 命名选择依据

公开检索发现已存在同名的开源 `TermiPad` CLI 记事本项目，因此不宜将 `TermiPad` 继续作为未来对外商品名称。[1] `Shelldex` 在本次公开软件名称初筛中未出现显著的 macOS 终端工具冲突；这只是产品命名层面的初筛，不构成商标、域名、公司名称或应用商店名称的法律清查。

| 候选 | 评价 | 结论 |
|---|---|---|
| TermiPad | 已用于公开 CLI 记事本，且“Pad”容易联想到 iPad | 不作为未来商品名 |
| Pathloom | 发音柔和，但已用于户外路线规划产品 | 淘汰 |
| Shellorium | 区分度较高，但过于抽象、难以一眼理解 | 备用 |
| **Shelldex** | Shell + Index，贴合“可发现、可审查、可启动的 CLI 工具库”；简短、可读 | **采用** |

## 3. 稳定与 P2 的分层标识

| 层级 | 标识 | 用途 | 安全承诺 |
|---|---|---|---|
| 已验证稳定基线 | **Shelldex 1.0 Stable** | P0 + P1 本地功能、恢复与真实 macOS 验证的固定参照 | 不含远程发现、安装、自动升级或依赖治理 |
| 当前代码基线标签 | `shelldex-stable-1.0.0` | 对应通过真实 macOS 集中验证及审计记录的 Git 固定点 | 可用于回归、差异审计与问题回退定位 |
| P2 发现开发线 | **Shelldex Next — Discovery Preview** | P2-A 的手动发现、缓存、来源证据和可解释排序 | 默认关闭网络；不提供安装动作 |
| 未来安装协助线 | **Shelldex Next — Install Review** | P2-B 的受控安装计划与终端交接 | 必须另行通过来源 allowlist、命令预览和明确确认验收 |

“Stable”只表示内部私有基线的代码与本机验证状态，不表示已通过 Developer ID、Hardened Runtime、公证、Gatekeeper 冷启动或外部分发验收。

## 4. 采用规则

从 P2 起，产品文档、路线图、测试计划和未来 UI 文案使用 **Shelldex** 作为商品名；技术源码路径、已有 bundle identifier、Swift 模块和本地数据容器暂保留 `TermiPad`。任何面向外部用户的发行前重命名必须作为单独迁移：同时评估显示名、bundle identifier、SwiftData 容器、备份兼容、Keychain service、自动化权限和公证身份，不能以字符串替换方式处理。

当前稳定基线固定后，P2 新功能必须以“Preview”身份描述，且不得回写、自动升级或改变 Shelldex 1.0 Stable 的已验证行为。若 P2 的实验导致回归，开发应回退到稳定标签，而不应以不透明的临时提交作为参照。

## References

[1]: https://github.com/Jcharis/TermiPad "Jcharis/TermiPad: A Simple Note Taking CLI Notepad"
