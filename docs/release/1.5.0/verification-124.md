# Drel 1.5.0 build 124

Date: 2026-10-30

Build 124 is the third automated-release probe and includes the concurrent
home-badge styling commit `22491ac`.

## Build history

- `v1.5.0+122` requested `macos-15` because its tag predated the self-hosted
  workflow merge. No steps ran and nothing uploaded.
- `v1.5.0+123` reached `drel-m2max`; preflight, Pods, certificate import, and
  release identity passed, but signed archive creation failed.
- `v1.5.0+124` adds archive-log tail output and includes the green cloud badge
  styling so the next failed archive is diagnosable from the Actions log.

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
