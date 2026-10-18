# Drel 1.5.0 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ship a narrowly bounded Drel 1.5.0 release that enables only signed,
per-purpose, revocable `haptic`, `vibrate`, and `share` actions for
network-managed apps.

**Architecture:** Split ownership cleanly between the reusable SDK and the
Drel product. The SDK provides generic manifest, signature, authorization, and
action primitives; Drel injects the product trust policy, action catalog,
permission UI, audit store, and release gates. Offline packages and ordinary
web pages remain bridge-disabled.

**Tech Stack:** Swift 5 / iOS 15, XcodeGen, CocoaPods, XCTest, XCUITest,
Hummingbird Swift server, Ed25519 manifest signing, WKWebView, AVFoundation
metadata scanning, UIKit share sheet, and local persisted audit storage.

---

## Fixed owner decisions

The original four decisions plus the 2026-10-18 scope reduction are accepted in
`docs/release/drel-1-5-0-owner-decisions.md` and must not be reopened during
implementation without a new owner decision:

1. Drel ships a local, bounded, redacted, user-visible permission audit
   history.
2. `haptic` and `vibrate` require the same signed action declarations,
   authorization, audit, and revocation path as `share` and `scan`.
3. The Drel product owner owns security review and final security sign-off.
4. The Drel product owner owns App Review narrative, privacy disclosure, and
   final privacy sign-off.
5. The first 1.5.0 review train includes only `haptic`, `vibrate`, and `share`;
   scan, photos, Bluetooth, and microphone are deferred.

## Non-negotiable boundaries

- 1.4.1 Build 89 is a separate App Review train. Do not change its version,
  build number, configuration, or ASC metadata while implementing this plan.
- 1.5.0 does not open Bridge for offline packages.
- Ordinary web pages and all 1.4 manifests remain `Bridge=0`.
- The only allowed actions are `haptic`, `vibrate`, and `share`.
- All enabled actions support only `once` or `appSession`; `always` is
  forbidden.
- Protected actions require a foreground user gesture.
- Push and deep links may navigate, but never authorize or execute a protected
  action.
- There is no generic JavaScript-to-native Bridge and no remotely extensible
  native action catalog.

## Repository responsibility split

| Concern | Drel repository | WebBridgeKit-Framework repository |
| --- | --- | --- |
| Product scope and owner decisions | Owns | Reference only |
| Gateway trust anchor and official gateway injection | Injects | Provides generic injection API |
| Container-only policy | Injects product policy | Provides generic host-policy hook |
| Push App Group / Keychain namespace | Injects product identifiers | Provides configurable storage primitives |
| Manifest v2 schema and signing | Server and product tests own contract | SDK owns shared models and validation primitives |
| Action catalog | Owns the four-action allowlist | Provides generic action model |
| Permission UI, audit history, revocation UX | Owns | Provides primitives only |
| Scanner, share sheet, haptics | Owns product wrappers | Provides reusable handler foundations |
| App Review and privacy package | Owns | Provides technical input only |

---

## Task 0: Confirm the working baseline

**Files:**

- Read-only: `docs/release/drel-1-5-0-owner-decisions.md`
- Read-only: `docs/adr/0006-split-drel-product-repository.md`
- Read-only: `docs/plans/2026-10-18-drel-1-5-0-implementation.md`

**Step 1: Confirm decisions and boundaries**

Confirm all owner decisions and the non-negotiable boundaries above are
still current.

**Step 2: Confirm repository state**

Run:

```bash
git status --short --branch
```

Expected:

```text
## main...origin/main
```

Do not begin if either repository has unrelated uncommitted work.

**Step 3: Record the named security reviewer**

Before code changes, the product owner must name the security reviewer in the
implementation tracking note. A placeholder such as “TBD” blocks Task 1.

---

## Task 1: Repair verification ownership and fresh baseline

**Files:**

- Modify: `../WebBridgeKit-Framework/tools/run-jsbridge-regression.sh`
- Create: `tools/run-drel-app-webview-regression.sh`
- Modify: `tools/run-release-gate.sh`
- Modify: `.github/workflows/ci.yml`
- Modify: `../WebBridgeKit-Framework/.github/workflows/ci.yml`

**Step 1: Remove stale product references from the framework gate**

Remove the `SuperApp` scheme and `SuperAppUITests` references from
`tools/run-jsbridge-regression.sh`. The framework gate must run only:

- browser fallback JavaScript verification;
- `CoreTests/WebJavaScriptBridgeTests`;
- `BridgeTests`;
- the focused SDK handler shards that do not require the Drel app host.

**Step 2: Add the Drel App WebView integration gate**

Create `tools/run-drel-app-webview-regression.sh`. It must:

1. Start local services.
2. Build and test the Drel app scheme.
3. Run real WebView tests for bridge bootstrap, ordinary-page denial, and each
   enabled action.
4. Write a report under `build/reports/`.

**Step 3: Wire the gates into CI**

- Framework CI runs the SDK JSBridge gate and template gate.
- Drel CI runs the new App WebView gate and existing release gates.

**Step 4: Run the refreshed baselines**

Framework:

```bash
cd ../WebBridgeKit-Framework
xcodegen generate
pod install
bash tools/verify-deliverable-boundaries.sh
bash tools/run-template-gate.sh
bash tools/run-jsbridge-regression.sh
```

Drel:

```bash
xcodegen generate
pod install
bash scripts/services.sh start
bash scripts/services.sh verify
bash tools/verify-deliverable-boundaries.sh
bash tools/verify-drel-container-only.sh
bash tools/verify-drel-release-settings.sh
bash tools/run-drel-app-webview-regression.sh
```

Expected:

- Framework boundary: 6/6.
- Framework template gate: 5/5.
- Framework JSBridge regression: all selected SDK tests pass.
- Drel boundary: 5/5.
- Drel container-only policy: 40/40.
- Drel release-settings policy: 11/11.
- New Drel WebView gate: all tests pass.

**Step 5: Commit**

```bash
git add tools/run-drel-app-webview-regression.sh tools/run-release-gate.sh .github/workflows/ci.yml
git commit -m "ci: separate framework and Drel verification ownership"
```

Framework repository:

```bash
git add tools/run-jsbridge-regression.sh .github/workflows/ci.yml
git commit -m "ci: scope JSBridge regression to framework targets"
```

---

## Task 2: Remove the Drel gateway default and migration from the SDK

**Files:**

- Modify: `../WebBridgeKit-Framework/Sources/Runtime/HTMLAppGatewayConfiguration.swift`
- Modify: `../WebBridgeKit-Framework/Tests/ModelsTests/HTMLAppGatewayConfigurationTests.swift`
- Modify: `../WebBridgeKit-Framework/AppTemplate/Sources/*` only if it currently
  relies on the removed default
- Modify: `../WebBridgeKit-Framework/README.md`
- Modify: `SuperApp/Sources/AppDelegate.swift`

**Step 1: Write failing framework tests**

Add tests proving:

1. The SDK has no built-in `drel-gateway` default.
2. The SDK has no Drel legacy-origin migration.
3. A host can inject an official gateway configuration.
4. An unconfigured host does not silently activate a Drel trust anchor.

Suggested test names:

- `testSDKHasNoDrelGatewayDefault`
- `testLegacyDrelOriginsAreNotMigrated`
- `testHostCanInjectOfficialGateway`
- `testUnconfiguredHostHasNoActiveOfficialGateway`

**Step 2: Run tests and confirm failure**

```bash
cd ../WebBridgeKit-Framework
xcodebuild test \
  -workspace WebBridgeKit.xcworkspace \
  -scheme ModelsTests \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:ModelsTests/HTMLAppGatewayConfigurationTests
```

Expected: the new tests fail because the Drel default and migration remain.

**Step 3: Extract the Drel gateway**

In the SDK:

- Remove `HTMLAppGatewayDefaults.official`’s Drel values.
- Remove Drel-specific migration origins and IDs.
- Keep a generic host-injection API.

In Drel:

- Move the official gateway values into `SuperApp/Sources/AppDelegate.swift`
  or a dedicated product configuration type.
- Inject them at startup.

**Step 4: Run tests and confirm success**

Repeat the ModelsTests command. Expected: all tests pass, including the four
new tests.

**Step 5: Run cross-repo gates**

```bash
cd ../WebBridgeKit-Framework
bash tools/verify-deliverable-boundaries.sh
bash tools/run-template-gate.sh

cd ../Drel
bash tools/verify-deliverable-boundaries.sh
bash tools/verify-drel-container-only.sh
```

**Step 6: Commit**

Framework:

```bash
git add Sources/Runtime/HTMLAppGatewayConfiguration.swift Tests/ModelsTests/HTMLAppGatewayConfigurationTests.swift README.md
git commit -m "refactor(gateway): remove Drel-specific defaults from SDK"
```

Drel:

```bash
git add SuperApp/Sources/AppDelegate.swift
git commit -m "feat(app): inject Drel official gateway at startup"
```

---

## Task 3: Remove the product container-only switch from SDK source

**Files:**

- Modify: `../WebBridgeKit-Framework/Sources/Runtime/DrelContainerBuildPolicy.swift`
- Modify: `../WebBridgeKit-Framework/Sources/ViewModels/WebBrowserViewModel.swift`
- Modify: `../WebBridgeKit-Framework/Sources/Controllers/WebBrowserViewController.swift`
- Modify: `../WebBridgeKit-Framework/Sources/Controllers/WebBrowserViewController+Delegates.swift`
- Modify: `../WebBridgeKit-Framework/Sources/Controllers/WebBrowserViewController+Menu.swift`
- Modify: `../WebBridgeKit-Framework/Sources/Controllers/WebViewController.swift`
- Modify: `../WebBridgeKit-Framework/Sources/Controllers/WebViewController+CacheDebug.swift`
- Modify: `../WebBridgeKit-Framework/Sources/WebBridgeKit.swift`
- Modify: `../WebBridgeKit-Framework/Tests/CoreTests/*`
- Modify: `SuperApp/Sources/AppDelegate.swift`
- Modify: `tools/verify-drel-container-only.sh`

**Step 1: Write failing SDK tests**

Add tests proving:

1. A default framework build enables the native bridge.
2. A host can inject `containerOnly = true`.
3. No source path depends on `DREL_CONTAINER_ONLY`.
4. The user-agent and runtime bootstrap still expose `Bridge/0` when the host
   policy disables the bridge.

Suggested test names:

- `testDefaultFrameworkBuildEnablesBridge`
- `testHostContainerOnlyOverrideDisablesBridge`
- `testRuntimeContractReportsBridgeZeroWhenContainerOnly`

**Step 2: Confirm tests fail**

```bash
cd ../WebBridgeKit-Framework
xcodebuild test \
  -workspace WebBridgeKit.xcworkspace \
  -scheme CoreTests \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:CoreTests/WebBrowserManagerTests
```

**Step 3: Replace the compile-time switch with host policy**

Rename or replace `DrelContainerBuildPolicy` with a generic
`WebBridgeHostCapabilityPolicy`. The SDK must:

- default to bridge-enabled;
- accept an explicit host override;
- never mention Drel or `DREL_CONTAINER_ONLY`.

Update all SDK call sites to consult the generic policy.

**Step 4: Update Drel injection**

In `SuperApp/Sources/AppDelegate.swift`, inject:

```swift
WebBridgeHostCapabilityPolicy.shared.containerOnly = true
```

for Store configurations, and `false` for development configurations.

**Step 5: Update the Drel verifier**

Change `tools/verify-drel-container-only.sh` so it proves:

- Drel Store configurations inject container-only policy;
- SDK source contains no `DREL_CONTAINER_ONLY`;
- Drel archive still reports `Bridge=0`;
- ordinary pages receive no bridge object.

**Step 6: Run all gates**

Framework:

```bash
bash tools/verify-deliverable-boundaries.sh
bash tools/run-template-gate.sh
```

Drel:

```bash
bash tools/verify-drel-container-only.sh
bash tools/run-drel-app-webview-regression.sh
bash tools/run-release-gate.sh
```

**Step 7: Commit**

Framework:

```bash
git add Sources Tests
git commit -m "refactor(policy): replace product compile flag with host policy"
```

Drel:

```bash
git add SuperApp/Sources/AppDelegate.swift tools/verify-drel-container-only.sh
git commit -m "feat(app): inject Drel container-only host policy"
```

---

## Task 4: Make push identity namespaces host-owned

**Files:**

- Modify: `../WebBridgeKit-Framework/Sources/Message/PushCipher.swift`
- Modify: `../WebBridgeKit-Framework/Sources/Message/SelfHostedPushCrypto.swift`
- Modify: `../WebBridgeKit-Framework/Tests/MessageTests/PushCipherContractTests.swift`
- Modify: `SuperApp/Sources/AppDelegate.swift`
- Modify: `NotificationServiceExtension/PushCrypto.swift` only if needed for
  temporary compatibility during this task

**Step 1: Write failing namespace tests**

Add tests proving:

1. SDK defaults use a WebBridgeKit namespace, not
   `group.com.webbridgekit.superapp`.
2. A host can override App Group and Keychain service names.
3. Two hosts with different namespaces cannot read each other’s keys.
4. Drel injection restores the existing product identifiers.

Suggested names:

- `testDefaultPushNamespaceIsWebBridgeKit`
- `testHostCanOverridePushNamespace`
- `testNamespacesAreIsolated`

**Step 2: Run failing tests**

```bash
cd ../WebBridgeKit-Framework
xcodebuild test \
  -workspace WebBridgeKit.xcworkspace \
  -scheme MessageTests \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

**Step 3: Change defaults and keep injection**

Replace the Drel-branded defaults with WebBridgeKit defaults. Keep the existing
`configure(appGroup:keychainService:)` APIs.

In Drel, continue injecting:

```swift
PushCipher.configure(
    appGroup: "group.com.webbridgekit.superapp",
    keychainService: "com.webbridgekit.superapp.push-crypto"
)
SelfHostedPushCrypto.configure(
    appGroup: "group.com.webbridgekit.superapp"
)
```

**Step 4: Run contract and Drel push tests**

Framework:

```bash
xcodebuild test -workspace WebBridgeKit.xcworkspace -scheme MessageTests \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

Drel:

```bash
bash tools/verify-apns-single-attempt.sh
bash tools/verify-real-device-push-readiness.sh
```

**Step 5: Commit**

Framework:

```bash
git add Sources/Message Tests/MessageTests
git commit -m "refactor(push): use host-owned identity namespaces"
```

Drel:

```bash
git add SuperApp/Sources/AppDelegate.swift
git commit -m "feat(app): inject Drel push identity namespace"
```

---

## Task 5: Share the NSE wire contract

**Files:**

- Create: `../WebBridgeKit-Framework/Sources/Message/WBKPushWireContract.swift`
- Modify: `../WebBridgeKit-Framework/Tests/MessageTests/PushCipherContractTests.swift`
- Modify: `NotificationServiceExtension/PushCrypto.swift`
- Modify: `Podfile`
- Modify: `project.yml`
- Create: `tools/verify-push-wire-contract.sh`

**Step 1: Define the contract once**

Create a small, dependency-free Swift source containing:

- ciphertext field name;
- self-hosted envelope field name;
- schema identifier;
- defaults key names;
- file names;
- canonical associated-data construction.

**Step 2: Write a drift test**

Add a test that compares the shared contract constants with:

- the SDK `WBKMessage` implementation;
- the Drel NSE implementation;
- the server’s envelope schema;
- the contract test fixtures.

Suggested name:

- `testPushWireContractIsIdenticalAcrossSDKServerAndNSE`

**Step 3: Compile the same source into the NSE**

Update `NotificationServiceExtension/PushCrypto.swift` to consume the shared
source. In `project.yml`, add the exact sibling file
`../WebBridgeKit-Framework/Sources/Message/WBKPushWireContract.swift` to the
NSE target’s sources. Do not copy it into a second Drel file and do not import
the full WebBridgeKit framework into the NSE.

**Step 4: Build and test**

```bash
cd ../Drel
xcodegen generate
pod install
xcodebuild build \
  -workspace Drel.xcworkspace \
  -scheme Drel \
  -sdk iphonesimulator \
  -arch arm64 \
  -derivedDataPath /tmp/drel-nse-contract \
  CODE_SIGNING_ALLOWED=NO
bash tools/verify-push-wire-contract.sh
```

**Step 5: Commit**

```bash
git add NotificationServiceExtension Podfile project.yml tools/verify-push-wire-contract.sh
git commit -m "refactor(nse): consume shared push wire contract"
```

Framework:

```bash
git add Sources/Message/WBKPushWireContract.swift Tests/MessageTests/PushCipherContractTests.swift
git commit -m "feat(message): expose shared push wire contract"
```

---

## Task 6: Add Manifest v2 action declarations on the server

**Files:**

- Modify: `Server/Sources/WebBridgeServer/Models/HTMLAppPolicyManifest.swift`
- Modify: `Server/Sources/WebBridgeServer/Services/HTMLAppGatewayService.swift`
- Modify: `Server/Tests/WebBridgeServerTests/HTMLAppGatewayRoutesTests.swift`
- Create: `Server/Tests/WebBridgeServerTests/HTMLAppCapabilitiesV2Tests.swift`
- Create: `test_resources/capabilities-v2/signed-manifest.json`

**Step 1: Define the v2 schema**

Add:

```json
"capabilities_v2": [
  {
    "action": "scan",
    "origins": ["https://inventory.example.com"],
    "purposeId": "scan-asset-tag",
    "purpose": "Scan an asset tag for this inventory item",
    "scope": "appSession"
  }
]
```

Validation rules:

- `action` is one of `haptic`, `vibrate`, `share`, `scan`.
- `origins` is a nonempty subset of parent `allowedOrigins`.
- `purposeId` is stable, nonempty, and bounded.
- `purpose` is nonempty and length-bounded.
- `scope` is `once` or `appSession`; `always` is invalid.
- `scan` cannot satisfy `camera`, `video`, or `torch`.
- Legacy `capabilities` never upgrades to v2.
- Empty `capabilities_v2` grants nothing.

**Step 2: Write failing server tests**

Cover:

1. Valid v2 manifest signing and verification.
2. Tampered action.
3. Tampered origin.
4. Tampered purpose ID.
5. Tampered purpose text.
6. Tampered scope.
7. `always` rejection.
8. Origin outside parent manifest.
9. Duplicate purpose IDs.
10. Legacy capability arrays not upgrading.

**Step 3: Implement schema and canonical signing**

Extend the manifest model and gateway service. Ensure the signature covers every
v2 field.

**Step 4: Run server tests**

```bash
cd Server
swift test
```

Expected: all existing tests and the new v2 tests pass.

**Step 5: Commit**

```bash
git add Server/Sources/WebBridgeServer/Models/HTMLAppPolicyManifest.swift \
  Server/Sources/WebBridgeServer/Services/HTMLAppGatewayService.swift \
  Server/Tests/WebBridgeServerTests/HTMLAppGatewayRoutesTests.swift \
  Server/Tests/WebBridgeServerTests/HTMLAppCapabilitiesV2Tests.swift \
  test_resources/capabilities-v2/signed-manifest.json
git commit -m "feat(server): sign action-level capability declarations"
```

---

## Task 7: Add the SDK action-declaration model

**Files:**

- Modify: `../WebBridgeKit-Framework/Sources/Models/HTMLAppRuntimeModels.swift`
- Create: `../WebBridgeKit-Framework/Sources/Runtime/HTMLAppActionDeclaration.swift`
- Modify: `../WebBridgeKit-Framework/Sources/Runtime/HTMLAppBridgeCapabilityPolicy.swift`
- Modify: `../WebBridgeKit-Framework/Sources/Core/WebJavaScriptBridge.swift`
- Modify: `../WebBridgeKit-Framework/Tests/ModelsTests/HTMLAppRuntimeModelsTests.swift`
- Create: `../WebBridgeKit-Framework/Tests/CoreTests/HTMLAppActionDeclarationTests.swift`

**Step 1: Write failing model tests**

Test:

1. v2 declaration decoding.
2. Action allowlisting.
3. Origin subset enforcement.
4. Purpose ID and purpose text bounds.
5. Scope restrictions.
6. Legacy arrays not satisfying v2 requests.
7. `scan` not satisfying camera or torch.

**Step 2: Implement the model**

Introduce a concrete `HTMLAppActionDeclaration` type and validation method.
Keep it generic in the SDK; Drel will supply the allowlist.

**Step 3: Route action authorization through declarations**

Update `WebJavaScriptBridge` so protected actions require:

- a signed parent manifest;
- an exact action declaration;
- matching origin;
- allowed scope;
- foreground gesture evidence supplied by the host.

**Step 4: Run tests**

```bash
cd ../WebBridgeKit-Framework
xcodebuild test \
  -workspace WebBridgeKit.xcworkspace \
  -scheme ModelsTests \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
xcodebuild test \
  -workspace WebBridgeKit.xcworkspace \
  -scheme CoreTests \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

**Step 5: Commit**

```bash
git add Sources/Models/HTMLAppRuntimeModels.swift \
  Sources/Runtime/HTMLAppActionDeclaration.swift \
  Sources/Runtime/HTMLAppBridgeCapabilityPolicy.swift \
  Sources/Core/WebJavaScriptBridge.swift \
  Tests/ModelsTests/HTMLAppRuntimeModelsTests.swift \
  Tests/CoreTests/HTMLAppActionDeclarationTests.swift
git commit -m "feat(bridge): require action-level signed declarations"
```

---

## Task 8: Enforce Drel’s managed-manifest-only trust policy

**Files:**

- Create: `SuperApp/Sources/Services/DrelCapabilityRuntimePolicy.swift`
- Modify: `SuperApp/Sources/Managers/EngineBootstrap.swift`
- Modify: `SuperApp/Sources/Controllers/WebBrowserViewController.swift`
- Modify: `SuperApp/Sources/AppDelegate.swift`
- Create: `DrelTests/DrelCapabilityRuntimePolicyTests.swift`
- Modify: `SuperAppUITests/FunctionalTests.swift`

**Step 1: Write failing product policy tests**

Prove:

1. Ordinary web pages receive no bridge object.
2. `local.<origin>` identities are rejected.
3. `page.<app-id>` identities are rejected.
4. Only an active trusted gateway plus exact signed manifest can bootstrap.
5. Origin or app ID mismatch fails.
6. Push and deep links cannot authorize or execute actions.
7. Offline package entrypoints remain `Bridge=0`.

**Step 2: Implement the product policy**

Create `DrelCapabilityRuntimePolicy` with:

```swift
enum DrelCapabilityAction: String {
    case haptic
    case vibrate
    case share
    case scan
}
```

Expose only the enabled 1.5.0 actions and reject everything else.

**Step 3: Remove local/page fallback paths in Drel**

Ensure the Drel host does not create `local.` or `page.` subjects and does not
install the bridge for unmanaged origins.

**Step 4: Run product tests**

```bash
xcodebuild test \
  -workspace Drel.xcworkspace \
  -scheme Drel \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:DrelTests/DrelCapabilityRuntimePolicyTests \
  -only-testing:DrelUITests/FunctionalTests
```

**Step 5: Commit**

```bash
git add SuperApp/Sources/Services/DrelCapabilityRuntimePolicy.swift \
  SuperApp/Sources/Managers/EngineBootstrap.swift \
  SuperApp/Sources/Controllers/WebBrowserViewController.swift \
  SuperApp/Sources/AppDelegate.swift \
  DrelTests/DrelCapabilityRuntimePolicyTests.swift \
  SuperAppUITests/FunctionalTests.swift
git commit -m "feat(policy): restrict bridge to managed signed apps"
```

---

## Task 9: Implement haptic and vibrate

**Files:**

- Modify: `../WebBridgeKit-Framework/Sources/Handlers/Device/WebHapticHandler.swift`
- Modify: `../WebBridgeKit-Framework/Sources/Handlers/Device/WebVibrateHandler.swift`
- Modify: `../WebBridgeKit-Framework/Tests/HandlerTests/WebHapticHandlerTests.swift`
- Modify: `../WebBridgeKit-Framework/Tests/HandlerTests/WebVibrationHandlerTests.swift`
- Modify: `SuperApp/Sources/Services/DrelCapabilityRuntimePolicy.swift`

**Step 1: Write failing handler tests**

Cover:

1. Allowed haptic styles.
2. Invalid style fallback or rejection.
3. Maximum vibrate duration.
4. Repeated vibration prohibition beyond the bound.
5. Foreground-gesture requirement.
6. Revocation stops pending work.
7. Audit event emission without payload content.

**Step 2: Constrain the handlers**

Make `haptic` and `vibrate`:

- require a v2 declaration;
- accept only bounded parameters;
- execute only after product-policy approval;
- report cancellation cleanly;
- never run indefinitely.

**Step 3: Run focused tests**

```bash
cd ../WebBridgeKit-Framework
xcodebuild test \
  -workspace WebBridgeKit.xcworkspace \
  -scheme HandlerTests-Part1 \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:HandlerTests-Part1/WebHapticHandlerTests
xcodebuild test \
  -workspace WebBridgeKit.xcworkspace \
  -scheme HandlerTests-Part2 \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:HandlerTests-Part2/WebVibrationHandlerTests
```

**Step 4: Commit**

```bash
git add Sources/Handlers/Device/WebHapticHandler.swift \
  Sources/Handlers/Device/WebVibrateHandler.swift \
  Tests/HandlerTests/WebHapticHandlerTests.swift \
  Tests/HandlerTests/WebVibrationHandlerTests.swift
git commit -m "feat(feedback): bound haptic and vibrate actions"
```

---

## Task 10: Implement system share

**Files:**

- Modify: `../WebBridgeKit-Framework/Sources/Handlers/Interaction/WebShareHandler.swift`
- Modify: `../WebBridgeKit-Framework/Tests/HandlerTests/WebShareHandlerTests.swift`
- Modify: `SuperApp/Sources/Services/DrelCapabilityRuntimePolicy.swift`
- Create: `SuperAppUITests/ShareCapabilityTests.swift`

**Step 1: Write failing tests**

Cover:

1. Valid outbound text and URL.
2. Missing text or URL rejection.
3. Oversized payload rejection.
4. User cancellation.
5. Successful completion.
6. No background share.
7. Audit records outcome but not content.

**Step 2: Redefine result semantics**

Resolve only after the user completes or cancels the share sheet. Do not resolve
merely because the sheet was presented.

**Step 3: Run tests**

```bash
cd ../WebBridgeKit-Framework
xcodebuild test \
  -workspace WebBridgeKit.xcworkspace \
  -scheme HandlerTests-Part2 \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:HandlerTests-Part2/WebShareHandlerTests
```

Drel:

```bash
xcodebuild test \
  -workspace Drel.xcworkspace \
  -scheme DrelUITests \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:DrelUITests/ShareCapabilityTests
```

**Step 4: Commit**

```bash
git add Sources/Handlers/Interaction/WebShareHandler.swift \
  Tests/HandlerTests/WebShareHandlerTests.swift
git commit -m "feat(share): expose bounded system share action"
```

Drel:

```bash
git add SuperApp/Sources/Services/DrelCapabilityRuntimePolicy.swift SuperAppUITests/ShareCapabilityTests.swift
git commit -m "test(app): cover Drel share capability flow"
```

---

## Task 11: Implement scan-only camera

**Blocked:** the first 1.5.0 review train excludes the camera permission. Do
not execute this task until the owner separately authorizes a later 1.5.x
scan-only camera release.

**Files:**

- Modify: `../WebBridgeKit-Framework/Sources/Handlers/Interaction/WebScanHandler.swift`
- Modify: `../WebBridgeKit-Framework/Sources/Controllers/QRScannerViewController.swift`
- Modify: `../WebBridgeKit-Framework/Tests/HandlerTests/WebScanHandlerTests.swift`
- Create: `SuperApp/Sources/Controllers/Capabilities/DrelScanViewController.swift`
- Create: `SuperAppUITests/ScanCapabilityTests.swift`
- Modify: `SuperApp/Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `SuperApp/Resources/en.lproj/Localizable.strings`
- Modify: `SuperApp/Sources/Info.plist`

**Step 1: Define the scan contract**

Decide and record:

- allowed code formats;
- maximum returned value length;
- timeout;
- cancellation behavior;
- whether multiple scans are allowed in one `appSession`.

Initial recommendation:

- QR only;
- one scan per request;
- 60-second timeout;
- cancel returns a user-cancelled error;
- no frames, images, or video are persisted or uploaded.

**Step 2: Write failing tests**

Cover:

1. Camera permission not determined.
2. Camera permission granted.
3. Camera permission denied and Settings recovery.
4. Successful scan.
5. Cancel.
6. Timeout.
7. Revocation while scanner is active.
8. App backgrounding stops capture.
9. Audit does not contain scanned value.
10. `scan` cannot satisfy camera, torch, or video.

**Step 3: Build the Drel-owned scanner**

Use a Drel foreground view controller, not a generic SDK-only screen. It must:

- show app name, origin, action, and signed purpose;
- require a foreground gesture;
- stop the session on disappear, revoke, or background;
- return only the scanned value and stable metadata.

**Step 4: Update usage strings and localization**

The camera usage description must say scan-only use and must not imply general
photo or video capture.

**Step 5: Run simulator and device tests**

Framework:

```bash
cd ../WebBridgeKit-Framework
xcodebuild test \
  -workspace WebBridgeKit.xcworkspace \
  -scheme HandlerTests-Part2 \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:HandlerTests-Part2/WebScanHandlerTests
```

Simulator:

```bash
xcodebuild test \
  -workspace Drel.xcworkspace \
  -scheme DrelUITests \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:DrelUITests/ScanCapabilityTests
```

```bash
xcodebuild test \
  -workspace Drel.xcworkspace \
  -scheme DrelUITests \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:DrelUITests/ScanCapabilityTests
```

Physical device:

- first-use iOS camera prompt;
- deny flow;
- Settings recovery;
- successful scan;
- cancel;
- revoke while active;
- background and lock behavior.

**Step 6: Commit**

Framework:

```bash
git add Sources/Handlers/Interaction/WebScanHandler.swift \
  Sources/Controllers/QRScannerViewController.swift \
  Tests/HandlerTests/WebScanHandlerTests.swift
git commit -m "feat(scan): bound camera use to foreground scanning"
```

Drel:

```bash
git add SuperApp/Sources/Controllers/Capabilities/DrelScanViewController.swift \
  SuperAppUITests/ScanCapabilityTests.swift \
  SuperApp/Resources/zh-Hans.lproj/Localizable.strings \
  SuperApp/Resources/en.lproj/Localizable.strings \
  SuperApp/Sources/Info.plist
git commit -m "feat(scan): add Drel-owned scan-only camera flow"
```

---

## Task 12: Add permission review, audit history, and revocation

**Files:**

- Create: `SuperApp/Sources/Models/DrelCapabilityAuditEvent.swift`
- Create: `SuperApp/Sources/Services/DrelCapabilityAuditStore.swift`
- Modify: `SuperApp/Sources/Controllers/Settings/PWAPermissionCenterViewController.swift`
- Modify: `SuperApp/Sources/Views/Settings/WebOriginGrantsView.swift`
- Create: `DrelTests/DrelCapabilityAuditStoreTests.swift`
- Create: `SuperAppUITests/CapabilityPermissionCenterTests.swift`

**Step 1: Write failing audit tests**

Cover:

1. Prompt shown.
2. User decision and selected scope.
3. System authorization result.
4. Denied request.
5. Successful execution.
6. Revocation.
7. Session expiry.
8. Manifest update removing an action.
9. Redaction of payload and scanned value.
10. Age and count pruning.

**Step 2: Implement the store**

Persist only:

- event type;
- action;
- capability family;
- purpose ID;
- subject identity;
- timestamp;
- bounded outcome.

Do not store share content, scanned values, or action payloads.

**Step 3: Extend the permission UI**

Show:

- current grants;
- signed purpose;
- origin;
- action;
- scope;
- revoke control;
- local audit history.

**Step 4: Run tests**

```bash
xcodebuild test \
  -workspace Drel.xcworkspace \
  -scheme Drel \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:DrelTests/DrelCapabilityAuditStoreTests
xcodebuild test \
  -workspace Drel.xcworkspace \
  -scheme DrelUITests \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:DrelUITests/CapabilityPermissionCenterTests
```

**Step 5: Commit**

```bash
git add SuperApp/Sources/Models/DrelCapabilityAuditEvent.swift \
  SuperApp/Sources/Services/DrelCapabilityAuditStore.swift \
  SuperApp/Sources/Controllers/Settings/PWAPermissionCenterViewController.swift \
  SuperApp/Sources/Views/Settings/WebOriginGrantsView.swift \
  DrelTests/DrelCapabilityAuditStoreTests.swift \
  SuperAppUITests/CapabilityPermissionCenterTests.swift
git commit -m "feat(permissions): add local capability audit and revocation"
```

---

## Task 13: Write developer documentation and the App Review package

**Files:**

- Create: `docs/api/drel-capabilities-v2.md`
- Create: `docs/guides/drel-controlled-capabilities.md`
- Modify: `skills/drel-app-development/SKILL.md`
- Modify: `skills/drel-app-development/references/web-app-manifest.md`
- Create: `docs/release/drel-1-5-0-review-notes.md`
- Create: `docs/release/drel-1-5-0-privacy-disclosure.md`
- Create: `test_resources/capabilities-v2/demo-app.json`
- Create: `docs/testing/results/drel-1-5-0-app-review-recording.md`

**Step 1: Document only the enabled actions**

Do not describe the broader SDK handler registry as available to Drel apps.

**Step 2: Document manifest v2**

Include:

- action allowlist;
- origin rules;
- purpose ID and purpose text rules;
- scope rules;
- signature coverage;
- offline package exclusion;
- sample JSON.

**Step 3: Prepare privacy and review material**

Cover:

1. Exact data flow for each action.
2. Scan-only camera semantics.
3. Statement that Drel does not collect scan data for its own account.
4. Signed demo app and deterministic manifest.
5. Review video script:
   - manifest import and activation;
   - first-use prompt;
   - denial and Settings recovery;
   - successful bounded execution;
   - permission review and revoke;
   - ordinary webpage remaining bridge-disabled.
6. Explicit statement that Drel has no generic or remotely extensible Bridge.

**Step 4: Owner sign-off**

Record product-owner approval of security review, privacy disclosure, and App
Review narrative before creating any ASC version.

**Step 5: Commit**

```bash
git add docs/api/drel-capabilities-v2.md \
  docs/guides/drel-controlled-capabilities.md \
  skills/drel-app-development/SKILL.md \
  skills/drel-app-development/references/web-app-manifest.md \
  docs/release/drel-1-5-0-review-notes.md \
  docs/release/drel-1-5-0-privacy-disclosure.md \
  test_resources/capabilities-v2/demo-app.json \
  docs/testing/results/drel-1-5-0-app-review-recording.md
git commit -m "docs(capabilities): document Drel 1.5 controlled actions"
```

---

## Task 14: Create the 1.5.0 release train

**Files:**

- Modify: `project.yml`
- Modify: `tools/verify-drel-store-archive.sh`
- Modify: `tools/run-release-gate.sh`
- Create: `docs/release/drel-1-5-0-submission-checklist.md`

**Step 1: Add a separate 1.5 configuration**

Create a `Drel15Release` configuration and `Drel15Store` scheme. Do not reuse
or mutate `Drel14Release` / `Drel14Store`.

Set:

- `MARKETING_VERSION = 1.5.0`
- a new build number assigned only after ASC state is re-read;
- container-only host policy injection;
- no offline-package Bridge.

**Step 2: Extend the archive verifier**

Assert:

1. Only `haptic`, `vibrate`, `share`, and `scan` capability markers are present.
2. Excluded handler markers are absent from the Drel archive.
3. Offline package entrypoints report `Bridge=0`.
4. Ordinary webpage fixtures receive no bridge object.
5. Permission UI and audit markers are present.
6. No debug-only capability pages leak.

**Step 3: Run the full gate**

```bash
bash tools/run-release-gate.sh
bash tools/run-drel-app-webview-regression.sh
bash tools/verify-drel-store-archive.sh /tmp/drel-1-5-archive/Drel.xcarchive
```

**Step 4: Prepare TestFlight and device matrix**

Physical-device matrix:

- upgrade from 1.4.1;
- ordinary webpage no Bridge;
- offline package no Bridge;
- network-managed app v2 flow;
- haptic;
- vibrate;
- share;
- scan first prompt;
- scan deny and Settings recovery;
- scan revoke while active;
- audit history;
- push and deep link cannot authorize.

**Step 5: Owner release confirmation**

Only after all evidence is green:

1. owner confirms exact version and build;
2. ASC metadata and privacy answers match;
3. review notes and video match;
4. owner explicitly approves submission.

Do not submit from this plan without that separate confirmation.

**Step 6: Commit**

```bash
git add project.yml tools/verify-drel-store-archive.sh tools/run-release-gate.sh \
  docs/release/drel-1-5-0-submission-checklist.md
git commit -m "chore(release): prepare Drel 1.5.0 train"
```

---

## Rollback strategy

| Failure | Rollback |
| --- | --- |
| SDK policy extraction destabilizes framework | Revert framework policy commit; Drel keeps injecting the previous explicit override until the generic policy is fixed. |
| Manifest v2 signing breaks 1.4 manifests | Keep v2 parsing behind server feature flag; republish gateway with v1-only manifests. |
| Drel runtime policy blocks valid managed apps | Disable 1.5 action catalog and restore `Bridge=0` while keeping manifest v1 behavior. |
| Scan fails device validation | Ship 1.5.0 with haptic/vibrate/share only, or defer whole release; do not broaden camera semantics. |
| Audit store grows unbounded | Force pruning migration and disable action execution until store size is bounded. |
| App Review evidence incomplete | Defer submission; do not weaken privacy narrative or action scope. |

## Completion definition

Drel 1.5.0 is complete only when:

1. all residual ADR-0006 Phase 1 items are closed;
2. only the enabled 1.5.0 actions are available;
3. ordinary pages and offline packages remain `Bridge=0`;
4. all simulator, archive, and physical-device gates pass;
5. audit and revocation work end to end;
6. security, privacy, and App Review sign-offs are recorded;
7. the owner approves the exact build for submission.
