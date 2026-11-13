# Drel 1.5.4 Build 147 Release Verification

Verified: 2026-11-13

## Change

- `UNUserNotificationCenter.didReceive` now marks a non-copy notification tap
  as an explicit launch destination before routing.
- `drel://app` external launches mark the same destination before resolving.
- The delayed recent-session restore requires no current browser, no explicit
  destination, and a restorable URL.

## Simulator gate

- Store scheme source build required after the lifecycle patch.
- Physical acceptance must force-quit Drel and tap a structured VOT push; the
  expected result is one immersive destination and no delayed normal page.
