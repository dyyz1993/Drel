# Drel signed app catalog browser

Date: 2026-10-31

## Scope

The "我的应用" management sheet now includes **浏览全部应用**. The browser
lists every app in the active gateway's signed trust registry, instead of only
the apps already activated on the Home screen.

Each row exposes:

- app name, icon, source host, and manifest version
- Home activation state
- declared Bridge capability summary

The detail sheet shows:

- active gateway name
- allowed source origins
- App ID and signed entry URL
- Ed25519 algorithm and signing-key ID
- declared capability purpose and scope
- allowed routes and offline policy

From the detail sheet the user can:

- open the signed app without adding it to Home
- explicitly add the app to Home

## Trust and state boundaries

- Only manifests with a signature are listed.
- Catalog refresh uses the same `HTMLAppGatewayOnboardingService` validation
  and activation path as the active gateway; it does not merge unsigned local
  manifests into the product catalog.
- Opening an app does not activate it.
- Adding an app writes only its stable App ID to
  `HTMLAppPushActivationStore`, so the current signed manifest remains the
  source of name, icon, routes, capabilities, and offline metadata.

## Verification

Simulator: `Drel R22 Width Verify`, iOS 27.1.

```text
Debug simulator build:       PASS
Drel15Release build:         PASS
PWAAppCatalogTests:          2/2 PASS
```

Test cases:

1. `testSignedCatalogListsAppsAndShowsTrustDetails`
   - opens the manage sheet
   - enters "浏览全部应用"
   - observes all six signed catalog apps
   - opens the source/signature/capability/routes detail
   - adds Drel Data Template to Home and verifies the new tile
2. `testSignedCatalogOpensAppWithoutAddingToHome`
   - opens Drel Data Template directly from catalog detail
   - verifies the immersive browser and WebView launch without an activation
     step

## Artifacts

- Catalog list（截图保留在内部记录）
- Trust and capability detail（截图保留在内部记录）
- Added to Home（截图保留在内部记录）
- Opened without adding（截图保留在内部记录）

## Source

- `SuperApp/Sources/Views/PWAHome/PWAAppCatalogView.swift`
- `SuperApp/Sources/Controllers/Settings/PWAAppCenterViewController.swift`
- `SuperAppUITests/PWAAppCatalogTests.swift`
