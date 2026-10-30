# Drel 1.5.0 build 126

Date: 2026-10-30

Build 126 retries the automated release after build 125 reached the signed
archive and failed only because the host ran out of disk space.

## Build history

- `v1.5.0+122` predated the self-hosted workflow and did not start.
- `v1.5.0+123` failed in signed archive creation before the failure log was
  surfaced.
- `v1.5.0+124` exposed the compiler type-check timeout in the offline badge
  expression.
- `v1.5.0+125` fixed that compiler failure but hit `errno=28` while writing
  the Realm archive on the runner host.
- `v1.5.0+126` is unchanged code with only rebuildable local build products
  cleaned up.

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
