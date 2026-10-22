# Changelog

All notable changes to Drel are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and Drel uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html) for
the marketing version plus a monotonically increasing build number for the
bundle version.

Each release line carries three pieces of evidence:

- **Scope** — which surface the change belongs to (`App`, `Gateway`, `Push`,
  `Bridge`, `Website`, `Server`).
- **Verified** — how the change was checked (`physical-device`, `simulator`,
  `server-test`, `manual`, `none`).
- **Evidence** — a link to the verification record under
  `docs/testing/results/` or `docs/release/`.

## Unreleased

Nothing yet.

## [1.5.0] — 2026-10-22

The Manifest v2 action runtime train. Drel 1.5.0 adds a narrowly scoped
declaration model for four low-impact native actions, a permission center for
reviewing and revoking grants, and a one-command permission regression gate.

### Added

- Declared native actions: trusted HTML apps can declare `haptic`,
  `vibrate`, `share` and `fullscreen` in an Ed25519-signed gateway manifest.
  A declaration is an allowlist, not a standing user grant. — Scope: `Bridge`
  — Verified: `physical-device` — Evidence:
  [docs/release/1.5.0/verification.md](docs/release/1.5.0/verification.md)
- Permission center: a single screen lists every active grant, shows the
  grant ledger diagnostics, and allows revoking a grant after an explicit
  confirmation. — Scope: `App` — Verified: `simulator` — Evidence:
  [docs/release/1.5.0/verification.md](docs/release/1.5.0/verification.md)
- Clipboard and location grants, a share icon, and an add-to-home-screen
  action in the app catalog. — Scope: `Bridge`, `App` — Verified:
  `simulator` — Evidence:
  [docs/release/1.5.0/verification.md](docs/release/1.5.0/verification.md)
- iPhone Home Screen guide: a two-step Safari flow that adds a web app to the
  Home Screen and hands the launch back to Drel. — Scope: `App` — Verified:
  `simulator` — Evidence:
  [docs/release/1.5.0/verification.md](docs/release/1.5.0/verification.md)
- One-command permission regression gate
  (`tools/run-drel-permission-regression.sh`) that produces a recording, a
  screenshot set and per-case animation artifacts. — Scope: `App`, `Website` —
  Verified: `simulator` — Evidence:
  [docs/testing/results/drel-permission-regression-README.md](docs/testing/results/drel-permission-regression-README.md)

### Changed

- The active gateway identity is synced at app launch, so a grant issued
  under one gateway is never evaluated against another gateway's manifest.
  — Scope: `App`, `Gateway` — Verified: `simulator` — Evidence:
  [docs/release/1.5.0/verification.md](docs/release/1.5.0/verification.md)
- The permission center is presented modally and closes with an explicit
  close button. — Scope: `App` — Verified: `simulator` — Evidence:
  [docs/release/1.5.0/verification.md](docs/release/1.5.0/verification.md)
- The action demo shares the app's own name and current URL instead of a
  fixed string. — Scope: `Website` — Verified: `simulator` — Evidence:
  [docs/release/1.5.0/verification.md](docs/release/1.5.0/verification.md)
- The gateway signs action-level capability declarations so a manifest can
  declare `haptic` for one origin without declaring every other action.
  — Scope: `Gateway` — Verified: `server-test` — Evidence:
  [docs/release/1.5.0/verification.md](docs/release/1.5.0/verification.md)
- The server enforces APNs payload and expiration limits. — Scope: `Server` —
  Verified: `server-test` — Evidence:
  [docs/release/1.5.0/verification.md](docs/release/1.5.0/verification.md)

### Fixed

- "Always allow" grants now survive an app relaunch. — Scope: `App` —
  Verified: `simulator` — Evidence:
  [docs/testing/results/drel-permission-flow-101/verification.md](docs/testing/results/drel-permission-flow-101/verification.md)
- Revoking a web grant asks for confirmation and the button keeps a tappable
  hit area. — Scope: `App` — Verified: `simulator` — Evidence:
  [docs/release/1.5.0/verification.md](docs/release/1.5.0/verification.md)
- The hosted `/launch/` handoff retries when its standalone page becomes
  visible again, so returning to the Home Screen web app can trigger the app
  URL without force-quitting Drel. — Scope: `Website` — Verified:
  `physical-device` — Evidence:
  [docs/release/1.5.0/verification.md](docs/release/1.5.0/verification.md)
- The TestFlight upload no longer aborts when `altool` exits non-zero, and a
  duplicate build upload is treated as success. — Scope: `Server` — Verified:
  `manual` — Evidence:
  [docs/release/1.5.0/verification.md](docs/release/1.5.0/verification.md)
- The TestFlight upload reads `processingState` correctly and no longer
  references an undefined `UPLOAD_JSON`. — Scope: `Server` — Verified:
  `manual` — Evidence:
  [docs/release/1.5.0/verification.md](docs/release/1.5.0/verification.md)
- Favorites visibility and the default startup app are restored in the store
  build. — Scope: `App` — Verified: `simulator` — Evidence:
  [docs/release/1.5.0/verification.md](docs/release/1.5.0/verification.md)
- Home navigation adapts to iOS scenes. — Scope: `App` — Verified:
  `simulator` — Evidence:
  [docs/release/1.5.0/verification.md](docs/release/1.5.0/verification.md)

### Security

- The Store build keeps only the four declared actions in the host allowlist;
  every other Bridge action is rejected before handler dispatch. Remote pages
  still receive no general JavaScript-to-native Bridge. — Scope: `Bridge` —
  Verified: `physical-device` — Evidence:
  [docs/release/1.5.0/verification.md](docs/release/1.5.0/verification.md)
- A manifest update that removes an action also drops the dependent grant
  identity; a legacy broad capability marker cannot authorize a v2 action.
  — Scope: `Bridge`, `App` — Verified: `simulator` — Evidence:
  [docs/release/1.5.0/verification.md](docs/release/1.5.0/verification.md)

### Known issues

- The real-device Safari add-to-Home-Screen path still needs a manual
  confirmation on the signed phone build. — Verified: `none`
- `testHomeTileLongPressShowsSettingsAndPhoneShortcutGuide` still asserts the
  retired single-step guide copy and must be updated to the two-step labels.
  — Verified: `none`

## [1.4.1] — 2026-10-18

Hotfix train for the 1.4 line. The marketing version and the 1.4.1 build
(89) stay frozen so the App Store record is never rewritten in place.

### Changed

- The website points at the split Drel and WebBridgeKit-Framework
  repositories, and adds the App Store destination and the Bark comparison
  guides. — Scope: `Website` — Verified: `manual` — Evidence:
  [docs/testing/results/drel-1.4.1-89-iphone-validation/README.md](docs/testing/results/drel-1.4.1-89-iphone-validation/README.md)

### Verified

- Physical iPhone walkthrough of push registration, favorites upgrade
  continuity, inbox rendering, offline app launch, deep-link parameter
  routing and real APNs banner delivery. — Scope: `App`, `Push` — Verified:
  `physical-device` — Evidence:
  [docs/testing/results/drel-1.4.1-89-iphone-validation/README.md](docs/testing/results/drel-1.4.1-89-iphone-validation/README.md)

## [1.4.0] — 2026-09-14

The first release with the trusted-HTML-app model, strong offline packages
and deep links.

### Added

- Favorites: save frequently used pages, pin and unpin with a full swipe, and
  reopen saved apps in fullscreen. — Scope: `App` — Verified:
  `physical-device` — Evidence:
  [docs/testing/results/drel-1.4.1-89-iphone-validation/README.md](docs/testing/results/drel-1.4.1-89-iphone-validation/README.md)
- Trusted HTML apps: import a gateway configuration you trust; app metadata
  comes from Ed25519-signed manifests with declared routes and optional
  offline packages. — Scope: `App`, `Gateway` — Verified: `physical-device` —
  Evidence:
  [docs/testing/results/drel-1.4.1-89-iphone-validation/README.md](docs/testing/results/drel-1.4.1-89-iphone-validation/README.md)
- Strong offline mode: app resources are verified with SHA-256 and stored
  locally so they launch without a network. — Scope: `App` — Verified:
  `physical-device` — Evidence:
  [docs/testing/results/drel-1.4.1-89-iphone-validation/README.md](docs/testing/results/drel-1.4.1-89-iphone-validation/README.md)
- Notification avatars: a push can include an HTTPS image URL shown as the
  sender avatar. — Scope: `App`, `Push` — Verified: `physical-device` —
  Evidence:
  [docs/testing/results/drel-1.4.1-89-iphone-validation/README.md](docs/testing/results/drel-1.4.1-89-iphone-validation/README.md)
- `drel://app` deep links: open a specific route in a registered trusted app.
  Arbitrary URL passthrough is not supported. — Scope: `App` — Verified:
  `physical-device` — Evidence:
  [docs/testing/results/drel-1.4.1-89-iphone-validation/README.md](docs/testing/results/drel-1.4.1-89-iphone-validation/README.md)

### Changed

- The Inbox gained clearer search, grouping, unread and pinned-message
  management. — Scope: `App` — Verified: `physical-device` — Evidence:
  [docs/testing/results/drel-1.4.1-89-iphone-validation/README.md](docs/testing/results/drel-1.4.1-89-iphone-validation/README.md)

### Security

- Remote pages receive no JavaScript-to-native Bridge. — Scope: `Bridge` —
  Verified: `physical-device` — Evidence:
  [docs/testing/results/drel-1.4.1-89-iphone-validation/README.md](docs/testing/results/drel-1.4.1-89-iphone-validation/README.md)

## [1.0.1] — 2026-08-20

### Fixed

- The default startup app is restored in the store build. — Scope: `App` —
  Verified: `simulator` — Evidence: `none`

[Unreleased]: https://github.com/dyyz1993/Drel/compare/v1.5.0...HEAD
[1.5.0]: https://github.com/dyyz1993/Drel/releases/tag/v1.5.0
[1.4.1]: https://github.com/dyyz1993/Drel/releases/tag/v1.4.1
[1.4.0]: https://github.com/dyyz1993/Drel/releases/tag/v1.4.0
[1.0.1]: https://github.com/dyyz1993/Drel/releases/tag/v1.0.1
