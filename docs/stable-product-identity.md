# TermiPad：地名版本代号体系

**生效日期：** 2026-08-25
**适用对象：** TermiPad 的内部稳定基线、预览开发线与未来私有 beta 候选。

## 1. 命名原则

TermiPad 保留为产品名、私有仓库名、Swift 模块名和当前 bundle 标识。每一代**经过完整验证的稳定版本**另获一个地名代号，采用类似经典 macOS 版本的“产品名 + 地名”表达，而不是为每个开发分支重新起一个独立商品名。

> 稳定版本名的格式为：**TermiPad [地名]**。
>
> 例如，当前基线为 **TermiPad Mendocino**。

本系列采用**加利福尼亚太平洋海岸城镇与海湾**作为主题。它与“终端工具库”强调的本地、清晰、可探索但不越权的体验相符，同时避免使用苹果已经公开采用过的 macOS 代号，例如 Ventura、Sonoma、Monterey、Mojave、Catalina、Big Sur、Sequoia 或 Yosemite。

地名代号不替代语义版本号。它是人可读的代际身份；语义版本、Git commit 和验证证据仍是工程上的事实来源。

## 2. 当前稳定版本

当前已通过真实 Apple Silicon macOS 集中验证的 P0 + P1 基线命名为：

# TermiPad Mendocino

**内部版本标识：** `1.0.0`

**发布通道：** Stable（私有已验证基线）

**代码验证基线：** `6a3bd11`（`Ensure UI tests create a main window`）

**审计记录：** `c361db3`（私有 beta 验证审计更新）

“Mendocino”代表第一代完整的本地优先工具库：候选收件箱、保守扫描、手动管理、命令模板、受控终端启动、GitHub/AI 信息边界、备份与隔离恢复、健康检查、工作目录、诊断、更新提示，以及真实 macOS 集中验证。

**Stable** 仅表示该基线已完成项目内部定义的代码与真实 macOS 验证；它不表示已满足 Developer ID、Hardened Runtime、公证、Gatekeeper 冷启动或外部分发验收。

## 3. P2 与稳定代号的关系

地名只在一个能力批次完成、代码冻结并通过完整集中验证后升级。P2 的开发过程不能提前消耗下一个稳定地名，避免功能实验与可回退稳定版本混淆。

| 状态 | 面向用户的写法 | 语义版本建议 | Git/工程标识 | 含义 |
|---|---|---|---|---|
| 当前稳定基线 | **TermiPad Mendocino** | `1.0.0` | `termipad-mendocino-1.0.0` | 已验证的 P0 + P1 本地版本；不含 P2 功能 |
| P2-A 发现开发 | **TermiPad Mendocino — Discovery Preview** | `1.1.0-preview.N` | `p2/discovery-preview` | 仅手动发现、缓存、来源证据和可解释排序；不安装软件 |
| P2-A 验证后下一稳定版 | **TermiPad Sausalito** | `2.0.0` | `termipad-sausalito-2.0.0` | P2-A 已完成并通过完整验证后的下一稳定代 |
| P2-B 安装评审开发 | **TermiPad Sausalito — Install Review Preview** | `2.1.0-preview.N` | `p2/install-review-preview` | 仅开发受控安装计划和审查界面；尚不代表通用一键安装 |
| P2-B 验证后下一稳定版 | **TermiPad Morro Bay** | `3.0.0` | `termipad-morro-bay-3.0.0` | 仅在受限渠道安装协助完成安全验收后使用 |
| 未来只读环境报告 | **TermiPad Avalon — Environment Preview** | `3.1.0-preview.N` | 未来单独立项 | 仅展示生态与版本状态；不自动升级、不卸载、不解冲突 |

任何预览版本都必须在产品文档和 UI 中清楚标明 **Preview**，并可随时回退到前一个稳定代号。预览不改写稳定版本的备份格式、数据存储路径、Keychain 服务、bundle identifier 或用户命令。

## 4. 保留代号池

下列名称用于后续稳定代际的候选池，而非已承诺的功能顺序：

| 顺序 | 地名代号 | 使用条件 |
|---|---|---|
| 1 | **Mendocino** | 当前 P0 + P1 已验证稳定版 |
| 2 | **Sausalito** | P2-A 发现能力完成、冻结并验证后 |
| 3 | **Morro Bay** | P2-B 受控安装协助完成独立安全验收后 |
| 4 | **Avalon** | 后续具备清晰、安全边界的新稳定能力批次 |
| 5 | **Solvang** | 未来候选；仅在需要下一稳定代时启用 |
| 6 | **Arcata** | 未来候选；仅在需要下一稳定代时启用 |

名称本身不表示质量、安全等级、地理来源、与当地机构的合作，也不构成商标或域名可用性的法律结论。在将来外部分发前，仍需对最终名称进行商标、域名、App Store 及当地法律层面的正式清查。

## 5. 采用规则

从现在起：

1. 已验证稳定基线统一称为 **TermiPad Mendocino**，而不是“Shelldex”或泛称“稳定版”。
2. P2-A 实施期间使用 **TermiPad Mendocino — Discovery Preview**；它不能被表述为下一稳定版本。
3. 只有 P2-A 的范围、测试和真实 macOS 集中验证全部完成时，才启用 **TermiPad Sausalito**。
4. 外部分发仍需单独满足 Developer ID、Hardened Runtime、公证、Gatekeeper 冷启动和真实旧 store 升级验证；地名代号不绕过这些闸门。
5. `TermiPad` 的技术名称和现有本地数据标识在当前阶段不改动，以保护 Mendocino 已验证基线。
