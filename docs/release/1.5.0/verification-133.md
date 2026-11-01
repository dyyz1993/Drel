# Drel 1.5.0 build 133

Date: 2026-11-01

## Changes

- Replace the immersive More action sheet with a custom bottom function panel.
- Keep permission management in the panel and preserve ordinary-browser tools.
- Preserve the immersive browser controls when returning from bookmarks.
- Return unmanaged cache-statistics results to the main thread while saving separate Realm objects in the background.
- WebBridgeKit framework commit: `12819e1aa0249bcd55cc74961cf1dcc3459a46eb`.

## Simulator verification

- Managed immersive panel: open, dismiss by backdrop and swipe, and enter permissions — PASS, 1/1 (`/tmp/drel-133-final-ui3.xcresult`).
- Ordinary immersive browser: copy URL (clipboard checked), bookmarks and return, navigation and status bar toggles, cache statistics, and permission management — PASS, 1/1 (`/tmp/drel-133-final-ui3.xcresult`). The ordinary page permission entry is available in the Debug host; release policy determines its availability.
- `Drel15Release` simulator build: BUILD SUCCEEDED.
- `swiftlint --quiet` and framework changed-file lint: exit 0 (existing warnings in Drel).
- `tools/ci-lint.sh`: 18 passed, 0 failed.
- `tools/verify-drel-v2-action-policy.sh`: PASS.

These results are simulator evidence; they do not establish TestFlight or physical-device acceptance.
