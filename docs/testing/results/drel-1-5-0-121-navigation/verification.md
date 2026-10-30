# Drel 1.5.0 build 121 — immersive navigation controls

Date: 2026-10-30

## Scope

Build 121 keeps the existing floating fullscreen controls but gives navigation
and closing distinct behaviors:

- `‹` collapses the floating control.
- `×` closes the immersive web app and returns to Drel Home.
- A left-edge rightward swipe returns through the page's history and never
  closes the immersive web app.

The route fixture also exposes full-document navigation, History API routing,
hash routing, and `history.replaceState` so the behavior can be reproduced.

## Simulator evidence

Device: `Tongbuview 17 Pro Fresh`, iOS 26.4.1. The latest debug build was
installed and launched with `--pwa-v2-actions`.

| Case | Observed after navigation | Left-edge swipe |
|---|---|---|
| A tag | `a-tag`, history=2 | returned to `首页` |
| `location.href` | `location-href` | returned to `首页` |
| `location.assign` | `location-assign` | returned to `首页` |
| `window.open(_self)` | `window-open` | returned to `首页` |
| `history.pushState` | `history-push` | returned to `首页` |
| hash route | `route=hash` | returned to `首页` |
| `history.replaceState` | `history-replace` | remained on the current route |

Closing was checked separately: from the immersive route page, expanding the
floating control and tapping `×` returned to Drel Home. The page did not remain
open and the control did not merely collapse.

## Artifacts

- `screenshots/route-history-lab.jpg` — route fixture with the expanded
  floating control.
- `screenshots/x-close-home.jpg` — Drel Home after tapping `×`.

## Commands and limitations

Verification used a simulator build plus direct simulator touch automation.
The full repository `xcodebuild` build completed successfully. The existing
focused XCUITest run hit a simulator accessibility-loading failure during this
session, so the route and edge-gesture matrix above was executed with direct
touch injection and accessibility-tree readback.
