#!/usr/bin/env bash
# TermiPad's local macOS verification entry point.
# Runs by default: SwiftPM manifest validation, unit tests, XcodeGen generation, xcodebuild build, UI smoke tests.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SKIP_UI=0
if [[ "${1:-}" == "--skip-ui" ]]; then
  SKIP_UI=1
elif [[ $# -gt 0 ]]; then
  echo "Usage: $0 [--skip-ui]" >&2
  exit 64
fi

for command in swift xcodebuild xcodegen; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "$command is missing. Install the full Xcode and run: brew install xcodegen" >&2
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
    echo "[PASS] ${name}"
  else
    FAILED_STEP="${name}"
    echo "[FAIL] ${name}; full log: ${LOG_DIR}/${name}.log" >&2
    return 1
  fi
}

write_summary() {
  {
    echo "# TermiPad local verification summary"
    echo
    echo "- Time: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "- Commit: $(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
    echo "- Log directory: $LOG_DIR"
    echo
    echo "## Result"
    if [[ -n "$FAILED_STEP" ]]; then
      echo "- **Failed step: $FAILED_STEP**"
    else
      echo "- **All requested steps passed.**"
    fi
    echo
    echo "## Key diagnostics"
    echo '```text'
    grep -E -i '(^|[[:space:]])(error|warning|fatal error):|BUILD FAILED|TEST FAILED|Assertion' "$LOG_DIR"/*.log 2>/dev/null || true
    echo '```'
  } > "$LOG_DIR/summary.md"
}
trap write_summary EXIT

swift_source_guard() {
  if grep -RInF '\(AppCopy.text(\"' Sources; then
    echo 'Detected an AppCopy call that was wrongly escaped inside a Swift string interpolation.' >&2
    return 1
  fi
  if grep -RInF 'case (.available, .notInspectable,' Sources; then
    echo 'Detected a ToolHealth two-element tuple wrongly written as a three-element case.' >&2
    return 1
  fi
  if grep -RInE 'summary\.(toolsAdded|toolsUpdated|candidatesAdded|candidatesUpdated)' Sources Tests UITests; then
    echo 'Detected deprecated BackupRestoreSummary field names.' >&2
    return 1
  fi
  if grep -REn 'TerminalLauncher|CommandTemplate|modelContext\.insert|TerminalTool\(|CandidateTool\(|Process\(|NSAppleScript|brew install|npm install|pip install|cargo install' Sources/DiscoveryPreview*.swift Sources/DiscoveryService.swift; then
    echo 'Detected Discovery Preview touching the command execution, install, or library write boundary.' >&2
    return 1
  fi
  if grep -RInF 'response.isIncomplete' Sources/DiscoveryService.swift; then
    echo 'Detected a wrong isIncomplete field reference in the GitHub search DTO.' >&2
    return 1
  fi
  local controlled_install_code environment_report_code
  controlled_install_code="$(sed '/^[[:space:]]*\/\//d' Sources/ControlledInstallPlan.swift)"
  environment_report_code="$(sed '/^[[:space:]]*\/\//d' Sources/EnvironmentReport.swift)"
  if printf '%s\n' "$controlled_install_code" | grep -En 'URLSession|Process\(|NSAppleScript|TerminalLauncher|modelContext\.insert|tap |cask |npm install|pip install|cargo install|brew upgrade|brew uninstall'; then
    echo 'Detected the controlled install catalog touching the network, in-app execution, third-party channels, or mutating package-manager commands.' >&2
    return 1
  fi
  if ! printf '%s\n' "$controlled_install_code" | grep -qF 'command: "brew install \(formula)"'; then
    echo 'The controlled install catalog is missing the fixed Homebrew core formula command template.' >&2
    return 1
  fi
  if printf '%s\n' "$environment_report_code" | grep -En 'URLSession|NSAppleScript|/bin/sh|modelContext\.insert|install|upgrade|uninstall|remove'; then
    echo 'Detected the environment report touching the network, a shell, persistence, or mutating operations.' >&2
    return 1
  fi
  if ! printf '%s\n' "$environment_report_code" | grep -qF 'task.arguments = ["--version"]'; then
    echo 'The environment report must be limited to the fixed --version argument.' >&2
    return 1
  fi
  if grep -En 'pathLookup \?\? executablePath\(for:\)|versionReader \?\? readVersion\(at:\)' Sources/EnvironmentReport.swift; then
    echo 'Detected a merged default-function-reference form in the environment report that Swift 6.3 cannot infer reliably.' >&2
    return 1
  fi
  if grep -nF 'TerminalLauncher.launch(command:' Sources/InstallEnvironmentView.swift | grep -vF 'TerminalLauncher.launch(command: plan.command'; then
    echo 'Install review may only hand static plan commands to the terminal the user chose.' >&2
    return 1
  fi
  local icon_code
  icon_code="$(sed '/^[[:space:]]*\/\//d' Sources/ToolIconView.swift Sources/ToolIconStore.swift)"
  if printf '%s\n' "$icon_code" | grep -En 'URLSession|AsyncImage|https?://|NSImage\(contentsOf: URL\(string:'; then
    echo 'Detected the local icon system trying to load network images or remote resources.' >&2
    return 1
  fi
  if ! printf '%s\n' "$icon_code" | grep -qF 'customIconFilename'; then
    echo 'The local icon system must keep the controlled-local-PNG-first field.' >&2
    return 1
  fi
  local task_policy_code
  task_policy_code="$(sed '/^[[:space:]]*\/\//d' Sources/TaskIntent.swift Sources/TaskIntentPolicy.swift Sources/TaskPolicyWorkbenchView.swift)"
  if printf '%s\n' "$task_policy_code" | grep -En 'URLSession|URLRequest|NWConnection|NWListener|WebSocket|NSAppleScript|TerminalLauncher|Process\(|forkpty|posix_openpt|/bin/sh|https?://|stdin|stdout|stderr'; then
    echo 'Detected the T0 task policy touching the network, terminal automation, process execution, PTY, or remote input/output boundary.' >&2
    return 1
  fi
  if ! printf '%s\n' "$task_policy_code" | grep -qF 'static let definitions'; then
    echo 'The T0 task policy must keep the fixed task catalog shipped with the app.' >&2
    return 1
  fi
  local task_execution_code
  task_execution_code="$(sed '/^[[:space:]]*\/\//d' Sources/TaskExecutionService.swift Sources/TaskIntent.swift Sources/TaskPolicyWorkbenchView.swift)"
  # M2b-2 (docs/m2b-remote-task-console-design.md §5.4/§7): controlled relaxation —
  # when the output visibility is ≥ restricted, T1 captures stdout/stderr with a Pipe into an in-memory only
  # ring buffer (32KB/400-line cap; the tail snippet is returned after redaction). The parts of the red line that do not change
  # stay locked down: no network, no terminal automation, no PTY, no shell, no arbitrary stdin.
  if printf '%s\n' "$task_execution_code" | grep -En 'URLSession|URLRequest|NWConnection|NWListener|WebSocket|NSAppleScript|TerminalLauncher|forkpty|posix_openpt|/bin/sh|https?://|stdin'; then
    echo 'Detected the T1 executor touching the network, terminal automation, PTY, shell, or process input boundary.' >&2
    return 1
  fi
  # Pipe is allowed in two places (M4-3 revision, docs/m4-interactive-session-design.md §2.2):
  # output capture (attachOutputCapture, visibility decision) + the interaction point stdin pipe
  # (opened only for tasks that declare interactionPoints). To prevent scattered abuse: count capped at 2.
  if [ "$(printf '%s\n' "$task_execution_code" | grep -cE 'Pipe\(\)')" -gt 2 ] \
    || ! printf '%s\n' "$task_execution_code" | grep -qF 'if capturesOutput {'; then
    echo 'T1 may use Pipe in only two places: output capture and the interaction point stdin.' >&2
    return 1
  fi
  if ! printf '%s\n' "$task_execution_code" | grep -qF 'process.standardInput = FileHandle.nullDevice'; then
    echo 'The T1 executor must use empty input.' >&2
    return 1
  fi
  if ! printf '%s\n' "$task_execution_code" | grep -qF 'process.standardOutput = FileHandle.nullDevice' || ! printf '%s\n' "$task_execution_code" | grep -qF 'process.standardError = FileHandle.nullDevice'; then
    echo 'The T1 executor must keep empty output at the minimal level (the nullDevice branch must not be removed).' >&2
    return 1
  fi
  if grep -RInE 'Process\(' Sources | grep -vE 'Sources/(EnvironmentReport|TaskExecutionService|TailnetTunnelService)\.swift'; then
    echo 'Detected a new process execution entry point outside T1 (for M2a only TailnetTunnelService may run the tailscale CLI).' >&2
    return 1
  fi
  # Backup and task domain isolation (track-protocol §4.5): Sources/BackupService.swift must not reference
  # any task entity — their fields (paths / nonce / exit codes / timestamps) contain locally sensitive information
  # and should never enter a portable JSON backup.
  local backup_code
  backup_code="$(sed '/^[[:space:]]*\/\//d' Sources/BackupService.swift)"
  if printf '%s\n' "$backup_code" | grep -En 'TaskIntent|TaskProjectScope|TaskReviewWindow|projectScopeID|reviewWindowID'; then
    echo 'Detected BackupService referencing task-domain entities — a backup never contains task history, project paths, or review windows.' >&2
    return 1
  fi
  # M0 mobile entry (track-protocol stage 4.1): the 6 fields never leave this Mac and never enter a JSON backup.
  # The fields are safe inside Sources/TerminalTool.swift (local data), but Sources/BackupService.swift
  # must not reference them anywhere — a reference means the field is on the serialization path.
  if printf '%s\n' "$backup_code" | grep -En 'mobileDisplayName|mobileDescription|showInMobileEntry|allowMobileLaunchRequest|mobileLocalConfirmPolicy|revokeMobilePermissionAt'; then
    echo 'Detected BackupService referencing M0 mobile entry fields — a backup does not contain the phone display name / description / switches.' >&2
    return 1
  fi
  # Update checks are read-only network (track-prototol user commitment: option A, notification-style).
  # UpdateCheckService must **not** trigger downloads, **not** write to ~/Applications, and
  # **not** start NSWorkspace.openApplication to auto-update the .app. Any "automatic download/replace"
  # commit would bypass the Mac Gatekeeper trust chain + introduce a supply-chain attack surface.
  local update_check_code
  update_check_code="$(sed '/^[[:space:]]*\/\//d' Sources/UpdateCheckService.swift)"
  if printf '%s\n' "$update_check_code" | grep -En 'NSWorkspace.shared.openApplication|FileManager.default.write|FileManager.default.copy|FileManager.default.move|/bin/sh -c |Process\(|NSAppleScript|TarExtractor|tempDirectory'; then
    echo 'Detected UpdateCheckService trying to automatically download/unpack/replace the .app — violates the project commitment to stay "notification-style".' >&2
    return 1
  fi
  if ! printf '%s\n' "$update_check_code" | grep -qF 'api.github.com/repos/AngryKiwiWithLegs/TermiPad'; then
    echo 'UpdateCheckService must point at the fixed AngryKiwiWithLegs/TermiPad releases endpoint' >&2
    echo 'and accept no runtime configuration — an attacker cannot change the endpoint to redirect to a malicious server.' >&2
    return 1
  fi
  if ! printf '%s\n' "$update_check_code" | grep -qF 'currentAppVersion'; then
    echo 'UpdateCheckService must read currentAppVersion from the bundle for version comparison —' >&2
    echo 'UserDefaults must not be used to configure an attacker-controlled version number.' >&2
    return 1
  fi

  mcp_code="$(sed '/^[[:space:]]*\/\//d' Sources/MCPStdIORuntime.swift Sources/TaskMCPBridge.swift Sources/TaskMCPSettings.swift Sources/TaskPolicyWorkbenchView.swift)"
  if printf '%s\n' "$mcp_code" | grep -En 'URLSession|URLRequest|NWConnection|NWListener|WebSocket|NSAppleScript|TerminalLauncher|forkpty|posix_openpt|/bin/sh|https?://|NSXPC|XPCListener|XPCSession|socket|Process\(|Pipe\('; then
    echo 'A network, XPC, process, terminal handoff, PTY, or output pipe entry point appeared in the local MCP directory.' >&2
    return 1
  fi
  if ! printf '%s\n' "$mcp_code" | grep -qF 'FileHandle.standardOutput.write(data)' || ! printf '%s\n' "$mcp_code" | grep -qE '"additionalProperties": false'; then
    echo 'Local MCP is missing stdio protocol output or the strict tool schema guard.' >&2
    return 1
  fi
  if grep -En 'ModelContainer|ModelContext|FetchDescriptor|TaskIntentPolicy' Sources/MCPStdIORuntime.swift; then
    echo 'The stdio MCP child process must not open or operate on the TermiPad SwiftData store directly.' >&2
    return 1
  fi
  # M0 mobile entry (track-protocol stage 4.1): the 6 fields never leave this Mac and never enter an MCP response.
  # The 8-field allowlist of LocalMCPTaskState (docs/task-result-minimal-spec.md §2.3) is fixed.
  if printf '%s\n' "$mcp_code" | grep -En 'mobileDisplayName|mobileDescription|showInMobileEntry|allowMobileLaunchRequest|mobileLocalConfirmPolicy|revokeMobilePermissionAt'; then
    echo 'Detected MCP referencing M0 mobile entry fields — the MCP response allowlist is fixed at 8 fields and contains no phone-side fields.' >&2
    return 1
  fi
  if ! grep -qF 'CFMessagePortCreateRemote' Sources/TaskMCPBridge.swift || ! grep -qF 'CFMessagePortCreateLocal' Sources/TaskMCPBridge.swift; then
    echo 'Local MCP must be bridged through the in-app CFMessagePort instead of letting the stdio child process compete for the store directly.' >&2
    return 1
  fi
  # M1 local network pairing core (feature/m1-local-network-pairing): pure cryptography + Keychain.
  # These two files must never contain network, process, or terminal automation entry points — network listening may only appear in
  # the future Sources/MobilePairingService.swift, fenced in by a dedicated guard.
  local mobile_pairing_core_code
  mobile_pairing_core_code="$(sed '/^[[:space:]]*\/\//d' Sources/MobilePairingCrypto.swift Sources/PairedDeviceStore.swift)"
  if printf '%s\n' "$mobile_pairing_core_code" | grep -En 'URLSession|URLRequest|NWConnection|NWListener|WebSocket|NSAppleScript|TerminalLauncher|Process\(|Pipe\(|forkpty|posix_openpt|/bin/sh|socket\('; then
    echo 'Detected the M1 pairing core touching the network, process, or terminal automation boundary — it must be pure cryptography + Keychain.' >&2
    return 1
  fi
  # M1 pairing protocol layer: allowlist + minimal payload + AEAD envelope + handshake state machine, likewise zero I/O.
  local mobile_pairing_protocol_code
  mobile_pairing_protocol_code="$(sed '/^[[:space:]]*\/\//d' Sources/MobilePairingProtocol.swift)"
  if printf '%s\n' "$mobile_pairing_protocol_code" | grep -En 'URLSession|URLRequest|NWConnection|NWListener|WebSocket|NSAppleScript|TerminalLauncher|Process\(|Pipe\(|forkpty|posix_openpt|/bin/sh|socket\('; then
    echo 'Detected the M1 pairing protocol layer touching the network, process, or terminal automation boundary — network listening is only allowed in MobilePairingService.swift.' >&2
    return 1
  fi
  # Global allowlist: across all of Sources, NWListener/NWConnection may only appear in
  # Sources/MobilePairingService.swift (M1 local network listener, off by default) and
  # Sources/TailnetTunnelService.swift (M2a loopback listener, off by default).
  if grep -RInE 'NWListener|NWConnection' Sources | grep -vE 'Sources/(MobilePairingService|TailnetTunnelService)\.swift'; then
    echo 'Detected a network listening entry point outside the M1/M2a listener files.' >&2
    return 1
  fi
  # M2a tunnel guard: the executable path literals of the tailscale CLI may only appear in
  # TailnetTunnelService.swift (fixed absolute path discipline); no other file may assemble the CLI.
  if grep -RIn 'bin/tailscale' Sources | grep -v 'Sources/TailnetTunnelService\.swift'; then
    echo 'Detected a tailscale CLI call outside TailnetTunnelService.' >&2
    return 1
  fi
  # M2a red line: Funnel (the public exposure entry point) is permanently disabled. Any occurrence of the literal fails verification.
  if grep -RInE '"funnel| funnel |--funnel' Sources; then
    echo 'Detected a reference to the funnel subcommand — public exposure red line, permanently forbidden.' >&2
    return 1
  fi
  # iOS companion app: NWBrowser may only appear under CompanionApp/; Sources/ must not use it.
  if grep -RInE 'NWBrowser' Sources; then
    echo 'Detected NWBrowser introduced on the Mac side — the browser belongs to the iOS companion app only.' >&2
    return 1
  fi
  # M2b defense line 1 (design §7) + M3 revision: LocalAuthentication's LAContext
  # is allowed in the iOS companion app and the Mac's RemoteAllowWindowSection (daily window authentication,
  # docs/m3-remote-allow-window-design.md §3.4) — it must not be introduced anywhere else.
  if grep -RInE 'import LocalAuthentication|LAContext' Sources \
    | grep -vE 'PreferencesView\.swift'; then
    echo 'Detected an out-of-bounds LocalAuthentication import (only CompanionApp and PreferencesView are allowed).' >&2
    return 1
  fi
  # Required in the iOS Info.plist: without NSLocalNetworkUsageDescription or NSBonjourServices, local discovery is silently killed.
  if ! grep -qF 'NSLocalNetworkUsageDescription' CompanionApp/Info.plist \
     || ! grep -qF '_termipad-m1._tcp' CompanionApp/Info.plist; then
    echo 'The iOS companion Info.plist must declare NSLocalNetworkUsageDescription and NSBonjourServices=_termipad-m1._tcp.' >&2
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
    echo "TermiPadUITests-Runner.app not found; see $LOG_DIR/ui-build-for-testing.log" >&2
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
      echo "UI failure attachments: $LOG_DIR/ui-attachments" >&2
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

# UpdateCheckService should not let the user configure a feed URL (that is a G6 gate hole: it lets social
# engineering lead a victim into entering https://evil.com/updates.json). PreferencesView
# should contain no updateFeedURL UserDefault, no URL input field, and no URL input path of any kind.
if grep -RnE 'updateFeedURL' Sources/PreferencesView.swift Sources/UpdateCheckService.swift 2>/dev/null; then
  echo 'Detected updateFeedURL — violates the G6 gate commitment "users do not configure a feed URL".' >&2
  return 1
fi


echo
echo "Verification passed. Summary: $LOG_DIR/summary.md"
