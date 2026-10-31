# Drel 1.5.0 build 131

Date: 2026-11-01

Build 131 promotes motion sensors from declaration-only access to an explicit,
revocable WebBridgeKit grant.

## Included changes

- `sensors` now requires the branded Drel consent prompt before Bridge
  dispatch. The user may choose "允许一次" or "始终允许".
- A persistent motion grant is listed in the per-app permission center and can
  be revoked with the existing confirmation flow.
- Revocation calls `WebSensorsHandler.htmlAppCapabilityDidRevoke()`, which
  immediately stops accelerometer and gyroscope updates and emits
  `onSensorsAccessRevoked`.
- Manifest validation now treats `sensors` like clipboard/location: the signed
  declaration must use `scope=always`.
- Gyro demo v9 documents the grant boundary and handles the revocation event by
  returning to touch fallback.

## Published demo and gateway

```text
Entry:                  https://gyro.drel.app/bridge-gyro.v9.html
Entry SHA-256:          5c2b020bd96d267573a975acbdf20a877bf572697bc8eaa137f607f3523e2421
Entry size:             18675 bytes
Web manifest SHA-256:   603a48d35410fd4c23ba6c857cbdad3f94ec5e3f0a3ad81c059c95ab83931615
Signed cache version:   9
Signed action:          sensors / gyro-tilt-steer / always
Gateway readback:       HTTP 200; Ed25519 key gw-2026-09-15
Worker asset version:   cfd372a0-a8ed-4d6c-a00c-994cebabdf50
```

## Verification

```text
Framework policy grant test:        PASS
  PermissionGrantPersistenceTests/
  testSensorsRequiresBrandedGrantAndPersistsAlwaysApproval
Sensor handler tests:               10/10 PASS
  includes revocation stop/stream flags/event
Server manifest tests:              9/9 PASS
Gyro v9 simulator UI test:          1/1 PASS
  grant prompt -> always -> native dispatch -> synthetic game
Drel15Release build:                BUILD SUCCEEDED
SwiftLint:                          exit 0 (existing warnings only)
V2 action policy:                   PASS
App Store metadata JSON:            PASS
Crash scan after UI test:           total 0
```

The Simulator has no accelerometer stream. The UI test proves branded grant
dispatch and the game/touch fallback; physical tilt remains covered by the
build 130 real-device result and should be repeated after TestFlight
processing if needed.

## Release evidence

```text
Tag:              v1.5.0+131
Release commit:   FILLED_BY_RELEASE
Actions run:      FILLED_BY_RELEASE
ASC build state:  FILLED_BY_RELEASE
```
