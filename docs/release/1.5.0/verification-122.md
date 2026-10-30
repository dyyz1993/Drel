# Drel 1.5.0 build 122

Date: 2026-10-30

Build 122 is the automated-release verification build after the Drel self-hosted
GitHub Actions runner was connected.

## What changed

- Home app badges show offline capability before installation and switch to a
  solid green cloud after the package is installed.
- The collapsed immersive control exposes 20pt at the screen edge instead of
  30pt, while retaining its arrow and enlarged tap target.

## Verification

- Framework immersive-control layout test: PASS.
- Drel immersive fullscreen UI regression: PASS, with a 20pt frame assertion.
- Evidence:
  [drel-1-5-0-122-immersive-inset/verification.md](../../testing/results/drel-1-5-0-122-immersive-inset/verification.md)

This document verifies the candidate before tagging. The tag-triggered GitHub
Actions run supplies the archive, signing, TestFlight upload, and Apple
processing-state evidence.
