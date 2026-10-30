# Drel 1.5.0 build 125

Date: 2026-10-30

Build 125 fixes the Release archive failure exposed by build 124.

## Build history

- `v1.5.0+122` predated the self-hosted workflow and did not start.
- `v1.5.0+123` reached the runner but failed in signed archive creation before
  the failure log was surfaced.
- `v1.5.0+124` surfaced the root cause from `archive-124.log`:
  `PWAHomeView.swift` exceeded the Swift compiler's expression type-check
  budget around the offline cloud-download badge.
- `v1.5.0+125` extracts the installed and available offline badges into small
  dedicated SwiftUI fragments, removing the long chained expression.

## Included app changes

- Home app badges use cloud icons for offline capability and installation
  state, with a green cloud after installation.
- The collapsed immersive control exposes 20pt at the screen edge instead of
  30pt, while retaining its arrow and enlarged tap target.

## Verification

- Release notes, documentation links, repository hygiene, design lint, Go
  server tests, Cloudflare Worker tests, website assets, and diagram checks
  pass locally.
- Framework immersive-control layout test: PASS.
- Drel immersive fullscreen UI regression: PASS, with a 20pt frame assertion.
- Evidence:
  [drel-1-5-0-122-immersive-inset/verification.md](../../testing/results/drel-1-5-0-122-immersive-inset/verification.md)

The tag-triggered GitHub Actions run is the authoritative archive, signing,
TestFlight upload, and Apple processing-state test for this build.
