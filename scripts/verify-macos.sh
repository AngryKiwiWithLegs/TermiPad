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

echo
echo "验证通过。摘要：$LOG_DIR/summary.md"
