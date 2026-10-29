# Drel 1.5.0 build 118

Date: 2026-10-29

Build 118 is the final 1.5.0 release candidate. It carries the corrected
signed-gateway behavior, canonical `getLocation` action, permission-ledger
cleanup, Store-package cleanup, and diagnostic fixes made after build 113.

## Package identity

```text
CFBundleShortVersionString = 1.5.0
CFBundleVersion = 118
TestFlight build ID = 1b65a4bd-2a15-42c2-a1ba-7bc4b3ee15e9
IPA SHA-256 = 143fedb85bd19ae6d637b185d34725a8598bd9e8441c304a6ef0bf7a6897504e
App Store version ID = 5f394085-1ddb-41f4-bef1-263ba39112a0
```

## Local and package gates

```text
DrelTests:                 31/31 passed
Release archive build:     118 / 1.5.0
Release package HTML:      0 files
Release fixture CSS:       0 files
```

The exact simulator, result-bundle counts, production-gateway checks, and
physical-device walkthrough are in
[`drel-1-5-0-118-verification.md`](../../testing/results/drel-1-5-0-118-verification/verification.md).

## Production dependency

The deployed Worker is `eb3bfe74-2b76-403f-8ba8-51a42c8a2ebc`. It returns the
official action-demo manifest from built-in storage, so the previous Durable
Object quota outage does not block the review demo.

The manifest reports `cache.version=3`, carries an Ed25519 signature under key
`gw-2026-09-15`, and declares exactly `haptic`, `vibrate`, `share`,
`fullscreen`, `clipboard`, `getLocation`, and `addToHomeScreen`.

## Physical-device result

iPhone 13 / iOS 18.7.3 installed through TestFlight as `1.5.0 (118)`. The
trusted Home tile loaded `Drel Action Demo` version 3. All seven declared
actions succeeded. An undeclared `camera` call was rejected by host policy.

The location permission ledger showed one grant (`location=always`). Revoking
it cleared the grant and the next `getLocation` call showed Drel's permission
prompt again. Re-authorizing it restored exactly one grant. The post-walkthrough
crash scan reported zero diagnostic reports and zero app crashes.

This proves the 118 TestFlight path on production infrastructure. It does not
predict Apple's review outcome or replace the eventual App Store release check.
