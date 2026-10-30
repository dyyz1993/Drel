# Drel 1.5.0 build 123

Date: 2026-10-30

Build 123 retries the automated-release verification after build 122 exposed a
workflow-version mismatch.

## Why 123

The `v1.5.0+122` tag was created from the app branch before the self-hosted
runner workflow was merged from `main`. Its GitHub Actions job therefore still
requested `macos-15`, failed before any steps ran, and did not upload a build.
The tag was left immutable.

Build 123 includes the self-hosted runner workflow, setup-action tool fixes,
secret-backed release configuration, and the app changes from 122.

## What changed

- Home app badges show offline capability before installation and switch to a
  solid green cloud after the package is installed.
- The collapsed immersive control exposes 20pt at the screen edge instead of
  30pt, while retaining its arrow and enlarged tap target.

## Verification

- Release notes, documentation links, repository hygiene, design lint, Go
  server tests, Cloudflare Worker tests, website assets, and diagram checks
  passed locally.
- Framework immersive-control layout test: PASS.
- Drel immersive fullscreen UI regression: PASS, with a 20pt frame assertion.
- Evidence:
  [drel-1-5-0-122-immersive-inset/verification.md](../../testing/results/drel-1-5-0-122-immersive-inset/verification.md)

The tag-triggered GitHub Actions run supplies the archive, signing, TestFlight
upload, and Apple processing-state evidence for this build.
