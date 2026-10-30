# Drel 1.5.0 build 128

Date: 2026-10-30

Build 128 adds the immersive route matrix to the public Action Demo and bumps
that signed demo to version 4 so TestFlight can verify navigation on the same
trusted app used for review.

## Demo changes

- `test_resources/action-demo/v1/index.html` now includes A-tag, full-document,
  History API, and hash navigation cases.
- The route label reports the active route and `history.length`.
- The Action Demo gateway manifest cache version changes from 3 to 4.

## Verification

- The website build and link check must pass before tagging.
- TestFlight physical-device acceptance is pending for build 128.

The physical matrix must cover collapse, re-expand, `×` close, left-edge
returns for A tag, `location.href`, `location.assign`, `window.open(_self)`,
`history.pushState`, and hash; `history.replaceState` must remain on the
current route.
