#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRAMEWORK="${WBK_FRAMEWORK_PATH:-$ROOT/../WebBridgeKit-Framework}"
# Default to the build number the project currently declares, so the gate
# follows the release train instead of expiring on every version bump.
if [[ -z "${DREL_V2_EXPECTED_BUILD:-}" ]]; then
  EXPECTED_BUILD="$(rg -A 7 '^        Drel15Release:$' "$ROOT/project.yml" \
    | rg -o 'CURRENT_PROJECT_VERSION: "[0-9]+"' \
    | rg -o '[0-9]+' | head -1)"
fi
EXPECTED_BUILD="${DREL_V2_EXPECTED_BUILD:-$EXPECTED_BUILD}"
cd "$ROOT"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -n "$EXPECTED_BUILD" ]] || fail "Drel 1.5 build number could not be resolved"

rg -q '^  Drel15Release: release$' project.yml || fail "Drel 1.5 release configuration missing"
rg -q '^  Drel15Store:$' project.yml || fail "Drel 1.5 Store scheme missing"
rg -A 7 '^        Drel15Release:$' project.yml | rg -q 'MARKETING_VERSION: "1.5.4"' || fail "Drel 1.5.4 version mismatch"
rg -A 7 '^        Drel15Release:$' project.yml | rg -q 'CURRENT_PROJECT_VERSION: "145"' || fail "Drel 1.5.4 build mismatch"
rg -A 2 '^        Drel15Release:$' project.yml | rg -q 'DREL_CONTAINER_ONLY DREL_RELEASE_MINIMAL_SETTINGS DREL_V2_MANAGED_ACTIONS_ONLY' || fail "Drel 1.5 host policy flags missing"
rg -A 2 '^        Drel15Release:$' project.yml | rg -q 'DREL_151_MICROPHONE' || fail "Drel 1.5 microphone allowlist flag missing"
rg -A 8 '^        Drel15Release:$' project.yml | rg -q 'CODE_SIGN_STYLE: Manual' || fail "Drel 1.5 must use manual App Store signing"
rg -A 8 '^        Drel15Release:$' project.yml | rg -q 'PROVISIONING_PROFILE_SPECIFIER: WebBridgeKit App Store' || fail "Drel 1.5 App Store profile missing"
rg -A 7 '^        Drel14Release:$' project.yml | rg -q 'MARKETING_VERSION: "1.4.1"' || fail "Drel 1.4.1 version was changed"
rg -A 7 '^        Drel14Release:$' project.yml | rg -q 'CURRENT_PROJECT_VERSION: "89"' || fail "Drel 1.4.1 build was changed"
rg -q '"haptic", "vibrate", "share", "fullscreen",' SuperApp/Sources/AppDelegate.swift || fail "Drel 1.5 action allowlist mismatch"
rg -q '"clipboard", "getLocation", "addToHomeScreen", "sensors", "getCapabilities"' SuperApp/Sources/AppDelegate.swift || fail "Drel 1.5 action allowlist mismatch"
rg -q '^  Drel151Release: release$' project.yml || fail "Drel 1.5.1 release configuration missing"
rg -q '^  Drel151Store:$' project.yml || fail "Drel 1.5.1 Store scheme missing"
rg -A 7 '^        Drel151Release:$' project.yml | rg -q 'DREL_CONTAINER_ONLY DREL_RELEASE_MINIMAL_SETTINGS DREL_V2_MANAGED_ACTIONS_ONLY DREL_151_MICROPHONE' || fail "Drel 1.5.1 microphone policy flags missing"
rg -A 7 '^        Drel151Release:$' project.yml | rg -q 'MARKETING_VERSION: "1.5.1"' || fail "Drel 1.5.1 version mismatch"
rg -A 7 '^        Drel151Release:$' project.yml | rg -q 'CURRENT_PROJECT_VERSION: "135"' || fail "Drel 1.5.1 build mismatch"
rg -q '#if DREL_151_MICROPHONE' SuperApp/Sources/AppDelegate.swift || fail "Drel 1.5.1 microphone allowlist gate missing"
rg -q 'nativeActionAllowlist\?\.insert\("audioLevel"\)' SuperApp/Sources/AppDelegate.swift || fail "Drel 1.5.1 microphone action missing"
rg -q '^  Drel152Release: release$' project.yml || fail "microphone release configuration missing"
rg -q '^  Drel152Store:$' project.yml || fail "microphone release scheme missing"
rg -q '^  Drel153Release: release$' project.yml || fail "capability query release configuration missing"
rg -q '^  Drel153Store:$' project.yml || fail "capability query release scheme missing"
rg -A 7 '^        Drel153Release:$' project.yml | rg -q 'DREL_152_MICROPHONE' || fail "1.5.3 microphone policy flag missing"
rg -A 7 '^        Drel153Release:$' project.yml | rg -q 'MARKETING_VERSION: "1.5.3"' || fail "capability query version mismatch"
rg -A 7 '^        Drel153Release:$' project.yml | rg -q 'CURRENT_PROJECT_VERSION: "142"' || fail "capability query build mismatch"
rg -A 7 '^        Drel152Release:$' project.yml | rg -q 'DREL_152_MICROPHONE' || fail "microphone policy flag missing"
rg -A 7 '^        Drel152Release:$' project.yml | rg -q 'MARKETING_VERSION: "1.5.2"' || fail "microphone version mismatch"
rg -A 7 '^        Drel152Release:$' project.yml | rg -q 'CURRENT_PROJECT_VERSION: "138"' || fail "microphone build mismatch"
rg -q '#if DREL_151_MICROPHONE \|\| DREL_152_MICROPHONE' SuperApp/Sources/AppDelegate.swift || fail "microphone allowlist gate missing"
rg -q 'nativeActionAllowlist\?\.insert\("audioLevel"\)' SuperApp/Sources/AppDelegate.swift || fail "microphone action missing"
rg -q 'allowedActions.contains\(action\)' "$FRAMEWORK/Sources/Core/WebJavaScriptBridge.swift" || fail "SDK does not enforce the host action allowlist"
rg -q 'testHostActionAllowlistRejectsUnlistedNativeActionBeforeHandler' "$FRAMEWORK/Tests/CoreTests/WebJavaScriptBridgeTests.swift" || fail "host allowlist regression test missing"
rg -q 'testDeclaredShareRunsAfterGestureWithoutReusableConsentGrant' "$FRAMEWORK/Tests/CoreTests/WebJavaScriptBridgeTests.swift" || fail "no-persistent-grant regression test missing"
rg -q 'testDeclaredFullscreenRunsAfterGestureWithoutPrivacyConsentOrReusableGrant' "$FRAMEWORK/Tests/CoreTests/WebJavaScriptBridgeTests.swift" || fail "fullscreen authorization regression missing"
rg -q 'testV2ShareUsesSystemSheetWithoutExtraPermissionPrompt' SuperAppUITests/PWAPermissionTests.swift || fail "system share-sheet UI test missing"
rg -q 'testV2FullscreenUsesGestureWithoutPermissionPromptAndKeepsNativeExit' SuperAppUITests/PWAPermissionTests.swift || fail "fullscreen UI regression test missing"
rg -q '^#if !DREL_CONTAINER_ONLY && !DREL_V2_MANAGED_ACTIONS_ONLY' SuperApp/Sources/Managers/TestDataSeeder.swift || fail "development fixture seeder is not excluded from Drel 1.5"

echo "PASS: Drel 1.5.4 (145) keeps signed actions; 1.5.1 (135), 1.5.2 (138), and 1.5.3 (142) preserve their gated action surfaces; 1.4.1 remains 1.4.1 (89)."
