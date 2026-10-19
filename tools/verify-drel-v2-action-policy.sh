#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRAMEWORK="${WBK_FRAMEWORK_PATH:-$ROOT/../WebBridgeKit-Framework}"
cd "$ROOT"

fail() { echo "FAIL: $*" >&2; exit 1; }

rg -q '^  Drel15Release: release$' project.yml || fail "Drel 1.5 release configuration missing"
rg -q '^  Drel15Store:$' project.yml || fail "Drel 1.5 Store scheme missing"
rg -A 7 '^        Drel15Release:$' project.yml | rg -q 'MARKETING_VERSION: "1.5.0"' || fail "Drel 1.5 version mismatch"
rg -A 7 '^        Drel15Release:$' project.yml | rg -q 'CURRENT_PROJECT_VERSION: "93"' || fail "Drel 1.5 build mismatch"
rg -A 2 '^        Drel15Release:$' project.yml | rg -q 'DREL_CONTAINER_ONLY DREL_RELEASE_MINIMAL_SETTINGS DREL_V2_MANAGED_ACTIONS_ONLY' || fail "Drel 1.5 host policy flags missing"
rg -A 8 '^        Drel15Release:$' project.yml | rg -q 'CODE_SIGN_STYLE: Manual' || fail "Drel 1.5 must use manual App Store signing"
rg -A 8 '^        Drel15Release:$' project.yml | rg -q 'PROVISIONING_PROFILE_SPECIFIER: WebBridgeKit App Store' || fail "Drel 1.5 App Store profile missing"
rg -A 7 '^        Drel14Release:$' project.yml | rg -q 'MARKETING_VERSION: "1.4.1"' || fail "Drel 1.4.1 version was changed"
rg -A 7 '^        Drel14Release:$' project.yml | rg -q 'CURRENT_PROJECT_VERSION: "89"' || fail "Drel 1.4.1 build was changed"
rg -q 'nativeActionAllowlist = \["haptic", "vibrate", "share", "fullscreen"\]' SuperApp/Sources/AppDelegate.swift || fail "Drel 1.5 action allowlist mismatch"
rg -q 'allowedActions.contains\(action\)' "$FRAMEWORK/Sources/Core/WebJavaScriptBridge.swift" || fail "SDK does not enforce the host action allowlist"
rg -q 'testHostActionAllowlistRejectsUnlistedNativeActionBeforeHandler' "$FRAMEWORK/Tests/CoreTests/WebJavaScriptBridgeTests.swift" || fail "host allowlist regression test missing"
rg -q 'testDeclaredShareRunsAfterGestureWithoutReusableConsentGrant' "$FRAMEWORK/Tests/CoreTests/WebJavaScriptBridgeTests.swift" || fail "no-persistent-grant regression test missing"
rg -q 'testDeclaredFullscreenRunsAfterGestureWithoutPrivacyConsentOrReusableGrant' "$FRAMEWORK/Tests/CoreTests/WebJavaScriptBridgeTests.swift" || fail "fullscreen authorization regression missing"
rg -q 'testV2ShareUsesSystemSheetWithoutExtraPermissionPrompt' SuperAppUITests/PWAPermissionTests.swift || fail "system share-sheet UI test missing"
rg -q 'testV2FullscreenUsesGestureWithoutPermissionPromptAndKeepsNativeExit' SuperAppUITests/PWAPermissionTests.swift || fail "fullscreen UI regression test missing"
rg -q '^#if !DREL_CONTAINER_ONLY && !DREL_V2_MANAGED_ACTIONS_ONLY' SuperApp/Sources/Managers/TestDataSeeder.swift || fail "development fixture seeder is not excluded from Drel 1.5"

echo "PASS: Drel 1.5 enables only signed, gesture-bound haptic/vibrate/share/fullscreen actions; 1.4.1 remains 1.4.1 (89)."
