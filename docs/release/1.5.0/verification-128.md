# Drel 1.5.0 build 128

Date: 2026-10-30

Build 128 carries two work streams: the immersive route matrix for the
public Action Demo, and the `sensors` managed action with the cloud
offline badges and the gyro-game experiment assets.

## Package identity

```text
CFBundleShortVersionString = 1.5.0
CFBundleVersion = 128
TestFlight build ID = 7f71ca24-77e4-4996-88cb-c65dc50cd0a5
IPA SHA-256 = 523a29df39faa364074760823bf7dc8db237dd7e3fb0e7eb7c1b1c3c4685003f
```

## Demo changes (immersive route matrix)

- `test_resources/action-demo/v1/index.html` now includes A-tag, full-document,
  History API, and hash navigation cases.
- The route label reports the active route and `history.length`.
- The Action Demo gateway manifest cache version changes from 3 to 4.

## App changes (sensors action + offline badges + gyro games)

- `sensors` becomes a controlled action (display class: signed declaration
  alone gates access, no consent panel, no Info.plist key); the native
  accelerometer/gyroscope subscription handler was already present.
- Home cards show the offline-capable cloud badge: gray cloud-download
  before install, solid green cloud after (user-designed states).
- App catalog browser ("浏览全部应用") lists registered apps with
  capabilities and origins.
- The gyro games moved to versioned filenames (`web-gyro.v4/v5.html`,
  `bridge-gyro.v4/v5.html`) because `returnCacheDataElseLoad` ignores
  `must-revalidate`, so in-place HTML edits never reached devices
  (LRN-20261030-009). The bridge game uses the subscription protocol with
  variance-gated calibration, started inside the start-game gesture.

## Verification

```text
DrelTests:                 35/35 (build 119 cycle)
Fresh-clone dual-repo build: green
swiftlint:                 0 errors
Worker unit tests:         51/51
Release gates:             notes / docs-links / hygiene / identity passed
Activation gates:          dev.gyro.web / dev.gyro.offline passed (v5)
```

Sensor comparison outcomes on the physical device are pending; the expected
matrix is recorded in
[`drel-gyro-sensors/verification.md`](../../testing/results/drel-gyro-sensors/verification.md).
