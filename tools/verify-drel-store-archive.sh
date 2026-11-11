#!/usr/bin/env bash
# Verifies the final Drel Store archive surface, not just source-level policy.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE_PATH="${1:-/tmp/wbk-release-gate/Drel.xcarchive}"
APP_PATH="$ARCHIVE_PATH/Products/Applications/Drel.app"
PLIST="$APP_PATH/Info.plist"
BINARY="$APP_PATH/Drel"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

[[ -d "$APP_PATH" ]] || fail "app bundle not found at $APP_PATH"
[[ -f "$PLIST" ]] || fail "Info.plist not found at $PLIST"
[[ -f "$BINARY" ]] || fail "app binary not found at $BINARY"

value() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null || true
}

[[ "$(value CFBundleIdentifier)" == "com.webbridgekit.superapp" ]] || fail "unexpected bundle identifier"
[[ "$(value CFBundleDisplayName)" == "Drel" ]] || fail "unexpected display name"
# WebBridgeKit remains linked as the reusable SDK. Apple scans its public
# Contacts/Bluetooth/Speech/audio implementation even though the Drel Store
# runtime is compile-time container-only and cannot expose the bridge to a
# remote page. Builds 141-143 were rejected with ITMS-90683 for the missing
# NSBluetoothAlwaysUsageDescription, so it must stay present.
for key in \
    NSCameraUsageDescription \
    NSBluetoothAlwaysUsageDescription \
    NSContactsUsageDescription \
    NSMicrophoneUsageDescription \
    NSSpeechRecognitionUsageDescription; do
    [[ -n "$(value "$key")" ]] || fail "required SDK privacy prompt missing: $key"
done

for key in \
    NSFaceIDUsageDescription \
    NSLocationWhenInUseUsageDescription \
    NSMotionUsageDescription \
    NSPhotoLibraryUsageDescription; do
    [[ -z "$(value "$key")" ]] || fail "Bridge-only privacy prompt leaked: $key"
done

bash "$ROOT/tools/privacy-surface-check.sh" "$APP_PATH" \
    || fail "shipped binary needs a purpose string that the Store build strips"

[[ -z "$(value NSAppTransportSecurity:NSAllowsArbitraryLoads)" ]] || fail "arbitrary HTTP loading leaked"

for marker in 'wbk.legacy-infra.example.invalid' 'ae8fcb.legacy-infra.example.invalid'; do
    ! strings -a "$BINARY" | grep -qF -- "$marker" || fail "legacy source-host marker leaked: $marker"
done

for marker in PWAPermissionCenterViewController WebOriginGrantsView '权限与原生能力' '网页授权管理'; do
    ! strings -a "$BINARY" | grep -qF -- "$marker" || fail "Bridge permission UI marker leaked: $marker"
done

echo "PASS: Drel Store archive identity, required SDK privacy prompts, and Bridge UI are clean."
