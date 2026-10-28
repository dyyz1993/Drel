# Drel 1.5.0 build 113

Date: 2026-10-29

Build 113 is the release candidate that carries the Store-package and
upgrade-residue cleanup made after build 112. Version and build metadata were
verified from the built simulator package.

## Package identity

```text
CFBundleShortVersionString = 1.5.0
CFBundleVersion = 113
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
```

The command log, exact paths, and remaining production prerequisites are in
[`docs/testing/results/drel-1-5-0-113-cleanup/verification.md`](../../testing/results/drel-1-5-0-113-cleanup/verification.md).

## Release state

This document proves the local release candidate only. It does not prove a
TestFlight upload, App Store Connect processing, signed production-gateway
availability, App Store review, or App Store release.
