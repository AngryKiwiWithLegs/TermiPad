# TermiPad P2：发现、受控安装与依赖治理设计

**状态：** 设计提案，尚未进入功能实现。

**适用范围：** 私有原生 macOS Swift/SwiftUI 应用。本文将原始方案中的“GitHub 热门项目发现、浏览、一键安装”和“依赖治理”拆为可验证的产品阶段；不会把推荐元数据、README、AI 输出或网络返回内容直接变成可执行命令。

**设计日期：** 2026-08-25。

> P2 的目标不是把 TermiPad 变成包管理器，而是在不丢失“用户已安装、直接交互 CLI 的图标启动库”核心身份的前提下，让用户可以发现候选项目、理解安装影响，并把经过审查的安装动作交给自己选择的终端执行。

## 1. 原始意图与新的边界

原始技术方案将 P2 定义为两项后续能力：GitHub 热门新项目发现与一键安装，以及跨 npm、pip、Homebrew、Cargo 的依赖冲突治理。它同时明确指出 GitHub 没有官方 Trending API，且陌生项目的一键安装必须先展示项目简介并要求用户确认。这个判断正确，但不足以覆盖安装阶段的供应链执行风险。

P0/P1 的命令对象是**用户已安装并确认的本地交互式 CLI**。P2 一旦可以建议或执行安装，就新增了四类责任：TermiPad 要说明推荐依据；要限定下载与安装来源；要把安装造成的文件、网络、依赖和可执行代码影响展示给用户；还要在安装后避免把失败、同名可执行文件或服务型组件误当作可启动工具。

| 维度 | P0/P1 已有模型 | P2 后必须新增的模型 |
|---|---|---|
| 对象 | 本地已安装可执行文件 | 远程发现条目、安装候选、安装回执与版本快照 |
| 信任来源 | 本地扫描、保守 GitHub 元数据 | GitHub 发现、官方包索引/受限安装渠道、用户审查 |
| 风险动作 | 用户点击后向终端启动已拥有的命令 | 用户点击后可能下载、解包、编译并执行第三方代码 |
| 完成判定 | 候选进入收件箱且用户确认 | 安装前预览、明确同意、终端执行、独立本地验证、再进入候选收件箱 |
| 责任边界 | 不安装第三方软件 | 不静默安装；不替用户决定来源、版本、权限或依赖策略 |

## 2. 推荐决策：采用“发现 → 审查 → 受控终端安装 → 验证收录”

不建议把 P2 做成无感的“一键安装”。产品可保留简短入口文案，但真实行为应是 **一次经审查的终端安装**：用户先看到不可编辑但可复制的安装计划和完整命令，再明确选择“复制命令”或“在我选择的终端执行”。任何网络内容都不能直接拼接为 shell 命令。

| 方案 | 用户体验与能力 | 安全与产品取舍 | 成本 | 设置复杂度 |
|---|---|---|---|---|
| A. 发现与浏览，不提供安装 | 展示候选、证据和官方链接；用户自行安装后由现有扫描收录 | 风险最低，但从发现到使用的链路较长 | 低；仅用户触发的公共 API 查询 | 低 |
| B. 受限来源的经审查终端安装（**推荐**） | 先支持官方 Homebrew formula；用户看完计划后复制或交由终端执行，完成后重新扫描 | 保留用户控制，严格限制安装来源；不试图统一解决所有生态 | 低；无服务端、无后台轮询 | 中 |
| C. 跨生态自动安装、自动升级和全局依赖治理 | npm、pip、Cargo、Homebrew 全覆盖并自动选择隔离方式 | 产品承诺和攻击面急剧扩大；需要环境、锁定、回滚、授权、日志和长期安全响应能力 | 高；需持续兼容与安全维护 | 高 |

**建议：** 先实现 A，再实现 B；C 不列入当前 P2 承诺。P2-B 的产物是“可信渠道安装协助”，不是通用软件安装器。P2-C 只有在 B 完成真实使用验证、签名/公证发行能力具备，并获得单独产品立项后才进入设计。

## 3. P2-A：热门发现与候选浏览

### 3.1 产品定义

新增侧边栏“发现”页面。它不是工具库，也不是应用商店；其内容是一组**待审查的远程项目候选**。每条卡片必须明确展示：项目名称、仓库拥有者、仓库链接、许可信息（若 API 返回）、创建/最近推送时间、星标数、分叉数、是否 fork、是否 archived、推荐理由、数据时间与“这不是官方 Trending 排名”的声明。

GitHub Search 结果最多返回 1,000 条，并按多因素“最佳匹配”排序；它不是官方热门榜。P2 因而不得使用“GitHub 官方热门”或“Trending”作为事实标签，而应使用“TermiPad 发现候选（可解释排序）”。搜索接口还可能返回 `incomplete_results`，出现时必须将该轮结果标记为不完整，而不是把排名呈现为稳定事实。[1]

### 3.2 可解释的本地启发式

首版不使用 AI 给项目排序，也不抓取任意网页。仅使用 GitHub 公共仓库 API 已提供、可显示和可缓存的字段构成**透明启发式**：近期活跃度、星标增长代理、主题标签、许可证是否存在、非 fork、非 archived、README/描述中是否出现交互式 CLI 信号。任何分数只用于本地排序，不能当作安全评级或质量担保。

推荐结果必须通过以下强制筛选才可呈现为“可安装渠道待查”：公开仓库、非 archived、非 fork、具备明确项目主页或 README、且没有服务/daemon/库优先的明显信号。无法判断的项目仍可作为“浏览候选”展示，但没有安装入口。

### 3.3 网络、缓存与隐私

P2-A 默认关闭；用户手动点击“刷新发现”后才访问 `api.github.com`。不进行后台常驻监控、不设每日自动拉取、不上传工具库、命令、路径、变量值、API Key 或用户 GitHub 身份。默认匿名公共请求只适合低频个人使用；GitHub 对未认证 REST 请求设定每 IP 每小时 60 次的一般上限，搜索又有更严格的专属限制。[2] 搜索端点当前允许未认证请求每分钟 10 次、认证请求每分钟 30 次。[1]

实现必须在本地保存请求规范化参数、响应时间、ETag、`Last-Modified`、限流头和最小化展示字段。刷新严格串行；遇到 `429`、`403` 或 `x-ratelimit-remaining: 0` 时停止并按 `Retry-After` 或 `x-ratelimit-reset` 退避。GitHub 明确建议避免轮询、避免并发请求、使用条件请求与 `304 Not Modified` 缓存结果。[3] 用户若未来选择连接自己的 GitHub 帐户，令牌只保存在 Keychain，权限最小化且仅用于提高速率；P2-A 不需要该令牌才能工作。

### 3.4 P2-A 的非目标

P2-A 不抓取 GitHub owner 头像，不从 README 提取可执行命令，不自动接受候选，不把 star 数当安全评分，不执行安装检查命令，不打开第三方网页，也不创建后台同步任务。

## 4. P2-B：受控终端安装协助

### 4.1 首版唯一受支持渠道：官方 Homebrew formula

P2-B 仅支持已在用户机器存在的 Homebrew，且仅允许 **`homebrew/core` 的官方 formula**。不安装 Homebrew 自身；不执行 `curl | sh`；不支持 cask、非官方 tap、tap URL、Git URL、`--HEAD`、本地路径、`sudo`、环境变量前缀、管道、重定向、命令替换或多命令串联。

选择 Homebrew formula 是范围控制，不是对软件安全性的绝对承诺。Homebrew 的官方核心渠道通过维护者审查、审核过的元数据中的校验和、签名 JSON API 和官方 bottle 构建等机制降低供应链风险；官方文档同时强调第三方 tap 是可执行代码，默认不应信任。[4] 对 cask，Homebrew 说明其通常直接安装上游预编译应用，信任模型弱于 core formula；因此 cask 不进入 P2-B 首版。[4]

如果 Homebrew 不存在、版本不可读取或渠道不是官方 core，界面只显示安装条件和“复制官方说明链接”；绝不代替用户安装包管理器。Homebrew 自己也要求用户在其安装脚本执行前确认将执行的动作。[5]

### 4.2 安装计划而非远程命令

远程发现条目与安装渠道之间不得存在“README 命令映射”。可安装项目必须经过一个本地签名/随应用发布的 `InstallCatalog` 映射，最少包含：稳定 GitHub repository ID、允许的 Homebrew formula 名、预期 CLI 可执行文件名集合、允许的架构、许可证提示、映射审核版本与审核时间。映射记录只能由 TermiPad 的正式更新变更；GitHub API、AI、README、搜索标题或网页内容均不能创建或修改它。

用户选择“审查安装”后，应用以只读 `InstallPlan` 呈现以下内容：

| 必显字段 | 目的 |
|---|---|
| 仓库、Homebrew core formula、映射审核时间 | 让用户区分发现来源与实际安装来源 |
| 精确版本/可用版本、目标架构、预期二进制 | 避免名称近似或意外二进制 |
| 完整固定命令 | 用户可复制、阅读并在外部终端复核 |
| 影响说明 | 可能下载、写入 Homebrew prefix、解析依赖、运行包管理器步骤 |
| 可信度限制 | 明确“官方渠道/校验和不等于无恶意或适合你的环境” |
| 已安装/冲突/未知状态 | 只读预检结果；未知状态禁止默认执行 |
| 取消与复制路径 | 复制始终可用，取消不留下安装状态 |

安装命令由本地 token 化 recipe 编译，首版仅允许等价于 `brew install --formula <approved-formula>` 的参数序列。编译器不得接收一段自由文本；对 formula 名使用严格正则和 allowlist 双重校验，并在执行前将 token 重新序列化为展示文本。任何不符合语法、含换行或 shell 元字符的输入均应拒绝并写入仅含固定事件类别的本地诊断。

### 4.3 用户确认、终端边界与收录

默认主按钮为“复制安装命令”。“在终端执行”只有在用户勾选“我已审查完整命令与影响”后才可用，并在按钮中显示实际 formula 名。TermiPad 仍将命令交给用户在设置中选择的 Terminal.app、iTerm、Warp 或复制目标；不会在应用进程内直接运行包管理器、请求管理员权限、输入密码、绕过终端自动化授权或隐藏输出。

终端返回并不代表成功。用户回到 TermiPad 后必须主动点击“验证并扫描”；应用只做现有的本地 PATH/受限目录扫描、健康检查和候选收件箱流程。只有发现 `InstallCatalog` 允许的预期可执行文件并经用户确认后，才创建工具库记录。安装失败、额外文件、服务型组件、同名但路径不匹配的文件或扫描不确定性都不得自动收录。

### 4.4 安装记录、卸载与隐私

本地 `InstallReceipt` 仅保存：渠道、catalog ID、formula、用户确认时间、计划版本、验证结果枚举与用户手动关联的工具 ID。它不保存终端完整输出、Homebrew prefix、绝对路径、环境变量、下载 URL、命令历史或用户目录。默认 JSON 备份不含 receipt；诊断只记录安装计划打开/复制/交给终端/验证成功或失败等固定类别。

P2-B 不提供“一键卸载”或“回滚”。卸载和升级一样可能影响其他工具，必须先在未来的受控版本治理设计中提供依赖影响预览、明确确认、失败恢复与证据模型后再讨论。

## 5. P2-C：依赖与版本治理的正确拆分

“防止重复安装、版本冲突并自动选择最合适隔离方式”不是一个跨生态的通用操作。包管理器的来源、依赖解析、安装位置、生命周期脚本、锁定文件和回滚能力各不相同。因此 P2-C 不能从“自动裁决”开始，只能从**只读清单与局部预检**开始。

| 生态 | 已知风险/语义 | P2 的允许动作 | P2 首版禁止动作 |
|---|---|---|---|
| Homebrew core formula | 官方 core 有审核和校验机制，但安装仍会改变用户 prefix 与依赖集 | 检测已安装、只读 `info`/版本摘要、单 formula 安装计划 | third-party tap、cask、卸载、升级、`--HEAD`、自动修复依赖 |
| npm | `npm install`/`npm ci` 可运行 `preinstall`、`install`、`postinstall`、`prepare` 等生命周期脚本。[6] | 仅在 P2-C 研究期显示生态风险与复制命令 | 自动/终端执行全局 npm 安装、Git URL、生命周期脚本绕过承诺 |
| pip | 默认不防远程篡改且可能运行发行包任意代码；安全模式要求本地 hashes、全依赖 pin 和常见情况下的 binary-only 策略。[7] | 仅显示环境检测、虚拟环境建议和复制命令 | 修改系统 Python、`--break-system-packages`、自动创建/选择环境、未锁定安装 |
| Cargo | `cargo install` 默认可能重新解析依赖；`--locked` 才使用随包提供的 lockfile。[8] | 只读列出安装记录和版本；后续可预览固定 crate 计划 | Git source、分支/tag 浮动引用、没有 lockfile 时自动降级安装 |

P2-C 的第一个可交付物应是“环境与安装来源报告”：按工具显示检测到的包管理器、安装位置类别、已知版本、是否由 TermiPad receipt 关联、是否可安全检查、以及“需要用户在终端处理”的原因。它不能尝试跨 Homebrew/npm/pip/Cargo 求解依赖树，也不能把“版本较新”自动解释为“应升级”。

pip 本身说明安装过程会选择依赖并可能构建 wheel；它提供 `--dry-run --report` 生成 JSON 解析报告，但失败恢复不是其承诺。[9] Cargo 也说明 `--locked` 的代价是不会获得依赖修复或更新。[8] 这些差异说明 TermiPad 最多可以展示生态各自给出的计划和证据，不能声称自己已经计算出一个通用的“最优隔离/无冲突方案”。

## 6. 攻击面与强制控制

| 新攻击面 | 典型失败模式 | P2 的强制控制 | 残余风险与用户告知 |
|---|---|---|---|
| 热门排序操纵 | star、fork 或描述被操纵 | 透明启发式、非官方排名标签、来源字段和时间戳 | 热度不代表安全、维护质量或适合度 |
| 同名/近似名项目 | typosquatting、slopsquatting、冒名仓库 | discovery 与 install catalog 分离；安装只允许稳定仓库 ID 映射 | 用户仍需阅读项目和渠道信息 |
| README/AI 提示注入 | 远程文本诱导执行命令 | README/AI 永不生成安装 recipe；AI 无法改变命令 | 远程描述仅是参考内容 |
| 仓库接管或 release 变更 | 已发现项目后被换内容 | 使用审核 catalog、展示审核时间、渠道重新验证 | 官方渠道与签名降低风险，不保证无恶意 |
| 下载/构建阶段执行代码 | package lifecycle、编译、post-install | P2-B 仅 Homebrew core formula；npm/pip/Cargo 不执行 | 即使通过渠道审核，安装仍可能执行第三方代码 |
| 第三方 tap/registry 混入 | 加载可执行 recipe 或 dependency confusion | 禁止非官方 tap、替换 registry、Git URL、额外 index | 未来若扩展必须另设 per-ecosystem policy |
| Shell 注入 | 网络字段进入 shell、参数被拼接 | token recipe、allowlist、拒绝元字符、无自由文本命令 | 现有用户自定义启动命令仍由用户负责 |
| 权限升级 | `sudo`、密码输入、系统目录写入 | recipe 禁止 `sudo`；应用不读取/输入密码 | 用户可在外部终端自行做高权限操作，TermiPad 不协助 |
| PATH/二进制混淆 | 同名可执行文件被误收录 | 预期 executable allowlist、健康检查、候选收件箱 | 无法确定时保留为待处理，不自动添加 |
| 隐私扩大 | 后台发送工具库、令牌或路径 | 默认关闭、仅手动刷新、最小字段缓存、Keychain、无路径/命令日志 | GitHub 仍可看到请求 IP 与公共查询 |
| API 限流/不可用 | 刷新导致限流或错误重试 | 串行、ETag、退避、缓存回退、不自动重试风暴 | 发现功能可能暂不可用，不影响本地库 |

## 7. 建议的数据与模块边界

P2 应新增独立模块，绝不把远程候选直接塞入 `TerminalTool`：

```text
DiscoveryService          只获取并缓存远程 DTO；不产生命令
DiscoveryRanking          只做可解释排序；不作安全评级
InstallCatalog            随应用发布的审核映射；远程数据不可修改
InstallPolicy             渠道、参数、版本、权限与禁止语法的纯函数策略
InstallPlanCompiler       从 token 化 recipe 生成只读安装计划
InstallReviewView         展示证据、影响、精确命令与明确确认
TerminalLauncher          复用现有用户选择终端/复制边界，不扩权
InstallVerifier           复用扫描、健康检查与候选收件箱；不以终端退出码直接收录
EnvironmentReportService  只读生态检测与版本快照，不自动修复
```

建议的核心模型为 `DiscoveryItem`、`DiscoveryEvidence`、`CatalogEntry`、`InstallRecipe`、`InstallPlan`、`InstallReceipt`、`EnvironmentSnapshot` 和 `VerificationResult`。其中 `CatalogEntry` 与 `InstallRecipe` 必须是应用随版本发布、可审计、可单测的静态数据；`DiscoveryItem` 是可过期的缓存数据；`InstallReceipt` 只保存在本机且默认不进入备份。

## 8. 实施分期、验收与退出条件

| 阶段 | 交付内容 | 必须通过的安全验收 | 不做什么 |
|---|---|---|---|
| P2-A0：策略与测试骨架 | 数据模型、缓存、限流、排序解释、网络开关 | 所有网络默认关闭；无 token 情况可优雅退化；所有 API 错误与限流可测试 | 不显示安装按钮 |
| P2-A1：发现浏览 | 手动刷新、缓存、来源证据、非官方排名说明、链接复制/打开 | ETag/退避、禁止头像、禁止 README 命令、结果不完整标识、隐私诊断审计 | 不自动刷新或推荐到工具库 |
| P2-B0：安装计划 | 静态 Homebrew core catalog、预检、命令编译、审查界面 | policy fuzz/单测拒绝所有 shell 元字符、tap、URL、`sudo`、未知 formula；plan snapshot 测试 | 不实际执行安装 |
| P2-B1：受控终端交接 | 复制优先、明确确认后终端交接、安装 receipt、重新扫描 | 自动化拒绝复制回退；不能从终端退出码自动收录；UI/单测覆盖取消、失败和同名冲突 | 不安装 Homebrew、不卸载、不升级 |
| P2-C0：只读环境报告 | Homebrew/npm/pip/Cargo 检测、版本与来源报告 | 不运行安装/升级；不写用户环境；输出不含路径、命令、令牌 | 不自动解决依赖或版本冲突 |
| P2-C1：单生态受控升级研究 | 仅在签名发行与真实用户试用后另立项 | 每个生态独立威胁模型、回滚、冲突和故障恢复验证 | 不做跨生态统一求解器 |

每个阶段均应扩展 `scripts/verify-macos.sh` 的静态策略防护、Swift 单元测试、Xcode 原生 build 与 UI 冒烟。P2-B/C 改变“点击可能导致第三方代码安装”的用户信任模型，因此在外部分发前还必须完成 Developer ID、Hardened Runtime、公证、Gatekeeper 冷启动与真实旧 store 升级验证；这些既有外部闸门不会因 P2 设计而消失。

## 9. 推荐的第一开发批次

获准进入实现后，应只启动 **P2-A0 + P2-A1**。它能让产品获得“发现新 CLI”的价值，同时不改变 P0/P1 的“只对已安装工具执行启动命令”的边界。完成并通过真实 macOS 集中验证后，再由用户决定是否开启 P2-B0 的 Homebrew 安装计划；该阶段仍不执行安装。

P2-B1 需要一次单独的产品确认，因为它首次把 TermiPad 从“启动器”扩展为“会将安装命令交给终端的协助者”。只有在用户明确接受上述来源限制、确认体验与诊断边界后才应实施。

## References

[1]: https://docs.github.com/en/rest/search/search?apiVersion=2026-03-10 "GitHub: REST API search endpoints"
[2]: https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api "GitHub: REST API rate limits"
[3]: https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api?apiVersion=2026-03-10 "GitHub: REST API best practices"
[4]: https://docs.brew.sh/Homebrew-Security-and-Supply-Chain "Homebrew: Security and supply chain"
[5]: https://docs.brew.sh/Installation "Homebrew: Installation"
[6]: https://docs.npmjs.com/cli/v11/using-npm/scripts/ "npm: Scripts and lifecycle events"
[7]: https://pip.pypa.io/en/stable/topics/secure-installs/ "pip: Secure installs"
[8]: https://doc.rust-lang.org/cargo/commands/cargo-install.html "Cargo Book: cargo install"
[9]: https://pip.pypa.io/en/stable/cli/pip_install/ "pip: pip install"
