# Drel 1.5.0 SDK Runtime V2 Report

Date: 2026-10-18

Status: SDK runtime authorization now requires signed Manifest v2 action
declarations for the selected 1.5.0 actions. This report covers the current
SDK increment; product-facing demo screens and App Review copy remain later
tasks.

## Scope inventory

### Enabled in this SDK increment

| Action | Capability family | Authorization path | Allowed scope |
| --- | --- | --- | --- |
| `haptic` | `displayStatus` | Signed `capabilities_v2` declaration | `once` / `appSession` |
| `vibrate` | `displayStatus` | Signed `capabilities_v2` declaration | `once` / `appSession` |
| `share` | `share` | Signed `capabilities_v2` declaration | `once` / `appSession` |

### Explicitly not enabled

- `scan` and camera
- photo library
- Bluetooth
- microphone and speech
- motion sensors
- clipboard
- file import/export
- notifications
- generic device control
- remote or dynamically supplied actions

## Runtime behavior

1. A controlled action first resolves the active managed app ID and document origin.
2. The SDK looks up the exact `capabilities_v2` declaration by:
   - action;
   - canonical origin.
3. If no exact declaration exists, authorization is denied before any prompt.
4. A legacy broad `capabilities` entry cannot satisfy a controlled action.
5. The authorization request carries:
   - signed `purpose`;
   - signed `purposeId`;
   - signed scope.
6. The user-facing prompt displays the signed purpose, not a runtime-supplied reason.
7. Consent completion revalidates the declaration before a grant is written.
8. A grant is capped by declaration scope:
   - declaration `once` plus user `appSession` records `once`;
   - declaration `appSession` records `appSession`;
   - `always` is not representable in V2.
9. Existing grant scope is rechecked on each request. A grant broader or
   narrower than the current signed declaration is revoked and the request is
   denied instead of silently reusing stale authorization.

## Automated test evidence

Targeted test class:

```text
CoreTests/WebJavaScriptBridgeTests
```

Result:

```json
{
  "result": "Passed",
  "totalTestCount": 21,
  "passedTests": 21,
  "failedTests": 0,
  "environmentDescription": "CoreTests · Built with macOS 26.2"
}
```

Evidence file:

- `WebBridgeKit-Framework/build/reports/v2-runtime/webjavascriptbridge-summary.json`
- `WebBridgeKit-Framework/build/reports/v2-runtime/simulator-final.png`

New cases:

1. A manifest with only legacy `capabilities: [.share]` does not authorize the
   controlled `share` action.
2. A valid V2 declaration authorizes `share`.
3. The signed purpose is used for the permission request.
4. A user selecting `always` when the declaration says `appSession` receives an
   `appSession` grant.

Existing regression cases still pass for the legacy V1 authorization path.

## Verification screenshot

`simulator-final.png` records the simulator state after the passing targeted
test run. It is evidence that the simulator completed the test session; it is
not yet a product consent-screen demo.

## Commits

- `a38e12d feat(manifest): decode signed action declarations`
- `b84d454 feat(bridge): authorize signed v2 actions`

## Boundaries preserved

- Drel `Drel14Release` remains `1.4.1 (89)`.
- No App Store Connect access or mutation occurred.
- No 1.5.0 release configuration was created.
- No physical-device permissions were exercised.

## Remaining work

1. Add product-side fixture/demo HTML showing:
   - declaration missing;
   - signed purpose prompt;
   - deny;
   - revoke;
   - signed `appSession` reuse.
2. Capture user-facing screenshots of those demo states.
3. Extend Drel WebView regression to register the V2 fixture and run each
   action.
4. Add manifest-update removal tests that clear dependent grants.
5. Add local/page trust denial tests at the bridge level for all three actions.
6. Run full JSBridge, Drel WebView, and Drel release gates after the product
   demo layer is wired.
7. Prepare reviewer-facing copy explaining the three-action catalog and the
   absence of a generic Bridge.
