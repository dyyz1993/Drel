#!/usr/bin/env bash
# Drel-owned WebView integration gate; framework SDK tests live in the sibling repo.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_DIR="$ROOT/build/reports"
REPORT="$REPORT_DIR/drel-app-webview-regression.md"
DERIVED_DATA="/tmp/drel-app-webview-regression"
mkdir -p "$REPORT_DIR"
cd "$ROOT"

SIMULATOR_ID="${WBK_SIMULATOR_ID:-$(xcrun simctl list devices booted 2>/dev/null | awk -F '[()]' '/Booted/{print $2; exit}')}"
if [ -z "$SIMULATOR_ID" ]; then
    echo "No booted simulator. Boot one before running the Drel WebView regression gate." >&2
    exit 1
fi
DESTINATION="id=$SIMULATOR_ID"

PASS=0
FAIL=0
ROWS=()

run_gate() {
    local name="$1"
    local command="$2"
    local log="$REPORT_DIR/$(echo "$name" | tr '[:upper:] /' '[:lower:]--').log"

    echo "== $name =="
    if bash -lc "$command" >"$log" 2>&1; then
        ROWS+=("| $name | PASS | $log |")
        PASS=$((PASS + 1))
        echo "PASS"
    else
        ROWS+=("| $name | FAIL | $log |")
        FAIL=$((FAIL + 1))
        echo "FAIL ($log)"
    fi
}

run_gate "Services start and verify" \
    "bash scripts/services.sh start && bash scripts/services.sh verify"
run_gate "Drel functional WebView tests" \
    "xcodebuild test -workspace Drel.xcworkspace -scheme Drel -sdk iphonesimulator -destination '$DESTINATION' -derivedDataPath '$DERIVED_DATA' CODE_SIGNING_ALLOWED=NO -only-testing:DrelUITests/FunctionalTests"

{
    echo "# Drel App WebView Regression Report"
    echo ""
    echo "| Gate | Result | Evidence |"
    echo "|---|---|---|"
    printf "%s\n" "${ROWS[@]}"
    echo ""
    echo "Summary: $PASS passed, $FAIL failed"
} >"$REPORT"

echo "Report: $REPORT"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
