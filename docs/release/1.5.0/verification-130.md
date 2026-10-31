# Drel 1.5.0 build 130

Date: 2026-10-31

Build 130 makes the signed `sensors` managed action usable end-to-end, adds
simulator diagnostics and synthetic tilt to the gyro demo, and fixes return
navigation from the signed app catalog.

## Included changes

- The Drel 1.5 host allowlist now includes the signed `sensors` action, so
  Bridge calls reach `WebSensorsHandler` instead of being rejected before
  CoreMotion.
- Gyro demo v7 exposes a sensor diagnostics panel with page/app identity,
  BarkBridge availability, `callNative`/`receiveEvent`, accelerometer and
  gyroscope availability, call logs, event counts, and synthetic tilt.
- "浏览全部应用" restores the navigation bar and exposes a dedicated
  `返回我的应用` action. A web app opened from the catalog closes back to the
  catalog list; the back action returns to My Apps.
- The gyro resource manifest advances to version 7 and the signed parent
  manifest points at `bridge-gyro.v7.html`.

## Simulator verification

```text
Device:                       iPhone 13 QA, iOS 18.3.1 Simulator
GyroDebugTests:               1/1 PASS
PWAAppCatalogTests:           2/2 PASS
Combined UI assertion gate:   3/3 PASS
Drel15Release build:          BUILD SUCCEEDED
Design/repository CI lint:     PASS, 0 errors
V2 action policy:             PASS
Docs links:                   241 checked, all PASS
```

The diagnostics panel reported `accelerometer:false`, `gyroscope:false`, and
`events:0` in Simulator. The `sensors` call was not rejected by host policy,
proving dispatch reached the native layer. Synthetic right tilt advanced the
game score from 0 to 23; this validates the game loop but is not physical
sensor evidence.

## Published demo

```text
Entry:                  https://gyro.drel.app/bridge-gyro.v7.html
Entry SHA-256:          aff9567ff3b9064d139419f7ab22f43dfc763a248c37b2a7eed4d5a8c6fe6929
Entry size:             18329 bytes
Resource manifest SHA:  39b54def06c2cc7330251805385b3a43fd48483fe01d67840b1b28dc063060f3
Signed cache version:   7
Signed action:          sensors / gyro-tilt-steer / appSession
Signing key:            gw-2026-09-15
```

## TestFlight publication

Pending tag-triggered archive, signing, upload, and App Store Connect
processing.

## Physical-device acceptance

Pending TestFlight install. Required checks:

- The debug panel reports a live accelerometer stream and event count.
- Tilt controls the ship after calibration, without the host-policy rejection.
- Closing a catalog-launched app returns to the catalog list.
- `返回我的应用` returns to My Apps.
