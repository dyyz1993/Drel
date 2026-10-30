# Drel 1.5.0 build 121

Date: 2026-10-30

Build 121 refines immersive web-app navigation by separating toolbar collapse,
page closing, and page-history navigation.

## What changed

- The `‹` control only collapses the floating toolbar.
- `×` closes the immersive web app and returns to Drel Home.
- A left-edge rightward swipe navigates page history and never exits the app.
- The behavior is implemented for both WebBridgeKit browser host variants and
  covers full-document routes, History API routes, hash routes, and
  `history.replaceState`.

## Verification

The complete route matrix and simulator evidence are recorded in
[`drel-1-5-0-121-navigation/verification.md`](../../testing/results/drel-1-5-0-121-navigation/verification.md).

```text
Simulator build:          green
Route/back matrix:        7/7 observed as expected
Explicit × close:         returned to Drel Home
```
