# Drel 1.5.1 build 135

Date: 2026-11-01

## Scope

UI-only release based on the source tagged `v1.5.0+134` (commit `668d2d8`).
This branch changes the release identity and release-gate expectations only.
It contains no microphone or `audioLevel` changes.

## Physical input

The owner accepted build 134 on a physical TestFlight device for the UI fixes
covered by this release.

## Local verification

- Framework source: `e2567ff` (`WebBridgeKit-Framework` clean worktree).
- `Drel15Release` iOS Simulator build, scheme `Drel15Store`: `BUILD SUCCEEDED`.
- SwiftLint: exit 0 with existing warnings.
- Design and repository lint: 18 passed, 0 failed.
- `tools/verify-drel-v2-action-policy.sh` for build 135: PASS.
- Source diff from `v1.5.0+134` contains only release identity, release scripts,
  and release documentation.

## Review posture

This version adds no new native action and no microphone capability. The
existing controlled-action review model remains unchanged.

## Status

- Pending: tag, TestFlight upload, ASC processing, and App Store submission.
