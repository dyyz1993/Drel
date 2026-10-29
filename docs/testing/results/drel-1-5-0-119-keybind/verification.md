# Drel 1.5.0 build 119 — key-scoped private registration verification

Date: 2026-10-29

Build 119 carries the key-scoped private HTML app registration feature
(FR-20261029-01) and the inbox app-open activation fix.

## Server (Worker `drel-api-proxy`, version `2026.10.29-keybind`)

```text
Worker unit tests:        50/50 passed (6 new key-binding cases)
Deployed version:         e9a18441-8a5f-49dc-884e-db2afcb4e4a7
Gateway contract gate:    5/5 passed
  (WBK_GATEWAY_URL=https://api.drel.app
   WBK_GATEWAY_APP_ID=dev.vot.workspace bash tools/verify-open-gateway.sh)
```

Live E2E against production with a real paired key:

1. `POST /api/v1/html-apps` with `deviceKey`, no admin key → 200, Ed25519
   signature over a document that does not contain `deviceKey`.
2. Anonymous `GET /api/v1/html-apps` does not list the private manifest.
3. `GET /api/v1/html-apps?key=<paired>` lists it; another key does not.
4. `POST` with an unpaired key → 404 `unknown deviceKey: pair the device
   before registering apps`.
5. `DELETE /api/v1/html-apps/<appId>?key=<paired>` → 204; the key-scoped
   listing no longer contains it. Test data was cleaned up after the run.

Guards: paired-key check against `OfficialPushRegistry` (skipped when the
binding is absent), per-key manifest limit of 20, private app-id shadowing
of a global manifest only for the owning key.

## App (simulator)

```text
DrelTests:                35/35 passed
  of which new:           DrelPushAppCatalogCoordinatorKeyScopeTests 4/4
Simulator build:          green (xcodebuild, Drel scheme, iphonesimulator arm64)
SwiftLint (changed files): no new warnings
```

The new unit tests cover: official gateway manifest path gains the current
key scope while identity fields stay unchanged and the scoped configuration
still passes `HTMLAppGatewayConfiguration.validate()` (query strings in
endpoint paths are now accepted); a stale scope is replaced with the current
key after regeneration; a non-official gateway is left unchanged; a missing
identity leaves the gateway unchanged.

Inbox fix verification: the message-detail app-open path now routes through
`DrelPushAppCatalogCoordinator.activateIfTrusted` before resolving, so a
manifest that arrives with the push no longer fails closed with
`应用未注册` from the inbox detail screen. Verified by build plus the
coordinator path assertion in unit tests; behavioral confirmation is listed
under Known boundaries below.

## Known boundaries

- Full private-app activation on a physical device (paired key → register →
  `?key=` fetch → push → tap → home card) closes with this TestFlight build;
  the simulator cannot pair with the official gateway because it has no APNs
  device token.
- The self-hosted Go gateway does not implement key-scoped manifests yet;
  the app intentionally does not inject `?key=` for non-official gateways.
