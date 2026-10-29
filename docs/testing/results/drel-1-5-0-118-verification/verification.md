# Drel 1.5.0 (118) final verification

Date: 2026-10-29

Status: local tests, release-package inspection, production gateway, TestFlight
processing, physical-device walkthrough, and App Store submission passed. The
version is waiting for Apple review.

## Identity

```text
CFBundleShortVersionString = 1.5.0
CFBundleVersion = 118
ASC build ID = 1b65a4bd-2a15-42c2-a1ba-7bc4b3ee15e9
ASC state = VALID
Uploaded = 2026-10-28T18:45:31-07:00
IPA = /tmp/drel-118-export-10-29-0939/Drel.ipa
IPA SHA-256 = 143fedb85bd19ae6d637b185d34725a8598bd9e8441c304a6ef0bf7a6897504e
```

Commands:

```bash
ASC_KEY_ID=... ASC_ISSUER_ID=... bash tools/asc-api.sh build 118
shasum -a 256 /tmp/drel-118-export-10-29-0939/Drel.ipa
```

Observed:

```text
Build 118 | state= VALID | id= 1b65a4bd-2a15-42c2-a1ba-7bc4b3ee15e9
143fedb85bd19ae6d637b185d34725a8598bd9e8441c304a6ef0bf7a6897504e
```

## Local tests and package

```bash
xcodebuild test -workspace Drel.xcworkspace -scheme Drel \
  -configuration Debug \
  -destination 'id=6EDF218F-03A2-47BB-9515-068EA8C7475D' \
  -only-testing:DrelTests \
  -resultBundlePath /tmp/drel-118-xcresult-79289
xcrun xcresulttool get test-results summary \
  --path /tmp/drel-118-xcresult-79289
```

```text
exit=0
result=Passed
totalTestCount=31
passedTests=31
failedTests=0
skippedTests=0
```

The unencrypted archive product is
`/tmp/drel-1-5-0-build-118-10-29-0939.xcarchive/Products/Applications/Drel.app`.

```text
CFBundleShortVersionString = 1.5.0
CFBundleVersion = 118
HTML files = 0
Fixture CSS files = 0
```

## Production gateway

The Worker deployment `eb3bfe74-2b76-403f-8ba8-51a42c8a2ebc` serves the
official action demo from built-in signed data:

```text
URL = https://api.drel.app/api/v1/html-apps/dev.drel.action-demo
HTTP = 200
cache.version = 3
signature.algorithm = ed25519
signature.keyId = gw-2026-09-15
actions = haptic,vibrate,share,fullscreen,clipboard,getLocation,addToHomeScreen
```

The signature was independently verified with OpenSSL and the public key from
the gateway trust document. The review page
`https://drel.app/test/actions/v1/index.html` is deployed from website
deployment `e178a1e7.drel.pages.dev` and displays version 3.

## Physical-device walkthrough

Device: physical iPhone 13, iOS 18.7.3, TestFlight distribution.

```bash
xcrun devicectl device info apps \
  --device 00008110-000E39D62106801E \
  --bundle-id com.webbridgekit.superapp
```

Observed installed identity:

```json
{
  "bundleIdentifier": "com.webbridgekit.superapp",
  "bundleVersion": "118",
  "name": "Drel"
}
```

| Check | Result | Evidence |
|---|---|---|
| Trusted Home app | PASS | `Drel Action Demo`, application version 3 |
| Haptic | PASS | page returned `haptic: success` for style `medium` |
| Vibrate | PASS | page returned `vibrate: success` |
| Share | PASS | native iOS share sheet opened and closed |
| Fullscreen enter | PASS | page returned `fullscreen: true` |
| Fullscreen exit | PASS | page returned `fullscreen: false` |
| Clipboard | PASS | Drel prompt, approval, and page result |
| Location | PASS | coordinates returned to the page |
| Add to Drel Home | PASS | `alreadyPresent` result |
| Add to iPhone Home Screen | PASS | Safari guide was shown for user confirmation |
| Undeclared camera | PASS | rejected before dispatch by host policy |
| Permission ledger | PASS | exactly one `location=always` grant |
| Revoke and re-prompt | PASS | revoke cleared grant; next call prompted again |
| Crash scan | PASS | 0 diagnostic reports, 0 app crashes |

Screenshots:

- [Action demo version 3](iphone-118-action-demo-version-3.jpg)
- [Clipboard success](iphone-118-clipboard-success.jpg)
- [Share sheet](iphone-118-share-sheet.jpg)
- [Location prompt](iphone-118-location-permission-prompt.jpg)
- [Location success](iphone-118-location-success.jpg)
- [One location grant](iphone-118-permission-one-location-grant.jpg)
- [Fullscreen enter](iphone-118-fullscreen-enter.jpg)
- [Fullscreen exit](iphone-118-fullscreen-exit.jpg)
- [Camera rejected](iphone-118-camera-rejected.jpg)
- [ASC waiting for review](asc-118-waiting-for-review.png)

Crash command:

```bash
bash scripts/scan-crash-logs.sh --json
```

Observed:

```json
{"diagnostic_reports":0,"app_crash_logs":0,"total":0}
```

## Boundary

## App Store submission

Submitted at 2026-10-29 10:52 +08:00. The confirmation panel reported one
submitted item and a review window of up to 48 hours.

```bash
ASC_KEY_ID=... ASC_ISSUER_ID=... bash tools/asc-api.sh get \
  '/v1/appStoreVersions/5f394085-1ddb-41f4-bef1-263ba39112a0?fields%5BappStoreVersions%5D=versionString,appStoreState,releaseType,build&include=build,appStoreVersionSubmission'
```

Observed:

```text
versionString = 1.5.0
appStoreState = WAITING_FOR_REVIEW
releaseType = MANUAL
build = 118
submission id = 5f394085-1ddb-41f4-bef1-263ba39112a0
```

## Boundary

This is production TestFlight, production-gateway, and submitted-review
evidence. It does not claim Apple review approval, App Store availability, or
post-release rollout health.
