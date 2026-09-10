#!/usr/bin/env bash
# TermiPad 的本机 macOS 验证入口。
# 默认执行：SwiftPM 清单校验、单元测试、XcodeGen 生成、xcodebuild 构建、UI 冒烟测试。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SKIP_UI=0
if [[ "${1:-}" == "--skip-ui" ]]; then
  SKIP_UI=1
elif [[ $# -gt 0 ]]; then
  echo "用法：$0 [--skip-ui]" >&2
  exit 64
fi

for command in swift xcodebuild xcodegen; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "缺少 $command。请安装完整 Xcode，并运行：brew install xcodegen" >&2
    exit 69
  fi
done

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_DIR="${TERMIPAD_VERIFY_OUTPUT:-$ROOT_DIR/.verification/$TIMESTAMP}"
DERIVED_DATA="$LOG_DIR/DerivedData"
UI_DERIVED_DATA="$LOG_DIR/UITestDerivedData"
RESULT_BUNDLE="$LOG_DIR/TermiPadUITests.xcresult"
mkdir -p "$LOG_DIR"

FAILED_STEP=""
run_step() {
  local name="$1"
  shift
  echo
  echo "========== ${name} =========="
  if "$@" 2>&1 | tee "${LOG_DIR}/${name}.log"; then
    echo "[通过] ${name}"
  else
    FAILED_STEP="${name}"
    echo "[失败] ${name}；完整日志：${LOG_DIR}/${name}.log" >&2
    return 1
  fi
}

write_summary() {
  {
    echo "# TermiPad 本机验证摘要"
    echo
    echo "- 时间：$(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "- 提交：$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
    echo "- 日志目录：$LOG_DIR"
    echo
    echo "## 结果"
    if [[ -n "$FAILED_STEP" ]]; then
      echo "- **失败步骤：$FAILED_STEP**"
    else
      echo "- **所有请求步骤均通过。**"
    fi
    echo
    echo "## 关键诊断"
    echo '```text'
    grep -E -i '(^|[[:space:]])(error|warning|fatal error):|BUILD FAILED|TEST FAILED|Assertion' "$LOG_DIR"/*.log 2>/dev/null || true
    echo '```'
  } > "$LOG_DIR/summary.md"
}
trap write_summary EXIT

swift_source_guard() {
  if grep -RInF '\(AppCopy.text(\"' Sources; then
    echo '检测到 Swift 字符串插值中被错误转义的 AppCopy 调用。' >&2
    return 1
  fi
  if grep -RInF 'case (.available, .notInspectable,' Sources; then
    echo '检测到 ToolHealth 二元元组被错误写成三元 case。' >&2
    return 1
  fi
  if grep -RInE 'summary\.(toolsAdded|toolsUpdated|candidatesAdded|candidatesUpdated)' Sources Tests UITests; then
    echo '检测到 BackupRestoreSummary 已废弃字段名。' >&2
    return 1
  fi
  if grep -REn 'TerminalLauncher|CommandTemplate|modelContext\.insert|TerminalTool\(|CandidateTool\(|Process\(|NSAppleScript|brew install|npm install|pip install|cargo install' Sources/DiscoveryPreview*.swift Sources/DiscoveryService.swift; then
    echo '检测到 Discovery Preview 触及命令执行、安装或工具库写入边界。' >&2
    return 1
  fi
  if grep -RInF 'response.isIncomplete' Sources/DiscoveryService.swift; then
    echo '检测到 GitHub 搜索 DTO 的错误 isIncomplete 字段引用。' >&2
    return 1
  fi
  local controlled_install_code environment_report_code
  controlled_install_code="$(sed '/^[[:space:]]*\/\//d' Sources/ControlledInstallPlan.swift)"
  environment_report_code="$(sed '/^[[:space:]]*\/\//d' Sources/EnvironmentReport.swift)"
  if printf '%s\n' "$controlled_install_code" | grep -En 'URLSession|Process\(|NSAppleScript|TerminalLauncher|modelContext\.insert|tap |cask |npm install|pip install|cargo install|brew upgrade|brew uninstall'; then
    echo '检测到受控安装目录触及网络、应用内执行、第三方渠道或修改性包管理器命令。' >&2
    return 1
  fi
  if ! printf '%s\n' "$controlled_install_code" | grep -qF 'command: "brew install \(formula)"'; then
    echo '受控安装目录缺少固定 Homebrew core formula 命令模板。' >&2
    return 1
  fi
  if printf '%s\n' "$environment_report_code" | grep -En 'URLSession|NSAppleScript|/bin/sh|modelContext\.insert|install|upgrade|uninstall|remove'; then
    echo '检测到环境报告触及网络、shell、持久化或修改性操作。' >&2
    return 1
  fi
  if ! printf '%s\n' "$environment_report_code" | grep -qF 'task.arguments = ["--version"]'; then
    echo '环境报告必须限定为固定 --version 参数。' >&2
    return 1
  fi
  if grep -En 'pathLookup \?\? executablePath\(for:\)|versionReader \?\? readVersion\(at:\)' Sources/EnvironmentReport.swift; then
    echo '检测到 Swift 6.3 无法稳定推断的环境报告默认函数引用合并写法。' >&2
    return 1
  fi
  if grep -nF 'TerminalLauncher.launch(command:' Sources/InstallEnvironmentView.swift | grep -vF 'TerminalLauncher.launch(command: plan.command'; then
    echo '安装审查只能将静态计划命令交给用户选择的终端。' >&2
    return 1
  fi
  local icon_code
  icon_code="$(sed '/^[[:space:]]*\/\//d' Sources/ToolIconView.swift Sources/ToolIconStore.swift)"
  if printf '%s\n' "$icon_code" | grep -En 'URLSession|AsyncImage|https?://|NSImage\(contentsOf: URL\(string:'; then
    echo '检测到本地图标系统尝试加载网络图像或远程资源。' >&2
    return 1
  fi
  if ! printf '%s\n' "$icon_code" | grep -qF 'customIconFilename'; then
    echo '本地图标系统必须保留受控本地 PNG 优先字段。' >&2
    return 1
  fi
  local task_policy_code
  task_policy_code="$(sed '/^[[:space:]]*\/\//d' Sources/TaskIntent.swift Sources/TaskIntentPolicy.swift Sources/TaskPolicyWorkbenchView.swift)"
  if printf '%s\n' "$task_policy_code" | grep -En 'URLSession|URLRequest|NWConnection|NWListener|WebSocket|NSAppleScript|TerminalLauncher|Process\(|forkpty|posix_openpt|/bin/sh|https?://|stdin|stdout|stderr'; then
    echo '检测到 T0 任务策略触及网络、终端自动化、进程执行、PTY 或远程输入输出边界。' >&2
    return 1
  fi
  if ! printf '%s\n' "$task_policy_code" | grep -qF 'static let definitions'; then
    echo 'T0 任务策略必须保留随应用发布的固定任务目录。' >&2
    return 1
  fi
  local task_execution_code
  task_execution_code="$(sed '/^[[:space:]]*\/\//d' Sources/TaskExecutionService.swift Sources/TaskIntent.swift Sources/TaskPolicyWorkbenchView.swift)"
  # M2b-2（docs/m2b-remote-task-console-design.md §5.4/§7）：受控放宽——
  # 输出档位 ≥ restricted 时 T1 用 Pipe 捕获 stdout/stderr 进仅内存
  # ring buffer（32KB/400 行上限，脱敏后回传末尾片段）。红线不变的部分
  # 仍然锁死：无网络、无终端自动化、无 PTY、无 Shell、无任意 stdin。
  if printf '%s\n' "$task_execution_code" | grep -En 'URLSession|URLRequest|NWConnection|NWListener|WebSocket|NSAppleScript|TerminalLauncher|forkpty|posix_openpt|/bin/sh|https?://|stdin'; then
    echo '检测到 T1 执行器触及网络、终端自动化、PTY、Shell 或进程输入边界。' >&2
    return 1
  fi
  # 捕获只允许出现在 attachOutputCapture 单点（设计 §5.4），且必须与
  # 档位裁决 capturesOutput 绑定；直接 grep Pipe 计数防止散落滥用。
  if [ "$(printf '%s\n' "$task_execution_code" | grep -cE 'Pipe\(\)')" -gt 1 ] \
    || ! printf '%s\n' "$task_execution_code" | grep -qF 'if capturesOutput {'; then
    echo 'T1 输出捕获必须仅在 attachOutputCapture 单点且由档位裁决开关。' >&2
    return 1
  fi
  if ! printf '%s\n' "$task_execution_code" | grep -qF 'process.standardInput = FileHandle.nullDevice'; then
    echo 'T1 执行器必须使用空输入。' >&2
    return 1
  fi
  if ! printf '%s\n' "$task_execution_code" | grep -qF 'process.standardOutput = FileHandle.nullDevice' || ! printf '%s\n' "$task_execution_code" | grep -qF 'process.standardError = FileHandle.nullDevice'; then
    echo 'T1 执行器 minimal 档位必须维持空输出（nullDevice 分支不得删除）。' >&2
    return 1
  fi
  if grep -RInE 'Process\(' Sources | grep -vE 'Sources/(EnvironmentReport|TaskExecutionService|TailnetTunnelService)\.swift'; then
    echo '检测到 T1 之外新增的进程执行入口（M2a 仅 TailnetTunnelService 允许跑 tailscale CLI）。' >&2
    return 1
  fi
  # 备份与任务域隔离（track-protocol §4.5）：Sources/BackupService.swift 不得引用
  # 任何 task 实体——它们的字段（路径/nonce/退出码/时间戳）含本地敏感信息，
  # 永远不应进入可移植的 JSON 备份。
  local backup_code
  backup_code="$(sed '/^[[:space:]]*\/\//d' Sources/BackupService.swift)"
  if printf '%s\n' "$backup_code" | grep -En 'TaskIntent|TaskProjectScope|TaskReviewWindow|projectScopeID|reviewWindowID'; then
    echo '检测到 BackupService 引用 task 域实体——备份绝不含任务历史、项目路径或审阅窗口。' >&2
    return 1
  fi
  # M0 移动端入口（track-protocol stage 4.1）：6 字段永不出本机，绝不进 JSON 备份。
  # 字段在 Sources/TerminalTool.swift 内安全（本地数据），但 Sources/BackupService.swift
  # 任何位置都不得引用——引用即意味着序列化路径中有了该字段。
  if printf '%s\n' "$backup_code" | grep -En 'mobileDisplayName|mobileDescription|showInMobileEntry|allowMobileLaunchRequest|mobileLocalConfirmPolicy|revokeMobilePermissionAt'; then
    echo '检测到 BackupService 引用 M0 移动端入口字段——备份不含手机端显示名/说明/开关。' >&2
    return 1
  fi
  # 更新检查只读网络（track-prototol 用户承诺：A 通知式方案）。
  # UpdateCheckService 必须**不**触发下载、**不**写入 ~/Applications、
  # **不**启动 NSWorkspace.openApplication 自动更新 .app。任何"自动下载/替换"
  # commit 都会绕过 Mac Gatekeeper 信任链 + 引入供应链攻击面。
  local update_check_code
  update_check_code="$(sed '/^[[:space:]]*\/\//d' Sources/UpdateCheckService.swift)"
  if printf '%s\n' "$update_check_code" | grep -En 'NSWorkspace.shared.openApplication|FileManager.default.write|FileManager.default.copy|FileManager.default.move|/bin/sh -c |Process\(|NSAppleScript|TarExtractor|tempDirectory'; then
    echo '检测到 UpdateCheckService 试图自动下载/解压/替换 .app — 违反项目"通知式"承诺。' >&2
    return 1
  fi
  if ! printf '%s\n' "$update_check_code" | grep -qF 'api.github.com/repos/dfdd2001-source/TermiPad'; then
    echo 'UpdateCheckService 必须固定指向 dfdd2001-source/TermiPad releases endpoint，' >&2
    echo '不接受运行时配置——攻击者不能改 endpoint 重定向到恶意 server。' >&2
    return 1
  fi
  if ! printf '%s\n' "$update_check_code" | grep -qF 'currentAppVersion'; then
    echo 'UpdateCheckService 必须从 bundle 读 currentAppVersion 用于版本比较——' >&2
    echo '不能用 UserDefaults 配置攻击者控制的版本号。' >&2
    return 1
  fi

  mcp_code="$(sed '/^[[:space:]]*\/\//d' Sources/MCPStdIORuntime.swift Sources/TaskMCPBridge.swift Sources/TaskMCPSettings.swift Sources/TaskPolicyWorkbenchView.swift)"
  if printf '%s\n' "$mcp_code" | grep -En 'URLSession|URLRequest|NWConnection|NWListener|WebSocket|NSAppleScript|TerminalLauncher|forkpty|posix_openpt|/bin/sh|https?://|NSXPC|XPCListener|XPCSession|socket|Process\(|Pipe\('; then
    echo '本机 MCP 目录出现网络、XPC、进程、终端交接、PTY 或输出管道入口。' >&2
    return 1
  fi
  if ! printf '%s\n' "$mcp_code" | grep -qF 'FileHandle.standardOutput.write(data)' || ! printf '%s\n' "$mcp_code" | grep -qE '"additionalProperties": false'; then
    echo '本机 MCP 缺少 stdio 协议输出或严格工具 schema 防护。' >&2
    return 1
  fi
  if grep -En 'ModelContainer|ModelContext|FetchDescriptor|TaskIntentPolicy' Sources/MCPStdIORuntime.swift; then
    echo 'stdio MCP 子进程不得直接打开或操作 TermiPad SwiftData store。' >&2
    return 1
  fi
  # M0 移动端入口（track-protocol stage 4.1）：6 字段永不出本机，绝不进 MCP 响应。
  # LocalMCPTaskState 8 字段白名单（docs/task-result-minimal-spec.md §2.3）固定不动。
  if printf '%s\n' "$mcp_code" | grep -En 'mobileDisplayName|mobileDescription|showInMobileEntry|allowMobileLaunchRequest|mobileLocalConfirmPolicy|revokeMobilePermissionAt'; then
    echo '检测到 MCP 引用 M0 移动端入口字段——MCP 响应白名单固定 8 字段，不含手机端字段。' >&2
    return 1
  fi
  if ! grep -qF 'CFMessagePortCreateRemote' Sources/TaskMCPBridge.swift || ! grep -qF 'CFMessagePortCreateLocal' Sources/TaskMCPBridge.swift; then
    echo '本机 MCP 必须通过应用内 CFMessagePort 桥接，而非让 stdio 子进程直接竞争 store。' >&2
    return 1
  fi
  # M1 同网配对核心（feature/m1-local-network-pairing）：纯密码学 + Keychain。
  # 这两个文件绝不允许网络、进程、终端自动化入口——网络监听只允许出现在
  # 未来的 Sources/MobilePairingService.swift 并由专门守卫圈定。
  local mobile_pairing_core_code
  mobile_pairing_core_code="$(sed '/^[[:space:]]*\/\//d' Sources/MobilePairingCrypto.swift Sources/PairedDeviceStore.swift)"
  if printf '%s\n' "$mobile_pairing_core_code" | grep -En 'URLSession|URLRequest|NWConnection|NWListener|WebSocket|NSAppleScript|TerminalLauncher|Process\(|Pipe\(|forkpty|posix_openpt|/bin/sh|socket\('; then
    echo '检测到 M1 配对核心触及网络、进程或终端自动化边界——它必须是纯密码学 + Keychain。' >&2
    return 1
  fi
  # M1 配对协议层：白名单 + 最小载荷 + AEAD 信封 + 握手状态机，同样零 I/O。
  local mobile_pairing_protocol_code
  mobile_pairing_protocol_code="$(sed '/^[[:space:]]*\/\//d' Sources/MobilePairingProtocol.swift)"
  if printf '%s\n' "$mobile_pairing_protocol_code" | grep -En 'URLSession|URLRequest|NWConnection|NWListener|WebSocket|NSAppleScript|TerminalLauncher|Process\(|Pipe\(|forkpty|posix_openpt|/bin/sh|socket\('; then
    echo '检测到 M1 配对协议层触及网络、进程或终端自动化边界——网络监听只允许在 MobilePairingService.swift。' >&2
    return 1
  fi
  # 全局白名单：整个 Sources 里 NWListener/NWConnection 只允许出现在
  # Sources/MobilePairingService.swift（M1 同网监听，默认关闭）与
  # Sources/TailnetTunnelService.swift（M2a 回环监听，默认关闭）。
  if grep -RInE 'NWListener|NWConnection' Sources | grep -vE 'Sources/(MobilePairingService|TailnetTunnelService)\.swift'; then
    echo '检测到 M1/M2a 监听文件之外的网络监听入口。' >&2
    return 1
  fi
  # M2a 隧道守卫：tailscale CLI 的可执行路径字面量只允许出现在
  # TailnetTunnelService.swift（固定绝对路径纪律）；任何其他文件不得拼 CLI。
  if grep -RIn 'bin/tailscale' Sources | grep -v 'Sources/TailnetTunnelService\.swift'; then
    echo '检测到 TailnetTunnelService 之外的 tailscale CLI 调用。' >&2
    return 1
  fi
  # M2a 红线：永久禁用 Funnel（公网暴露入口）。字面量出现即验证失败。
  if grep -RInE '"funnel| funnel |--funnel' Sources; then
    echo '检测到 funnel 子命令引用——公网暴露红线，永久禁止。' >&2
    return 1
  fi
  # iOS 伴侣 app：NWBrowser 只允许出现在 CompanionApp/ 下；Sources/ 不得使用。
  if grep -RInE 'NWBrowser' Sources; then
    echo '检测到 Mac 端引入 NWBrowser——浏览器仅属于 iOS 伴侣 app。' >&2
    return 1
  fi
  # M2b 防线 1（设计 §7）：LocalAuthentication 只允许 iOS 伴侣 app——
  # Mac 端不引入生物识别依赖。
  if grep -RInE 'import LocalAuthentication|LAContext' Sources; then
    echo '检测到 Mac 端引入 LocalAuthentication——App 锁仅属于 iOS 伴侣 app。' >&2
    return 1
  fi
  # iOS Info.plist 必填：缺 NSLocalNetworkUsageDescription 或 NSBonjourServices 则本地发现会被静默杀。
  if ! grep -qF 'NSLocalNetworkUsageDescription' CompanionApp/Info.plist \
     || ! grep -qF '_termipad-m1._tcp' CompanionApp/Info.plist; then
    echo 'iOS 伴侣 Info.plist 必须声明 NSLocalNetworkUsageDescription 和 NSBonjourServices=_termipad-m1._tcp。' >&2
    return 1
  fi
}

run_step toolchain bash -c 'xcodebuild -version && swift --version && xcodegen --version'
run_step scripts-syntax bash -c 'bash -n scripts/verify-macos.sh && bash -n scripts/verify-release-artifact.sh'
run_step swift-source-guard swift_source_guard
run_step package-manifest swift package dump-package
run_step unit-tests swift test

rm -rf TermiPad.xcodeproj
run_step xcodegen xcodegen generate
run_step build xcodebuild \
  -project TermiPad.xcodeproj \
  -scheme TermiPad \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  clean build

if [[ "$SKIP_UI" -eq 0 ]]; then
  run_step ui-build-for-testing xcodebuild \
    -project TermiPad.xcodeproj \
    -scheme TermiPad \
    -destination 'platform=macOS' \
    -derivedDataPath "$UI_DERIVED_DATA" \
    build-for-testing

  UI_RUNNER="$(find "$UI_DERIVED_DATA/Build/Products" -type d -name 'TermiPadUITests-Runner.app' -print -quit 2>/dev/null || true)"
  if [[ -z "$UI_RUNNER" ]]; then
    FAILED_STEP="ui-runner-discovery"
    echo "未找到 TermiPadUITests-Runner.app；请查看 $LOG_DIR/ui-build-for-testing.log" >&2
    exit 1
  fi
  run_step ui-runner-signature codesign --verify --deep --strict --verbose=2 "$UI_RUNNER"

  if ! run_step ui-smoke-test xcodebuild \
    -project TermiPad.xcodeproj \
    -scheme TermiPad \
    -destination 'platform=macOS' \
    -derivedDataPath "$UI_DERIVED_DATA" \
    -resultBundlePath "$RESULT_BUNDLE" \
    test-without-building; then
    if [[ -d "$RESULT_BUNDLE" ]]; then
      mkdir -p "$LOG_DIR/ui-attachments"
      xcrun xcresulttool export attachments \
        --path "$RESULT_BUNDLE" \
        --output-path "$LOG_DIR/ui-attachments" >/dev/null 2>&1 || true
      echo "UI 失败附件：$LOG_DIR/ui-attachments" >&2
      find "$LOG_DIR/ui-attachments" -maxdepth 1 -type f -print 2>/dev/null || true
    fi
    exit 1
  fi

  if [[ -d "$RESULT_BUNDLE" ]]; then
    mkdir -p "$LOG_DIR/ui-attachments"
    xcrun xcresulttool export attachments \
      --path "$RESULT_BUNDLE" \
      --output-path "$LOG_DIR/ui-attachments" >/dev/null 2>&1 || true
  fi
fi

# UpdateCheckService 不应让用户配置 feed URL（那是 G6 闸门漏洞：让 social
# engineering 把受害者引到填 https://evil.com/updates.json）。PreferencesView
# 不应出现 updateFeedURL UserDefault、URL 输入框,或任何 URL 输入路径。
if grep -RnE 'updateFeedURL' Sources/PreferencesView.swift Sources/UpdateCheckService.swift 2>/dev/null; then
  echo '检测到 updateFeedURL — 违反 G6 闸门"用户不配置 feed URL"承诺。' >&2
  return 1
fi


echo
echo "验证通过。摘要：$LOG_DIR/summary.md"
