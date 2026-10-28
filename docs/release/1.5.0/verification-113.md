# Drel 1.5.0 build 113

Date: 2026-10-29

Build 113 is the release candidate that carries the Store-package and
upgrade-residue cleanup made after build 112. It is processed as `VALID` in
App Store Connect and available in TestFlight.

## Package identity

```text
CFBundleShortVersionString = 1.5.0
CFBundleVersion = 113
TestFlight build ID = 957fd228-fc84-4947-b216-51df36b8fc95
IPA SHA-256 = 753c0707e48010c7ffb861aaf08988ae09a7ed981274418e637fd7d423711deb
```

## Local gates

```text
DrelTests:                 31/31 passed
Drel15Release build:       BUILD SUCCEEDED
Release package HTML:      0 files
Release fixture CSS:       0 files
ci-lint.sh:                18/18 passed
verify-release-notes.py:   PASS
verify-docs-links.py:      PASS
verify-drel-site.py:       PASS
Worker npm test:           42/42 passed
Store package HTML:        0 files
Store package fixture CSS: 0 files
```

The command log, exact paths, and remaining production prerequisites are in
[`docs/testing/results/drel-1-5-0-113-cleanup/verification.md`](../../testing/results/drel-1-5-0-113-cleanup/verification.md).

## Release state

The distribution signature is an Apple Distribution identity for team
`B45VZCNYU3`. The app has production APNs, communication notifications enabled,
and `get-task-allow=false`.

This document proves local gates and TestFlight processing. It does not prove
signed production-gateway availability, physical-device review exercise, App
Store review, or App Store release.
