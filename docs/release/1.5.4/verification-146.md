# Drel 1.5.4 Build 146 Release Verification

Verified: 2026-11-13

## Scope

- Marketing version: `1.5.4`
- Build: `146`
- Fix: keep a push launch as the single explicit cold-start destination and
  preserve immersive presentation for trusted HTML apps.
- Source commit: recorded after final release commit.

## Simulator gate

- Drel153Store Debug simulator build passed with the navigation change.
- The changed launch paths cover `PushRouter`, default startup app, and
  recent-session restore.
- Physical push acceptance is still required after TestFlight processing.

## Required physical acceptance

1. Install build 146 from TestFlight.
2. Force-quit Drel, trigger a structured VOT push, tap it while Drel is cold,
   and verify one destination opens in immersive mode.
3. Repeat with a default startup app configured and a recent browser session
   available; verify neither opens underneath or after the push route.
4. Verify VOT navigation parameters reach the app and are cleared from the URL.
