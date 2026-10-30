# Drel 1.5.0 build 120

Date: 2026-10-30

Build 120 opens the `sensors` managed action (eighth container action) and
ships the calibration-hardened gyro games at versioned URLs.

## Package identity

```text
CFBundleShortVersionString = 1.5.0
CFBundleVersion = 120
TestFlight build ID = 632df18b-db6b-49ad-984e-29c00787c0b9
IPA SHA-256 = 12e6781b73f67b72fc197fd792809b71c8b9dd7a798850da385c3de61bb62bf1
```

## What changed

- `sensors` becomes a controlled action (display class: signed declaration
  alone gates access, no consent panel, no Info.plist key); the native
  accelerometer/gyroscope subscription handler was already present.
- The gyro games moved to versioned filenames (`web-gyro.v4.html`,
  `bridge-gyro.v4.html`) because `returnCacheDataElseLoad` ignores
  `must-revalidate`, so in-place HTML edits never reached devices
  (LRN-20261030-009).
- The bridge game uses the subscription protocol with variance-gated
  calibration; both games share one core with touch fallback and live
  sensor readouts.

## Local and package gates

```text
DrelTests:                 35/35 passed (build 119 cycle)
Simulator build:           green
Activation gates:          dev.gyro.web / dev.gyro.offline 2×2 passed
Worker unit tests:         51/51 (server 2026.10.30-canonical)
Release gates:             release-notes / docs-links / hygiene / identity passed
```

Real-device outcomes for the sensor comparison are pending; the expected
matrix is recorded in
[`drel-gyro-sensors/verification.md`](../../testing/results/drel-gyro-sensors/verification.md).
