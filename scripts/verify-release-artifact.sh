#!/usr/bin/env bash
# 验证已归档、Developer ID 签名的 macOS .app；本脚本不执行签名、公证或网络上传。
# 用法：./scripts/verify-release-artifact.sh /path/to/TermiPad.app [evidence-directory] [--require-notarization]

set -euo pipefail

APP_PATH="${1:-}"
EVIDENCE_DIRECTORY="${2:-}"
REQUIRE_NOTARIZATION="${3:-}"

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" || "${APP_PATH##*.}" != "app" ]]; then
    echo "用法：$0 /path/to/TermiPad.app [evidence-directory] [--require-notarization]" >&2
    exit 64
fi

if [[ -z "$EVIDENCE_DIRECTORY" || "$EVIDENCE_DIRECTORY" == "--require-notarization" ]]; then
    EVIDENCE_DIRECTORY="$(pwd)/release-evidence/$(date +%Y%m%d-%H%M%S)"
    if [[ "$2" == "--require-notarization" ]]; then
        REQUIRE_NOTARIZATION="$2"
    fi
fi

if [[ -n "$REQUIRE_NOTARIZATION" && "$REQUIRE_NOTARIZATION" != "--require-notarization" ]]; then
    echo "未知选项：$REQUIRE_NOTARIZATION" >&2
    exit 64
fi

mkdir -p "$EVIDENCE_DIRECTORY"
SUMMARY_FILE="$EVIDENCE_DIRECTORY/summary.md"
SIGNATURE_FILE="$EVIDENCE_DIRECTORY/codesign-details.txt"
ENTITLEMENTS_FILE="$EVIDENCE_DIRECTORY/entitlements.plist"

pass_count=0
fail_count=0

record() {
    local result="$1"
    local name="$2"
    local detail="$3"
    printf '| %s | %s | %s |\n' "$name" "$result" "$detail" >> "$SUMMARY_FILE"
    if [[ "$result" == "PASS" ]]; then
        pass_count=$((pass_count + 1))
    else
        fail_count=$((fail_count + 1))
    fi
}

run_check() {
    local name="$1"
    shift
    local log_file="$EVIDENCE_DIRECTORY/${name}.log"
    if "$@" >"$log_file" 2>&1; then
        record "PASS" "$name" "日志：$(basename "$log_file")"
    else
        record "FAIL" "$name" "检查失败；日志：$(basename "$log_file")"
    fi
}

cat > "$SUMMARY_FILE" <<EOF
# TermiPad 发行工件检查摘要

- **工件：** \`$APP_PATH\`
- **检查时间：** \`$(date -u +%Y-%m-%dT%H:%M:%SZ)\`
- **要求公证：** \`$([[ "$REQUIRE_NOTARIZATION" == "--require-notarization" ]] && echo yes || echo no)\`

| 检查项 | 结果 | 证据 |
|---|---|---|
EOF

run_check "codesign-verify" codesign --verify --deep --strict --verbose=4 "$APP_PATH"

if codesign -dvvv "$APP_PATH" >"$SIGNATURE_FILE" 2>&1; then
    record "PASS" "signature-details" "日志：$(basename "$SIGNATURE_FILE")"
else
    record "FAIL" "signature-details" "无法读取签名详情"
fi

if grep -q '^Authority=Developer ID Application:' "$SIGNATURE_FILE"; then
    record "PASS" "developer-id" "检测到 Developer ID Application Authority"
else
    record "FAIL" "developer-id" "未检测到 Developer ID Application Authority；ad hoc 或开发签名不能用于外部分发"
fi

if grep -q 'runtime' "$SIGNATURE_FILE"; then
    record "PASS" "hardened-runtime" "签名 flags 包含 runtime"
else
    record "FAIL" "hardened-runtime" "签名 flags 未包含 runtime"
fi

if codesign -d --entitlements :- "$APP_PATH" >"$ENTITLEMENTS_FILE" 2>"$EVIDENCE_DIRECTORY/entitlements.stderr.log"; then
    get_task_allow="$(plutil -extract com.apple.security.get-task-allow raw -o - "$ENTITLEMENTS_FILE" 2>/dev/null || true)"
    if [[ "$get_task_allow" == "true" || "$get_task_allow" == "1" ]]; then
        record "FAIL" "get-task-allow" "发行工件不得包含 com.apple.security.get-task-allow=true"
    else
        record "PASS" "get-task-allow" "未检测到启用的调试 entitlement"
    fi
else
    record "FAIL" "entitlements" "无法导出签名 entitlement"
fi

if [[ "$REQUIRE_NOTARIZATION" == "--require-notarization" ]]; then
    run_check "gatekeeper-assessment" spctl --assess --type execute --verbose=4 "$APP_PATH"
    run_check "stapler-validate" xcrun stapler validate "$APP_PATH"
fi

printf '\n## 结果\n\n- 通过：%s\n- 失败：%s\n' "$pass_count" "$fail_count" >> "$SUMMARY_FILE"

if [[ "$fail_count" -gt 0 ]]; then
    printf '\n**RESULT: FAILED**\n' >> "$SUMMARY_FILE"
    cat "$SUMMARY_FILE"
    exit 1
fi

printf '\n**RESULT: PASSED**\n' >> "$SUMMARY_FILE"
cat "$SUMMARY_FILE"
