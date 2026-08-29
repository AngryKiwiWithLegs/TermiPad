#!/usr/bin/env bash
# TermiPad 外部分发构建脚本骨架。
#
# 状态：骨架就位（2026-08-29，zcode 接手 commit 3.1）。**当前不可执行完整流程**——
# 依赖 Apple Developer Program 账户、Developer ID Application 证书、App Store
# Connect API key (for notarytool)。没有这些时，签名 / 公证 / staple 步骤会
# 显式降级为"打印将要执行什么"而不是真跑。
#
# 用法：./scripts/release-build.sh [--skip-notarization] [--skip-staple]
#                                [--output-dir <dir>] [--dmg]
#
# 环境变量（必须提供才能跑完整流程）：
#   DEVELOPER_ID_APPLICATION   完整签名身份，如 "Developer ID Application: Foo (TEAMID)"
#   NOTARYTOOL_KEYCHAIN_PROFILE 钥匙串中存储的 App Store Connect API key profile 名
#                              （见 `xcrun notarytool store-credentials`）
#   BUNDLE_ID                  TermiPad Bundle Identifier（默认 com.termipad.app）
#   APPLE_TEAM_ID              10 字符 Apple Team ID
#
# 当前项目状态（post-takeover §6.5）：
#   - Apple Developer Program 账户: ❌ 未具备
#   - Developer ID 证书: ❌ 未具备
#   - notarytool keychain profile: ❌ 未具备
#   - 公证服务可达性: ⚠️ 需要登录 Apple ID 后才能验
#
# 该脚本是 release pipeline 的**第一步**——后续 ./scripts/verify-release-artifact.sh
# 审计已签名的 .app 完整性，证据写入 release-evidence/<时间戳>/。

set -euo pipefail

# ---- 参数解析 ----
SKIP_NOTARIZATION=0
SKIP_STAPLE=0
OUTPUT_DIR="$(pwd)/release-build/$(date +%Y%m%d-%H%M%S)"
MAKE_DMG=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-notarization) SKIP_NOTARIZATION=1; shift ;;
        --skip-staple)        SKIP_STAPLE=1; shift ;;
        --output-dir)         OUTPUT_DIR="$2"; shift 2 ;;
        --dmg)                MAKE_DMG=1; shift ;;
        -h|--help)
            sed -n '2,30p' "$0"
            exit 0
            ;;
        *) echo "未知参数：$1" >&2; exit 64 ;;
    esac
done

# ---- 探测外部条件 ----
HAVE_DEV_ID=0
HAVE_NOTARY_PROFILE=0

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    HAVE_DEV_ID=1
fi
if [[ -n "${NOTARYTOOL_KEYCHAIN_PROFILE:-}" ]]; then
    HAVE_NOTARY_PROFILE=1
fi

# ---- 前置检查 ----
if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "缺少 xcodebuild。请安装完整 Xcode。" >&2
    exit 69
fi
if ! command -v xcrun >/dev/null 2>&1; then
    echo "缺少 xcrun。请安装完整 Xcode。" >&2
    exit 69
fi
if ! command -v codesign >/dev/null 2>&1; then
    echo "缺少 codesign。请安装完整 Xcode。" >&2
    exit 69
fi

mkdir -p "$OUTPUT_DIR"
SUMMARY_FILE="$OUTPUT_DIR/summary.md"
ARCHIVE_PATH="$OUTPUT_DIR/TermiPad.xcarchive"
APP_PATH="$ARCHIVE_PATH/Products/Applications/TermiPad.app"
DMG_PATH="$OUTPUT_DIR/TermiPad.dmg"
ENTITLEMENTS_FILE="$OUTPUT_DIR/TermiPad.entitlements"

# ---- 写入 entitlements 占位符（Hardened Runtime 必需） ----
cat > "$ENTITLEMENTS_FILE" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Apple Events 用于 Terminal/iTerm/Warp 启动命令；用户首次会授权 -->
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <!-- 必要的话加 sandbox 入口；暂不启用（开发期 ENABLE_HARDENED_RUNTIME: NO）-->
</dict>
</plist>
PLIST

# ---- 1) Archive ----
echo "==== Step 1: xcodebuild archive ====" | tee -a "$SUMMARY_FILE"
echo "  archive path: $ARCHIVE_PATH" | tee -a "$SUMMARY_FILE"
if [[ ! -d TermiPad.xcodeproj ]]; then
    echo "  当前目录未找到 TermiPad.xcodeproj——先跑 xcodegen generate" >&2 | tee -a "$SUMMARY_FILE"
    xcodegen generate 2>&1 | tee -a "$SUMMARY_FILE"
fi

xcodebuild \
    -project TermiPad.xcodeproj \
    -scheme TermiPad \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    clean archive 2>&1 | tee -a "$SUMMARY_FILE"
echo "  archive 完成" | tee -a "$SUMMARY_FILE"

# ---- 2) Developer ID 签名（gate on 环境变量）----
echo "==== Step 2: codesign with Developer ID ====" | tee -a "$SUMMARY_FILE"
if [[ $HAVE_DEV_ID -eq 0 ]]; then
    echo "  ⚠️ DEVELOPER_ID_APPLICATION 未设置——签名降级为 ad hoc（不可分发）" | tee -a "$SUMMARY_FILE"
    echo "  实际签名身份将使用： -" | tee -a "$SUMMARY_FILE"
    SIGN_ARGS=(--force --deep --sign - --entitlements "$ENTITLEMENTS_FILE" --timestamp=none)
else
    echo "  签名身份：$DEVELOPER_ID_APPLICATION" | tee -a "$SUMMARY_FILE"
    SIGN_ARGS=(--force --deep --sign "$DEVELOPER_ID_APPLICATION" --entitlements "$ENTITLEMENTS_FILE" --timestamp)
fi

codesign "${SIGN_ARGS[@]}" "$APP_PATH" 2>&1 | tee -a "$SUMMARY_FILE"
codesign --verify --deep --strict --verbose=4 "$APP_PATH" 2>&1 | tee -a "$SUMMARY_FILE"
echo "  签名完成 + 校验通过" | tee -a "$SUMMARY_FILE"

# ---- 3) DMG 打包（可选）----
if [[ $MAKE_DMG -eq 1 ]]; then
    echo "==== Step 3: DMG 打包 ====" | tee -a "$SUMMARY_FILE"
    # 简易 read-only DMG 模板（项目维护者可改 volume name / icon）
    VOLUME_NAME="TermiPad ${BUNDLE_SHORT_VERSION_STRING:-dev}"
    if [[ -f "$APP_PATH/Contents/Info.plist" ]]; then
        VOLUME_NAME="TermiPad $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo dev)"
    fi
    hdiutil create -ov -format UDZO -fs HFS+ -srcfolder "$APP_PATH" -volname "$VOLUME_NAME" "$DMG_PATH" 2>&1 | tee -a "$SUMMARY_FILE"
    echo "  DMG: $DMG_PATH" | tee -a "$SUMMARY_FILE"
fi

# ---- 4) notarytool 公证（gate on profile）----
if [[ $SKIP_NOTARIZATION -eq 1 ]]; then
    echo "==== Step 4: 公证 SKIPPED (--skip-notarization) ====" | tee -a "$SUMMARY_FILE"
elif [[ $HAVE_NOTARY_PROFILE -eq 0 ]]; then
    echo "==== Step 4: ⚠️ NOTARYTOOL_KEYCHAIN_PROFILE 未设置——公证降级为打印 ====" | tee -a "$SUMMARY_FILE"
    echo "  实际将执行： xcrun notarytool submit <DMG 或 ZIP> --keychain-profile <name> --wait" | tee -a "$SUMMARY_FILE"
    echo "  完整公证流程见 docs/release-build.md" | tee -a "$SUMMARY_FILE"
else
    echo "==== Step 4: notarytool submit + wait ====" | tee -a "$SUMMARY_FILE"
    SUBMIT_TARGET="$APP_PATH"
    [[ $MAKE_DMG -eq 1 ]] && SUBMIT_TARGET="$DMG_PATH"
    xcrun notarytool submit "$SUBMIT_TARGET" --keychain-profile "$NOTARYTOOL_KEYCHAIN_PROFILE" --wait 2>&1 | tee -a "$SUMMARY_FILE"
    echo "  公证完成" | tee -a "$SUMMARY_FILE"
fi

# ---- 5) staple（gate on 公证结果）----
if [[ $SKIP_STAPLE -eq 1 ]]; then
    echo "==== Step 5: staple SKIPPED (--skip-staple) ====" | tee -a "$SUMMARY_FILE"
elif [[ $HAVE_NOTARY_PROFILE -eq 0 || $HAVE_DEV_ID -eq 0 ]]; then
    echo "==== Step 5: ⚠️ 前置条件不足——staple 降级为打印 ====" | tee -a "$SUMMARY_FILE"
    echo "  实际将执行： xcrun stapler staple <APP_PATH>" | tee -a "$SUMMARY_FILE"
else
    echo "==== Step 5: xcrun stapler staple ====" | tee -a "$SUMMARY_FILE"
    xcrun stapler staple "$APP_PATH" 2>&1 | tee -a "$SUMMARY_FILE"
    echo "  staple 完成" | tee -a "$SUMMARY_FILE"
fi

# ---- 6) 自检：跑 verify-release-artifact.sh ----
echo "==== Step 6: 跑 verify-release-artifact.sh 自检 ====" | tee -a "$SUMMARY_FILE"
if [[ -x ./scripts/verify-release-artifact.sh ]]; then
    EXTRA_FLAG=""
    if [[ $HAVE_DEV_ID -eq 1 && $HAVE_NOTARY_PROFILE -eq 1 && $SKIP_NOTARIZATION -eq 0 && $SKIP_STAPLE -eq 0 ]]; then
        EXTRA_FLAG="--require-notarization"
    fi
    ./scripts/verify-release-artifact.sh "$APP_PATH" "$OUTPUT_DIR" $EXTRA_FLAG 2>&1 | tee -a "$SUMMARY_FILE" || echo "  ⚠️ 自检未通过——但骨架 pipeline 已完成；详见 $SUMMARY_FILE" | tee -a "$SUMMARY_FILE"
else
    echo "  未找到 ./scripts/verify-release-artifact.sh——跳过自检" | tee -a "$SUMMARY_FILE"
fi

echo
echo "骨架 pipeline 完成：$OUTPUT_DIR"
echo "  archive: $ARCHIVE_PATH"
echo "  app:     $APP_PATH"
[[ $MAKE_DMG -eq 1 ]] && echo "  dmg:     $DMG_PATH"
echo "  summary: $SUMMARY_FILE"
echo
echo "下一步："
echo "  1. 注册 Apple Developer Program（如果还没）"
echo "  2. 生成 Developer ID Application 证书并 export 到 login keychain"
echo "  3. xcrun notarytool store-credentials 存 notary profile"
echo "  4. 设置环境变量 DEVELOPER_ID_APPLICATION / NOTARYTOOL_KEYCHAIN_PROFILE 重跑"
