# Drel Offline Diagnostics and VOT 0.4.10.3 Verification

Date: 2026-11-16

## Scope

Implemented release-path, local-only diagnostics for trusted HTML app opens, and repaired the Store container-only offline fallback path that could remain on `Load failed` when a local entrypoint did not become visible.

## Implementation Evidence

- Diagnostics now distinguish launch, package lookup, WebKit navigation, visible page state, online fallback, and API status.
- Records retain the Drel version/build, app ID, offline package version, resource-manifest digest prefix, controlled error domain/code, HTTP status, and actual online/offline source.
- Records are local-only, capped at 20 attempts and 96 KiB, with each attempt capped at 100 events.
- Settings exposes `离线应用诊断` in the normal preferences section; it is not part of the DEBUG-only developer tools.
- The diagnostics view supports app filtering, copy, and local clear.
- Store/container-only launches now carry an explicit online fallback URL instead of relying on Bridge payload fields.
- WebKit navigation failure and “navigation finished but key page content never became visible” both attempt one online fallback. If fallback is unavailable or also fails, the user gets `查看诊断` and `重试`.

## Privacy Verification

`ModelsTests/DrelOfflineDiagnosticsTests` passed 3/3:

- Query/fragment values, secrets, private path fragments, and arbitrary outcomes are stripped or replaced with controlled values.
- Unknown error domains become `controlled`; only domain and numeric code are retained.
- Only the latest 20 attempts are retained.

The simulator diagnostics file was additionally scanned and contained no `secret`, `password`, `authorization`, `cookie`, `token=`, query marker, host absolute path, or `/private/var` path.

## VOT Simulator Evidence

UI suite `OfflineVOTDiagnosticsTests` passed 4/4 on iPhone 16 Pro simulator (iOS 18.3.1):

1. Both identities opened their local VOT 0.4.10.3 packages:
   - `app.example.invalid`
   - `app.legacy.example.invalid`
   - Both rendered the VOT login shell, proving entrypoint, CSS, and JS execution rather than merely proving `didFinish`.
   - Diagnostics recorded `packageFound`, `navigationFinished`, and `pageReady` with source `offlinePackage`.
2. Delete → online open → redownload → terminate → relaunch → offline open all passed.
   - The missing-package attempt recorded `packageMissing` and source `online`.
3. A blank local entrypoint test passed.
   - Initial events: offline navigation finished, then page `keyElementMissing`/timeout.
   - Drel attempted online fallback once.
   - Final events: `fallbackSucceeded`, online `navigationFinished`, and online `pageReady`.
4. Authentication failure used a deliberately invalid VOT workspace token.
   - The app returned to the VOT login shell.
   - Diagnostics recorded `apiUnauthorized`, distinguishing invalid credentials from a network failure.
   - The test token was synthetic and was not written to the diagnostics report.

A separate real network-interruption run passed after the two packages were installed:

- Mac Wi-Fi was turned off only for the local simulator test and restored immediately afterwards.
- Both VOT identities still opened from `offlinePackage` and recorded `packageFound → navigationFinished → pageReady`.
- Post-run `networksetup -getairportpower en0` reported `On`, the default route returned to `en0`, and an HTTPS reachability check succeeded.

Commands:

```bash
xcodebuild test \
  -workspace Drel.xcworkspace \
  -scheme DrelUITests \
  -destination 'platform=iOS Simulator,id=DF7E7D35-D223-4D75-8DC1-E2B76F45A2B5' \
  -derivedDataPath /tmp/drel-offline-diag-dd \
  -only-testing:DrelUITests/OfflineVOTDiagnosticsTests

xcodebuild test \
  -workspace WebBridgeKit.xcworkspace \
  -scheme ModelsTests \
  -destination 'platform=iOS Simulator,id=4BB2045A-7C2C-4218-88A6-486C741DB03D' \
  -only-testing:ModelsTests/DrelOfflineDiagnosticsTests
```

## Build / Gate Evidence

- `Drel` Debug simulator build: PASS.
- `Drel15Store` simulator release build: PASS.
- Release binary contains `DrelOfflineDiagnostics`, `offlineDiagnostics.*` markers, and the injected diagnostics message handler.
- `tools/verify-drel-release-settings.sh`: 11 passed, 0 failed.
- `tools/verify-deliverable-boundaries.sh`: 7 passed, 0 failed.
- `tools/verify-release-no-debug.sh`: PASS, 0 leaked DEBUG markers.

## Physical Device Read-Only Evidence

Installed Drel: 1.5.4 (153). A read-only container inventory confirmed two distinct VOT package directories:

- `app.example.invalid`: version `0.4.10.3`, resource digest `296ef77c…c3a1e36`.
- `app.legacy.example.invalid`: version `0.4.9.14`, resource digest `86b0158f…9cd2d7f`.

Therefore, the presence of VOT files does not prove that both cards or both identities are on 0.4.10.3. The legacy identity remains on an older local package; any UI diagnosis must first identify which card/app ID was opened.

## Outstanding Gaps

- The physical device was not modified or overwritten; Drel 153 does not contain this new diagnostics implementation, so no real-device VOT failure record could be collected from it yet.
- Physical-device airplane-mode/lock-screen delivery remains real-device release evidence; the successful network-interruption result above was simulator-local.
- API success and non-401 server failures have implementation and unit-level sanitization, but the deterministic VOT E2E case covers the unauthorized path.
- Release/TestFlight packaging is not yet performed from this branch. Real-device validation requires a new Store build containing these changes.
