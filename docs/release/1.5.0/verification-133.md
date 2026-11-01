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

## TestFlight publication

- Tag: `v1.5.0+133`; Drel release commit: `44726dc3103ae8b7d5cf27d50ff43022f699667b`.
- GitHub Actions: [run 41268740776](https://github.com/dyyz1993/Drel/actions/runs/41268740776) — success.
- Runner framework checkout: `12819e1aa0249bcd55cc74961cf1dcc3459a46eb`.
- Signed archive, IPA export and Apple upload: succeeded.
- Apple processing state: `VALID`; internal beta state: `IN_BETA_TESTING`.
- Physical TestFlight installation and acceptance were not performed in this verification.

## Physical TestFlight check (2026-11-01)

- iPhone 13 via iPhone Mirroring: TestFlight list showed `1.5.0 (133)` and, after update, `打开`; Drel was opened from that row.
- Managed Action Demo: expanded/collapsed the edge capsule, opened the custom More panel, saw the link-copy success message, opened permissions and returned, dismissed the panel by tapping the backdrop, and used × to return Home.
- Ordinary browser: opened a previous ordinary HTTPS page from Recent Visits. Cache statistics opened without a crash; Bookmarks opened and returned; hiding the navigation bar exposed the edge control, More opened the custom panel, Bookmarks returned to the immersive browser, and Show Navigation Bar restored navigation.
- **Issue found:** with the ordinary navigation bar visible, selecting Hide Status Bar changed the menu item to Show Status Bar but the clock and indicators remained visible. An initial local fix did not change the actual status-bar display and was not retained; this remains open.
- This record does not claim physical coverage of all menu actions or the new changes under development.
