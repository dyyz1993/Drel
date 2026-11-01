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

## TestFlight publication

- Tag: `v1.5.1+135`; release commit: `03f5bd3`.
- GitHub Actions: run `41304657541` — success.
- Framework source: `e2567ff` (`WebBridgeKit-Framework/main`).
- Signed archive, IPA export, and Apple upload succeeded.
- ASC build 135: `VALID`; build ID `06ae0adb-2763-469b-bb65-efdb7d0f286e`.

## App Store Connect preparation

- App Store version 1.5.1 ID: `4fac81a9-f0de-470a-a045-53d52a75d855`.
- Build 135 attached; version state: `PREPARE_FOR_SUBMISSION`.
- Manual release after approval.
- Simplified Chinese and English "What's New" copy and promotional text updated.
- Review notes updated to describe the UI-only release and unchanged action
  surface, explicitly excluding microphone/audio.
- Existing 6.1-inch and 6.5-inch screenshot sets are complete for both
  locales.
- Pending: final owner confirmation and App Review submission.
