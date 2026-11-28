#!/bin/bash
# WebBridgeKit release readiness gate.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_DIR="$PROJECT_ROOT/build/reports"
REPORT="$REPORT_DIR/release-gate.md"
DERIVED_DATA="/tmp/wbk-dd-release-gate"
ARCHIVE_PATH="${DREL_RELEASE_GATE_ARCHIVE_PATH:-/tmp/wbk-release-gate/Drel.xcarchive}"
RELEASE_SCHEME="${DREL_RELEASE_GATE_SCHEME:-Drel14Store}"
SWIFTLINT_BIN="$(command -v swiftlint)"
ARCHIVE_VERSION_OVERRIDES=""
ARCHIVE_PROVISIONING_UPDATES=""
ARCHIVE_SIGNING_OVERRIDES=""
V2_EXPECTED_BUILD="${DREL_RELEASE_GATE_BUILD_NUMBER:-90}"
if [[ "${DREL_RELEASE_GATE_ALLOW_PROVISIONING_UPDATES:-}" == "1" ]]; then
    ARCHIVE_PROVISIONING_UPDATES="-allowProvisioningUpdates"
fi
if [[ "${DREL_RELEASE_GATE_AUTOMATIC_SIGNING:-}" == "1" ]]; then
    ARCHIVE_SIGNING_OVERRIDES='CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" PROVISIONING_PROFILE_SPECIFIER=""'
fi
if [[ -n "${DREL_RELEASE_GATE_MARKETING_VERSION:-}" ]]; then
    [[ "$DREL_RELEASE_GATE_MARKETING_VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || {
        echo "Invalid DREL_RELEASE_GATE_MARKETING_VERSION" >&2
        exit 2
    }
    [[ "${DREL_RELEASE_GATE_BUILD_NUMBER:-}" =~ ^[0-9]+$ ]] || {
        echo "Set DREL_RELEASE_GATE_BUILD_NUMBER to a numeric build number" >&2
        exit 2
    }
    ARCHIVE_VERSION_OVERRIDES="MARKETING_VERSION=$DREL_RELEASE_GATE_MARKETING_VERSION CURRENT_PROJECT_VERSION=$DREL_RELEASE_GATE_BUILD_NUMBER"
fi
mkdir -p "$REPORT_DIR" "$(dirname "$ARCHIVE_PATH")"
cd "$PROJECT_ROOT"

PASS=0
FAIL=0
ROWS=()
GATE_LAST_PASS=0

run_gate() {
    local name="$1"
    local command="$2"
    local log="$REPORT_DIR/$(echo "$name" | tr '[:upper:] /' '[:lower:]--').log"

    echo "== $name =="
    if bash -lc "$command" >"$log" 2>&1; then
        GATE_LAST_PASS=1
        ROWS+=("| $name | PASS | $log |")
        PASS=$((PASS + 1))
        echo "PASS"
    else
        GATE_LAST_PASS=0
        ROWS+=("| $name | FAIL | $log |")
        FAIL=$((FAIL + 1))
        echo "FAIL ($log)"
    fi
}

# launchctl can report the Python fixture listener before its first accepted
# connection. The authoritative gate is the following explicit health check;
# do not fail a release solely because that transient start probe raced.
run_gate "Services start and verify" "bash scripts/services.sh backend || true; bash scripts/services.sh http || true; bash scripts/services.sh proto || true; bash scripts/services.sh verify"
run_gate "Deliverable boundaries" "bash tools/verify-deliverable-boundaries.sh"
run_gate "Release notes and changelog" "python3 tools/verify-release-notes.py"
run_gate "Release identity" "python3 tools/verify-release-identity.py"
run_gate "Documentation links" "python3 tools/verify-docs-links.py"
run_gate "Repository hygiene" "python3 tools/verify-repo-hygiene.py"
run_gate "SwiftLint" "'$SWIFTLINT_BIN' --quiet"
run_gate "Design lint" "bash tools/ci-lint.sh"
run_gate "Build Debug" "xcodebuild build -workspace Drel.xcworkspace -scheme Drel -sdk iphonesimulator -arch arm64 -derivedDataPath '$DERIVED_DATA' CODE_SIGNING_ALLOWED=NO"
run_gate "Crash scan" "bash scripts/scan-crash-logs.sh --json | grep '\"total\": 0'"
# Keep archive intermediates separate from any interactive/simulator build.
# Xcode otherwise uses its shared default DerivedData path and two overlapping
# builds can corrupt header maps or object-file renames.
run_gate "Archive Release" "xcodebuild archive -workspace Drel.xcworkspace -scheme '$RELEASE_SCHEME' -archivePath '$ARCHIVE_PATH' -derivedDataPath '${DERIVED_DATA}-archive' -destination 'generic/platform=iOS' $ARCHIVE_VERSION_OVERRIDES $ARCHIVE_PROVISIONING_UPDATES $ARCHIVE_SIGNING_OVERRIDES"
ARCHIVE_READY="$GATE_LAST_PASS"
if [[ "$ARCHIVE_READY" == "1" ]]; then
    if [[ -n "${DREL_RELEASE_GATE_MARKETING_VERSION:-}" ]]; then
        run_gate "Archive version identity" "test \"\$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' '$ARCHIVE_PATH/Products/Applications/Drel.app/Info.plist')\" = '$DREL_RELEASE_GATE_MARKETING_VERSION' && test \"\$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' '$ARCHIVE_PATH/Products/Applications/Drel.app/Info.plist')\" = '$DREL_RELEASE_GATE_BUILD_NUMBER'"
    fi
    run_gate "No Release test HTML" "if [ -d '$ARCHIVE_PATH/Products/Applications/Drel.app' ]; then ! find '$ARCHIVE_PATH/Products/Applications/Drel.app' -iname '*test*.html' | grep -q .; else exit 1; fi"
    run_gate "No DEBUG-only code in Release" "bash tools/verify-release-no-debug.sh '$ARCHIVE_PATH/Products/Applications/Drel.app'"
else
    echo "SKIP: archive artifact checks because archive creation failed"
fi
if [[ "$RELEASE_SCHEME" == "Drel15Store" ]]; then
    run_gate "Drel 1.5 managed action policy" "bash tools/verify-drel-v2-action-policy.sh"
else
    run_gate "Drel Store container-only policy" "bash tools/verify-drel-container-only.sh"
fi
run_gate "Drel App WebView regression" "bash tools/run-drel-app-webview-regression.sh"
run_gate "Drel Store minimal settings policy" "DREL_RELEASE_SETTINGS_SCHEME='$RELEASE_SCHEME' bash tools/verify-drel-release-settings.sh"
if [[ "$ARCHIVE_READY" == "1" ]]; then
    if [[ "$RELEASE_SCHEME" == "Drel15Store" ]]; then
        if [[ "${DREL_RELEASE_GATE_AUTOMATIC_SIGNING:-}" == "1" ]]; then
            run_gate "Drel 1.5 staging archive surface" "DREL_V2_EXPECTED_VERSION='${DREL_RELEASE_GATE_MARKETING_VERSION:-1.5.1}' DREL_V2_EXPECTED_BUILD='${DREL_RELEASE_GATE_BUILD_NUMBER:-$V2_EXPECTED_BUILD}' DREL_V2_ARCHIVE_SIGNING=development bash tools/verify-drel-v2-store-archive.sh '$ARCHIVE_PATH'"
        else
            run_gate "Drel 1.5 Store archive surface" "DREL_V2_EXPECTED_VERSION='${DREL_RELEASE_GATE_MARKETING_VERSION:-1.5.1}' DREL_V2_EXPECTED_BUILD='${DREL_RELEASE_GATE_BUILD_NUMBER:-$V2_EXPECTED_BUILD}' bash tools/verify-drel-v2-store-archive.sh '$ARCHIVE_PATH'"
        fi
    else
        run_gate "Drel Store archive surface" "bash tools/verify-drel-store-archive.sh '$ARCHIVE_PATH'"
    fi
fi

{
    echo "# Release Gate Report"
    echo ""
    echo "| Gate | Result | Evidence |"
    echo "|---|---|---|"
    printf "%s\n" "${ROWS[@]}"
    echo ""
    echo "Summary: $PASS passed, $FAIL failed"
    echo ""
    echo "AppTemplate readiness is verified independently by: bash tools/run-template-gate.sh"
} >"$REPORT"

echo "Report: $REPORT"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi

cat >&2 <<'REMINDER'

⚠️  RELEASE REMINDER
Automated gates passed, but APNs delivery and notification presentation still
require physical-iPhone validation after TestFlight installation:
  1. Enable notifications on a real device.
  2. Send one normal push and one icon/avatar push.
  3. Verify lock-screen/banner, sound, badge, and Inbox entry.
  4. Tap each notification and confirm the exact target page opens once.

REMINDER
