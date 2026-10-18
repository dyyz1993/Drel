#!/bin/bash
# Verify that the Application project (SuperApp / Drel) maintains clean boundaries with WebBridgeKit-Framework.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

PASS=0
FAIL=0

pass() {
    echo "  PASS  $1"
    PASS=$((PASS + 1))
}

fail() {
    echo "  FAIL  $1"
    if [ -n "${2:-}" ]; then
        echo "$2" | sed 's/^/         /'
    fi
    FAIL=$((FAIL + 1))
}

echo ""
echo "=== Application Deliverable Boundary Verification ==="
echo ""

if [ ! -d "Sources" ] && [ ! -d "AppTemplate" ] && [ ! -d "Tests" ]; then
    pass "Framework Sources, AppTemplate, and SDK unit Tests are cleanly extracted to WebBridgeKit-Framework"
else
    fail "Framework Sources, AppTemplate, and SDK unit Tests are cleanly extracted to WebBridgeKit-Framework"
fi

if [ ! -f "SuperApp/project.yml" ]; then
    pass "Legacy nested SuperApp/project.yml is removed"
else
    fail "Legacy nested SuperApp/project.yml is removed"
fi

if grep -q "pod 'WebBridgeKit'" Podfile; then
    pass "Podfile declares dependency on WebBridgeKit framework"
else
    fail "Podfile declares dependency on WebBridgeKit framework"
fi

NSE_WBK_IMPORTS=$(rg -n 'import[[:space:]]+WebBridgeKit' NotificationServiceExtension --glob '*.swift' 2>/dev/null || true)
if [ -z "$NSE_WBK_IMPORTS" ]; then
    pass "NotificationServiceExtension remains self-contained without importing WebBridgeKit"
else
    fail "NotificationServiceExtension remains self-contained without importing WebBridgeKit" "$NSE_WBK_IMPORTS"
fi

if rg -q 'PushCipher\.configure' SuperApp/Sources/AppDelegate.swift && test -f SuperApp/Sources/Configuration/DrelGatewayConfiguration.swift; then
    pass "SuperApp explicitly injects App Group, Keychain, and Official Gateway configuration at launch"
else
    fail "SuperApp explicitly injects App Group, Keychain, and Official Gateway configuration at launch"
fi

if rg -q 'officialGateway: DrelGatewayConfiguration\.official' SuperApp/Sources \
    && rg -q 'WebBridgeHostCapabilityPolicy\.containerOnlyOverride' SuperApp/Sources/AppDelegate.swift; then
    pass "SuperApp owns Drel gateway migration and container-only host policy"
else
    fail "SuperApp owns Drel gateway migration and container-only host policy"
fi

if bash tools/verify-push-wire-contract.sh >/dev/null; then
    pass "NotificationServiceExtension and server consume the shared push wire contract"
else
    fail "NotificationServiceExtension and server consume the shared push wire contract"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
