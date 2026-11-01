# Drel 1.5.0 build 134

Date: 2026-11-01

## Changes

- Route ordinary-browser status-bar visibility through the app's tab and navigation containers.
- Collapse the edge capsule when the immersive function panel opens.
- Unify short feedback through the shared HUD, with semantic icon colors and a compact appearance; retain blocking behavior for loading/progress only.
- Framework revision: `e2567ff`.

## Simulator verification

- Ordinary browser: status bar visible and hidden on the same loaded page while retaining the navigation bar; screenshots visually checked. Menu regression: 1/1 PASS (`/tmp/drel-status-repair2.xcresult`).
- Managed and ordinary immersive panel tests: 2/2 PASS (`/tmp/drel-toast-final-v4.xcresult`); managed follow-up 1/1 PASS (`/tmp/drel-toast-last.xcresult`).
- `Drel15Release` simulator build: BUILD SUCCEEDED.
- Design and repository lint: 18 passed, 0 failed; SwiftLint exit 0 with existing warnings.
- `tools/verify-drel-v2-action-policy.sh`: PASS.
- The screenshots and tests above are simulator evidence; physical TestFlight verification remains outstanding.
