# Drel 1.5.0 build 129

Date: 2026-10-31

Build 129 ships the signed application catalog browser and the latest
sensor-fixture corrections accumulated after build 128.

## Included changes

- "我的应用 → 管理" now includes **浏览全部应用**.
- The catalog lists every signed app in the active gateway trust registry,
  including apps not yet activated on Home.
- App details expose the gateway, allowed origins, App ID, Ed25519 key ID,
  capabilities, scopes, routes, and offline policy.
- A catalog app can be opened without activation, or explicitly added to Home.
- Gyro fixture v6 follows the runtime `BarkBridge.callNative` contract and
  starts motion-sensor subscription from the start-game gesture.

## Verification

```text
Debug simulator build:       PASS
Drel15Release build:         PASS
PWAAppCatalogTests:          2/2 PASS
Design-system/repository gates: PASS
```

The catalog test observes all six currently signed apps, opens the trust
details, adds an app to Home, and verifies the new tile. A second test launches
an app directly from catalog details without adding it.

Evidence:
[drel-app-catalog-browser/verification.md](../../testing/results/drel-app-catalog-browser/verification.md)

The tag-triggered GitHub Actions run is the authoritative archive, signing,
TestFlight upload, and Apple processing-state proof for this build.

## TestFlight publication

```text
GitHub Actions run:  41176318146
Result:              PASS
Archive/signing:     PASS
Upload:              PASS
processingState:     VALID
internalBuildState:  IN_BETA_TESTING
```

The artifact upload step reported the account-level GitHub Actions artifact
quota warning, but archive, export, signing, TestFlight upload, and ASC
processing all completed successfully. The warning does not affect the
TestFlight binary.
