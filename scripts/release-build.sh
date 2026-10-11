#!/usr/bin/env bash
# Skeleton of the TermiPad external distribution build script.
#
# Status: skeleton in place (2026-08-29, zcode takeover commit 3.1). **The full flow cannot be run yet** —
# it depends on an Apple Developer Program account, a Developer ID Application certificate, and an App Store
# Connect API key (for notarytool). Without these, the signing / notarization / staple steps
# explicitly degrade to "print what would be executed" instead of really running.
#
# Usage: ./scripts/release-build.sh [--skip-notarization] [--skip-staple]
#                                [--output-dir <dir>] [--dmg]
#
# Environment variables (required to run the full flow):
#   DEVELOPER_ID_APPLICATION   full signing identity, e.g. "Developer ID Application: Foo (TEAMID)"
#   NOTARYTOOL_KEYCHAIN_PROFILE name of the App Store Connect API key profile stored in the keychain
#                              (see `xcrun notarytool store-credentials`)
#   BUNDLE_ID                  TermiPad Bundle Identifier (default com.termipad.app)
#   APPLE_TEAM_ID              10-character Apple Team ID
#
# Current project status (post-takeover §6.5):
#   - Apple Developer Program account: ❌ not available
#   - Developer ID certificate: ❌ not available
#   - notarytool keychain profile: ❌ not available
#   - Notarization service reachability: ⚠️ can only be checked after signing in with an Apple ID
#
# This script is the **first step** of the release pipeline — afterwards ./scripts/verify-release-artifact.sh
# audits the integrity of the signed .app and writes the evidence to release-evidence/<timestamp>/.

set -euo pipefail

# ---- Argument parsing ----
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
        *) echo "Unknown argument: $1" >&2; exit 64 ;;
    esac
done

# ---- Probe external conditions ----
HAVE_DEV_ID=0
HAVE_NOTARY_PROFILE=0

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    HAVE_DEV_ID=1
fi
if [[ -n "${NOTARYTOOL_KEYCHAIN_PROFILE:-}" ]]; then
    HAVE_NOTARY_PROFILE=1
fi

# ---- Pre-checks ----
if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "xcodebuild is missing. Install the full Xcode." >&2
    exit 69
fi
if ! command -v xcrun >/dev/null 2>&1; then
    echo "xcrun is missing. Install the full Xcode." >&2
    exit 69
fi
if ! command -v codesign >/dev/null 2>&1; then
    echo "codesign is missing. Install the full Xcode." >&2
    exit 69
fi

mkdir -p "$OUTPUT_DIR"
SUMMARY_FILE="$OUTPUT_DIR/summary.md"
ARCHIVE_PATH="$OUTPUT_DIR/TermiPad.xcarchive"
APP_PATH="$ARCHIVE_PATH/Products/Applications/TermiPad.app"
DMG_PATH="$OUTPUT_DIR/TermiPad.dmg"
ENTITLEMENTS_FILE="$OUTPUT_DIR/TermiPad.entitlements"

# ---- Write the entitlements placeholder (required by Hardened Runtime) ----
cat > "$ENTITLEMENTS_FILE" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Apple Events are used for Terminal/iTerm/Warp launch commands; the user authorizes on first use -->
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <!-- Add sandbox entries if needed; not enabled for now (during development ENABLE_HARDENED_RUNTIME: NO) -->
</dict>
</plist>
PLIST

# ---- 1) Archive ----
echo "==== Step 1: xcodebuild archive ====" | tee -a "$SUMMARY_FILE"
echo "  archive path: $ARCHIVE_PATH" | tee -a "$SUMMARY_FILE"
if [[ ! -d TermiPad.xcodeproj ]]; then
    echo "  TermiPad.xcodeproj not found in the current directory — run xcodegen generate first" >&2 | tee -a "$SUMMARY_FILE"
    xcodegen generate 2>&1 | tee -a "$SUMMARY_FILE"
fi

xcodebuild \
    -project TermiPad.xcodeproj \
    -scheme TermiPad \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    clean archive 2>&1 | tee -a "$SUMMARY_FILE"
echo "  archive done" | tee -a "$SUMMARY_FILE"

# ---- 2) Developer ID signing (gated on environment variables) ----
echo "==== Step 2: codesign with Developer ID ====" | tee -a "$SUMMARY_FILE"
if [[ $HAVE_DEV_ID -eq 0 ]]; then
    echo "  ⚠️ DEVELOPER_ID_APPLICATION is not set — signing degrades to ad hoc (not distributable)" | tee -a "$SUMMARY_FILE"
    echo "  The signing identity actually used will be: -" | tee -a "$SUMMARY_FILE"
    SIGN_ARGS=(--force --deep --sign - --entitlements "$ENTITLEMENTS_FILE" --timestamp=none)
else
    echo "  Signing identity: $DEVELOPER_ID_APPLICATION" | tee -a "$SUMMARY_FILE"
    SIGN_ARGS=(--force --deep --sign "$DEVELOPER_ID_APPLICATION" --entitlements "$ENTITLEMENTS_FILE" --timestamp)
fi

codesign "${SIGN_ARGS[@]}" "$APP_PATH" 2>&1 | tee -a "$SUMMARY_FILE"
codesign --verify --deep --strict --verbose=4 "$APP_PATH" 2>&1 | tee -a "$SUMMARY_FILE"
echo "  Signing done + verification passed" | tee -a "$SUMMARY_FILE"

# ---- 3) DMG packaging (optional) ----
if [[ $MAKE_DMG -eq 1 ]]; then
    echo "==== Step 3: DMG packaging ====" | tee -a "$SUMMARY_FILE"
    # Simple read-only DMG template (project maintainers can change the volume name / icon)
    VOLUME_NAME="TermiPad ${BUNDLE_SHORT_VERSION_STRING:-dev}"
    if [[ -f "$APP_PATH/Contents/Info.plist" ]]; then
        VOLUME_NAME="TermiPad $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo dev)"
    fi
    hdiutil create -ov -format UDZO -fs HFS+ -srcfolder "$APP_PATH" -volname "$VOLUME_NAME" "$DMG_PATH" 2>&1 | tee -a "$SUMMARY_FILE"
    echo "  DMG: $DMG_PATH" | tee -a "$SUMMARY_FILE"
fi

# ---- 4) notarytool notarization (gated on the profile) ----
if [[ $SKIP_NOTARIZATION -eq 1 ]]; then
    echo "==== Step 4: notarization SKIPPED (--skip-notarization) ====" | tee -a "$SUMMARY_FILE"
elif [[ $HAVE_NOTARY_PROFILE -eq 0 ]]; then
    echo "==== Step 4: ⚠️ NOTARYTOOL_KEYCHAIN_PROFILE is not set — notarization degrades to printing ====" | tee -a "$SUMMARY_FILE"
    echo "  Would actually run: xcrun notarytool submit <DMG or ZIP> --keychain-profile <name> --wait" | tee -a "$SUMMARY_FILE"
    echo "  See docs/release-build.md for the full notarization flow" | tee -a "$SUMMARY_FILE"
else
    echo "==== Step 4: notarytool submit + wait ====" | tee -a "$SUMMARY_FILE"
    SUBMIT_TARGET="$APP_PATH"
    [[ $MAKE_DMG -eq 1 ]] && SUBMIT_TARGET="$DMG_PATH"
    xcrun notarytool submit "$SUBMIT_TARGET" --keychain-profile "$NOTARYTOOL_KEYCHAIN_PROFILE" --wait 2>&1 | tee -a "$SUMMARY_FILE"
    echo "  Notarization done" | tee -a "$SUMMARY_FILE"
fi

# ---- 5) staple (gated on the notarization result) ----
if [[ $SKIP_STAPLE -eq 1 ]]; then
    echo "==== Step 5: staple SKIPPED (--skip-staple) ====" | tee -a "$SUMMARY_FILE"
elif [[ $HAVE_NOTARY_PROFILE -eq 0 || $HAVE_DEV_ID -eq 0 ]]; then
    echo "==== Step 5: ⚠️ prerequisites not met — staple degrades to printing ====" | tee -a "$SUMMARY_FILE"
    echo "  Would actually run: xcrun stapler staple <APP_PATH>" | tee -a "$SUMMARY_FILE"
else
    echo "==== Step 5: xcrun stapler staple ====" | tee -a "$SUMMARY_FILE"
    xcrun stapler staple "$APP_PATH" 2>&1 | tee -a "$SUMMARY_FILE"
    echo "  staple done" | tee -a "$SUMMARY_FILE"
fi

# ---- 6) Self-check: run verify-release-artifact.sh ----
echo "==== Step 6: run the verify-release-artifact.sh self-check ====" | tee -a "$SUMMARY_FILE"
if [[ -x ./scripts/verify-release-artifact.sh ]]; then
    EXTRA_FLAG=""
    if [[ $HAVE_DEV_ID -eq 1 && $HAVE_NOTARY_PROFILE -eq 1 && $SKIP_NOTARIZATION -eq 0 && $SKIP_STAPLE -eq 0 ]]; then
        EXTRA_FLAG="--require-notarization"
    fi
    ./scripts/verify-release-artifact.sh "$APP_PATH" "$OUTPUT_DIR" $EXTRA_FLAG 2>&1 | tee -a "$SUMMARY_FILE" || echo "  ⚠️ The self-check did not pass — but the skeleton pipeline completed; see $SUMMARY_FILE" | tee -a "$SUMMARY_FILE"
else
    echo "  ./scripts/verify-release-artifact.sh not found — skipping the self-check" | tee -a "$SUMMARY_FILE"
fi

echo
echo "Skeleton pipeline done: $OUTPUT_DIR"
echo "  archive: $ARCHIVE_PATH"
echo "  app:     $APP_PATH"
[[ $MAKE_DMG -eq 1 ]] && echo "  dmg:     $DMG_PATH"
echo "  summary: $SUMMARY_FILE"
echo
echo "Next steps:"
echo "  1. Enroll in the Apple Developer Program (if you have not yet)"
echo "  2. Generate a Developer ID Application certificate and export it to the login keychain"
echo "  3. Store the notary profile with xcrun notarytool store-credentials"
echo "  4. Set the environment variables DEVELOPER_ID_APPLICATION / NOTARYTOOL_KEYCHAIN_PROFILE and run again"
