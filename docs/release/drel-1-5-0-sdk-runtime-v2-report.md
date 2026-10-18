# Drel 1.5.0 SDK Runtime V2 Report

Date: 2026-10-18

Status: Runtime changes, simulator automation, cloud-signed Store export, and
TestFlight upload are complete. Build 1.5.0 (90) is processing-state `VALID`
and App Store eligible. No 1.4.1 state or App Review submission was changed.

## Product policy

- `haptic`, `vibrate`, `share`, and `fullscreen` require an exact signed Manifest v2 action
  declaration and a real foreground WebView gesture.
- These low-impact actions do not create or reuse a persistent per-app privacy
  grant. Manifest declarations are an action allowlist, not blanket user
  consent.
- `share` is user-triggered and presented by the native iOS share sheet on
  every invocation. The user reviews the payload and chooses its destination.
- `fullscreen` is limited to hiding the host navigation/status bars; the host
  exit control stays reachable, and no orientation or scrolling is changed.
- All other Bridge actions are rejected by the Drel 1.5 host allowlist. Camera
  scan, photo library, Bluetooth, microphone, sensors, and other data-bearing
  capabilities remain deferred.

## Implementation

1. Kept action-level grant identity and declaration-removal cleanup in the
   reusable runtime for future grant-based capabilities; these four low-impact
   actions do not write reusable grants.
2. The SDK checks the Drel host action allowlist before dispatching any native
   handler. The 1.5.0 host allowlist is exactly `haptic`, `vibrate`, `share`,
   and `fullscreen`.
3. V2 actions require a registered managed app, a declaration matching the
   exact action and origin, and a one-use native touch no older than 1.5s.
4. Added a separate `Drel15Store` / `Drel15Release` configuration for version
   1.5.0 build 90. `Drel14Release` remains version 1.4.1 build 89. The 1.5
   configuration excludes seeded development fixtures.
5. Updated the protocol and owner-decision documents to distinguish an action
   declaration from a user privacy permission.

## Automated evidence

| Gate | Result | Evidence |
|---|---:|---|
| SDK JSBridge regression | 6/6 gates passed; Core JSBridge tests passed | `../../../WebBridgeKit-Framework/build/reports/jsbridge-regression.md` |
| Drel WebView regression | 4/4 gates passed; 3 functional UI tests, V2 share UI test, and V2 fullscreen UI test passed | `../../build/reports/drel-app-webview-regression.md` |
| Manifest v2 signature tests | 7/7 passed | `../../build/reports/manifest-v2-server-tests.log` |
| Deliverable boundaries | 7/7 passed | `../../build/reports/deliverable-boundaries.log` |
| AppTemplate independent gate | 5/5 passed | `../../../WebBridgeKit-Framework/build/reports/template-gate.md` |
| SwiftLint / design lint | Passed | `../../build/reports/swiftlint.log`, `../../build/reports/design-lint.log` |
| Drel 1.5 host policy check | Passed | `../../tools/verify-drel-v2-action-policy.sh` |
| Drel release gate | 11 passed; App Store archive failed at profile entitlement validation | `../../build/reports/release-gate.md` |
| Crash scan | 0 current simulator crashes; clean iPhone 17 Pro ZoomTest simulator | `../../build/reports/crash-scan.log` |
| Store package validation | Apple validation succeeded with no errors | `/tmp/drel-1-5-0-90-export/Packaging.log` |
| TestFlight upload | Upload succeeded; delivery `d149fd76-6870-46f2-96b3-37c46ae281d5` | `../../build/reports/drel-1-5-0-build-90-status.log` |
| ASC build/group lookup | Build 90 is `VALID` and linked to 内部测试 | `../../build/reports/drel-1-5-0-build-90-asc.json` |

The UI regression verifies that a real tap opens the system share sheet without
showing Drel's separate permission prompt, and that fullscreen is gesture-bound,
shows the host exit affordance, and does not close the HTML app when exited.

## Screenshot

![iOS system share sheet from the V2 demo](../../build/reports/v2-runtime/screenshots/v2-share-system-sheet/A6F0E216-5E01-407A-B46A-5EE37AD1026B.png)

File: `../../build/reports/v2-runtime/screenshots/v2-share-system-sheet/A6F0E216-5E01-407A-B46A-5EE37AD1026B.png`

![Fullscreen demo with the native host exit control](../../build/reports/v2-runtime/screenshots/v2-fullscreen-host-exit-visible/v2-fullscreen-host-exit-visible.png)

File: `../../build/reports/v2-runtime/screenshots/v2-fullscreen-host-exit-visible/v2-fullscreen-host-exit-visible.png`

The screenshot is from an iOS 26.4.1 simulator running the local test fixture.
It shows the content preview and native per-share choices. It is not a
production gateway or physical-device approval.

## Distribution evidence

The checked-in manual profile is stale and lacks
`com.apple.developer.usernotifications.communication`, so the source archive's
first signing pass used the team development identity. The final export then
used Xcode automatic App Store signing to rebuild the main and NSE Store
profiles. This preserved the notification avatar entitlement without weakening
the app boundary.

Final exported package facts:

- Version/build: `1.5.0 (90)` for both the app and NSE.
- Signing: Apple Distribution, team `B45VZCNYU3`.
- Profiles: App Store production, `get-task-allow=false`.
- Entitlements: production APNs, Communication Notifications, and the shared
  app group.
- NSE dSYM contains `IconAvatarProcessor` symbols.
- IPA SHA-256:
  `d5ed64e1173d3ccc8c404433722b06a9446d60477d5be3fd461f5d86176e0f77`.
- Apple returned `USES-NON-EXEMPT-ENCRYPTION: false`.

Apple accepted the package and returned build state `VALID`. It emitted two
non-fatal warnings because linked SDK code references Bluetooth and location
APIs while the 1.5 Store build strips those purpose strings and the host
allowlist blocks those actions. This matches the intended first-submission
scope, but the warning should be reviewed before any broader distribution.

Archive and exported IPA are retained under `/tmp/drel-1-5-0-90-cloud/` and
`/tmp/drel-1-5-0-90-export/` for symbolication and exact-artifact review.

## Protected release state

- `Drel14Release` remains configured as `1.4.1 (89)`; no changes were made to
  its version, build, or signing policy.
- No App Store Connect version, metadata, build association, or review
  submission was created or changed for 1.4.1 or 1.5.0.
- `Drel15Store` is a separate 1.5.0 release configuration and uses the
  four-action host allowlist. The uploaded package is Apple Distribution
  signed; the development-signed intermediate archive was not uploaded.

## Current change inventory

- Framework source and tests are in the sibling `WebBridgeKit-Framework`
  repository; Drel source, test, release configuration, and this report are in
  the Drel repository.
- The implementation is committed in both repositories. Public release copy and
  reviewer-facing material are drafted in `drel-1-5-0-whats-new.md` and
  `drel-1-5-0-review-notes.md`; both remain pending owner approval and a
  production-gateway demo.
