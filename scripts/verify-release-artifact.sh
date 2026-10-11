#!/usr/bin/env bash
# Verifies an archived, Developer ID-signed macOS .app; this script performs no signing, notarization, or network upload.
# Usage: ./scripts/verify-release-artifact.sh /path/to/TermiPad.app [evidence-directory] [--require-notarization]

set -euo pipefail

APP_PATH="${1:-}"
EVIDENCE_DIRECTORY="${2:-}"
REQUIRE_NOTARIZATION="${3:-}"

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" || "${APP_PATH##*.}" != "app" ]]; then
    echo "Usage: $0 /path/to/TermiPad.app [evidence-directory] [--require-notarization]" >&2
    exit 64
fi

if [[ -z "$EVIDENCE_DIRECTORY" || "$EVIDENCE_DIRECTORY" == "--require-notarization" ]]; then
    EVIDENCE_DIRECTORY="$(pwd)/release-evidence/$(date +%Y%m%d-%H%M%S)"
    if [[ "$2" == "--require-notarization" ]]; then
        REQUIRE_NOTARIZATION="$2"
    fi
fi

if [[ -n "$REQUIRE_NOTARIZATION" && "$REQUIRE_NOTARIZATION" != "--require-notarization" ]]; then
    echo "Unknown option: $REQUIRE_NOTARIZATION" >&2
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
        record "PASS" "$name" "Log: $(basename "$log_file")"
    else
        record "FAIL" "$name" "Check failed; log: $(basename "$log_file")"
    fi
}

cat > "$SUMMARY_FILE" <<EOF
# TermiPad release artifact check summary

- **Artifact:** \`$APP_PATH\`
- **Checked at:** \`$(date -u +%Y-%m-%dT%H:%M:%SZ)\`
- **Notarization required:** \`$([[ "$REQUIRE_NOTARIZATION" == "--require-notarization" ]] && echo yes || echo no)\`

| Check | Result | Evidence |
|---|---|---|
EOF

run_check "codesign-verify" codesign --verify --deep --strict --verbose=4 "$APP_PATH"

if codesign -dvvv "$APP_PATH" >"$SIGNATURE_FILE" 2>&1; then
    record "PASS" "signature-details" "Log: $(basename "$SIGNATURE_FILE")"
else
    record "FAIL" "signature-details" "Could not read the signature details"
fi

if grep -q '^Authority=Developer ID Application:' "$SIGNATURE_FILE"; then
    record "PASS" "developer-id" "Developer ID Application Authority detected"
else
    record "FAIL" "developer-id" "No Developer ID Application Authority detected; ad hoc or development signatures cannot be used for external distribution"
fi

if grep -q 'runtime' "$SIGNATURE_FILE"; then
    record "PASS" "hardened-runtime" "Signature flags include runtime"
else
    record "FAIL" "hardened-runtime" "Signature flags do not include runtime"
fi

if codesign -d --entitlements :- "$APP_PATH" >"$ENTITLEMENTS_FILE" 2>"$EVIDENCE_DIRECTORY/entitlements.stderr.log"; then
    get_task_allow="$(plutil -extract com.apple.security.get-task-allow raw -o - "$ENTITLEMENTS_FILE" 2>/dev/null || true)"
    if [[ "$get_task_allow" == "true" || "$get_task_allow" == "1" ]]; then
        record "FAIL" "get-task-allow" "A release artifact must not contain com.apple.security.get-task-allow=true"
    else
        record "PASS" "get-task-allow" "No enabled debug entitlement detected"
    fi
else
    record "FAIL" "entitlements" "Could not export the signing entitlements"
fi

if [[ "$REQUIRE_NOTARIZATION" == "--require-notarization" ]]; then
    run_check "gatekeeper-assessment" spctl --assess --type execute --verbose=4 "$APP_PATH"
    run_check "stapler-validate" xcrun stapler validate "$APP_PATH"
fi

printf '\n## Result\n\n- Passed: %s\n- Failed: %s\n' "$pass_count" "$fail_count" >> "$SUMMARY_FILE"

if [[ "$fail_count" -gt 0 ]]; then
    printf '\n**RESULT: FAILED**\n' >> "$SUMMARY_FILE"
    cat "$SUMMARY_FILE"
    exit 1
fi

printf '\n**RESULT: PASSED**\n' >> "$SUMMARY_FILE"
cat "$SUMMARY_FILE"
