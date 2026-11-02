#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE_PATH="${1:-/tmp/wbk-v2-runtime-release/Drel-1.5.0-90.xcarchive}"
EXPECTED_BUILD="${DREL_V2_EXPECTED_BUILD:-90}"
EXPECTED_VERSION="${DREL_V2_EXPECTED_VERSION:-1.5.1}"
SIGNING_MODE="${DREL_V2_ARCHIVE_SIGNING:-distribution}"
APP_PATH="${DREL_V2_EXPORTED_APP_PATH:-$ARCHIVE_PATH/Products/Applications/Drel.app}"
PLIST="$APP_PATH/Info.plist"

fail() { echo "FAIL: $*" >&2; exit 1; }
value() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null || true; }

[[ -d "$APP_PATH" ]] || fail "Drel.app missing from archive"
[[ "$(value CFBundleIdentifier)" == "com.webbridgekit.superapp" ]] || fail "unexpected bundle identifier"
[[ "$(value CFBundleShortVersionString)" == "$EXPECTED_VERSION" ]] || fail "archive is not version $EXPECTED_VERSION"
[[ "$(value CFBundleVersion)" == "$EXPECTED_BUILD" ]] || fail "archive is not build $EXPECTED_BUILD"
[[ -f "$ARCHIVE_PATH/Info.plist" ]] || fail "archive metadata missing"
/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties' "$ARCHIVE_PATH/Info.plist" >/dev/null 2>&1 || fail "archive ApplicationProperties missing"
codesign --verify --deep --strict --verbose=2 "$APP_PATH" >/dev/null 2>&1 || fail "archive app signature invalid"
SIGNING_DETAILS="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1 || true)"
case "$SIGNING_MODE" in
    development)
        grep -q 'Authority=Apple Development:' <<<"$SIGNING_DETAILS" || fail "staging archive is not development signed"
        ;;
    distribution)
        grep -q 'Authority=Apple Distribution:' <<<"$SIGNING_DETAILS" || fail "exported app is not distribution signed"
        ;;
    *) fail "unknown signing mode: $SIGNING_MODE" ;;
esac
PROFILE="$APP_PATH/embedded.mobileprovision"
[[ -f "$PROFILE" ]] || fail "embedded App Store provisioning profile missing"
PROFILE_PLIST="$(mktemp)"
trap 'rm -f "$PROFILE_PLIST"' EXIT
security cms -D -i "$PROFILE" >"$PROFILE_PLIST" 2>/dev/null || fail "embedded provisioning profile is invalid"
PROFILE_ENTITLEMENTS="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements' "$PROFILE_PLIST" 2>/dev/null || true)"
[[ "$PROFILE_ENTITLEMENTS" == *"com.apple.developer.team-identifier"* ]] || fail "profile team entitlement missing"
if [[ "$SIGNING_MODE" == "distribution" ]]; then
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:get-task-allow' "$PROFILE_PLIST" 2>/dev/null || true)" == "false" ]] || fail "profile permits debugging"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:aps-environment' "$PROFILE_PLIST" 2>/dev/null || true)" == "production" ]] || fail "profile is not App Store/production push signed"
    ! /usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' "$PROFILE_PLIST" >/dev/null 2>&1 || fail "profile is development/ad-hoc, not App Store"
fi
[[ "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.usernotifications.communication' "$PROFILE_PLIST" 2>/dev/null || true)" == "true" ]] || fail "profile lacks Communication Notifications entitlement"

for key in NSCameraUsageDescription NSPhotoLibraryAddUsageDescription NSContactsUsageDescription NSMicrophoneUsageDescription NSSpeechRecognitionUsageDescription NSLocationWhenInUseUsageDescription; do
    [[ -n "$(value "$key")" ]] || fail "required privacy usage string missing: $key"
done
for key in NSBluetoothAlwaysUsageDescription NSFaceIDUsageDescription NSMotionUsageDescription NSPhotoLibraryUsageDescription; do
    [[ -z "$(value "$key")" ]] || fail "deferred capability usage string leaked: $key"
done
[[ -z "$(value NSAppTransportSecurity:NSAllowsArbitraryLoads)" ]] || fail "arbitrary HTTP loading leaked"

for marker in '--pwa-v2-actions' 'fixture-share-demo' 'v2-actions.html' '--pwa-offline-query' 'OfflineQueryUITestFixture'; do
    ! strings -a "$APP_PATH/Drel" | grep -qF -- "$marker" || fail "debug fixture leaked into Store binary: $marker"
done

echo "PASS: signed Drel $EXPECTED_VERSION ($EXPECTED_BUILD) $SIGNING_MODE app identity, privacy strings, and fixture boundary verified."
