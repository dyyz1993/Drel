# Drel 1.5.0 (98): repeated Home Screen launch handoff

## Build and device

- Release gate: 16/16 passed (`build/reports/release-gate.md`).
- Archive: `/tmp/drel-1-5-0-build-98/Drel.xcarchive`, version 1.5.0 (98), development signed for the connected iPhone.
- Installed over 1.5.0 (97) on the iPhone 13 running iOS 18.7.3 with `xcrun devicectl`; device readback confirmed bundle `com.webbridgekit.superapp`, version 1.5.0, build 98.
- Drel launched on the phone; PUA READY observation showed the rendered home screen and app list.
- Crash scan after launch: 0 app crashes, 0 diagnostic reports.

## Handoff fix and remaining device check

- The hosted `/launch/` handoff retries when its standalone page becomes visible again, so returning to the Home Screen web app can trigger the app URL again without requiring the user to force-quit Drel. The updated page is deployed at `https://drel.app/launch/`.
- Simulator check passed for launching Drel Action Demo twice without force-quitting Drel.
- On the physical iPhone, manually confirm: tap the saved Home Screen icon, return to SpringBoard without force-quitting Drel, then tap the same icon again. Each tap should reopen the intended app in Drel.

## Distribution

- This build is installed directly with a development provisioning profile; it is not a TestFlight upload.
- TestFlight export could not authenticate because the cached Xcode App Store Connect account credentials are invalid. The TestFlight build remains 1.5.0 (97).

## Follow-up: stale install and design alignment

- After the first 98 install, device readback showed 1.5.0 (97), so the old Shortcuts alert came from the stale installation. Reinstalled the same 98 archive; readback is now 1.5.0 (98).
- Source 98 uses the Safari launch-page flow in `showPhoneHomeScreenGuide`; it no longer contains the old alert copy.
- Figma node `165:485` / sheet `165:440` still documents the retired Shortcuts flow and should be updated to the Safari launch-page flow.
- Simulator smoke on Drel15Release 98: launched twice and tapped an app tile both times; the app page opened. This is not a Home Screen shortcut validation.

## UX review fixes

- Updated the Safari Home Screen guide copy and controls after the UX review:
  step labels are now `复制 / Safari / 打开`; step 2’s primary action is `打开 Safari 入口页`, followed by `我已在 Safari 完成添加`; step 3 uses `我已添加，完成` and `还没添加？回到 Safari 步骤`; placeholder icon state explicitly says the icon is provisional and can be confirmed in Safari; copy now consistently uses “主屏幕” instead of “桌面”.
- UI tests updated for the new controls; `PWAPermissionTests` long-press guide and desktop-entry flow passed 2/2 on iOS 18.3 simulator.
- Evidence refreshed in `docs/design/home-screen-safari-flow/sim`: guide steps 1–3 now reflect the fixed copy. The real-device Safari add/reopen path still needs manual validation.

## Physical-device UX round fixes

- Step 1 no longer offers a manual copy button: the HTTPS entry URL is copied automatically when the guide opens, and the only primary action advances to Safari.
- Step progress cannot jump forward; later steps unlock only after passing the earlier step.
- Public `/launch/` page deployed and verified live (`https://drel.app/launch/`) with clearer install steps and a single primary action.
- Rebuilt and reinstalled 1.5.0 (98) on the connected iPhone after these changes; device readback confirmed build 98.
- Remaining validation: user walks the real Safari add-to-Home-Screen flow and verifies the new icon opens Drel.

## Two-step guide simplification

- Removed the standalone copy step. The guide now starts directly at “打开 Safari 入口页”, with the Safari share/add instructions visible on the same page.
- Page 1: primary `打开 Safari 入口页`, secondary `我已在 Safari 完成添加`; page 2: `完成` plus `还没添加？回到 Safari 步骤`.
- `PWAPermissionTests/testHomeShortcutGuideOpensDesktopEntry` passes with the two-step flow.
- Known test issue: `testHomeTileLongPressShowsSettingsAndPhoneShortcutGuide` still fails at the old assertion expecting a separate “在 Safari 中添加” heading that no longer exists on page 1; the assertion needs updating to the new two-step labels. Real-device flow unaffected.
