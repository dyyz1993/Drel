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
- Favorites capture icons: a fixed-budget LRU cache serves saved icons
  first, an undecodable-miss falls back to fetching the site's favicon,
  and a favorite whose URL matches a registered gateway app prefers the
  manifest's signed icon from the same cache the home screen uses; missing
  icons are backfilled and persisted. — Scope: `App` — Verified:
  `server-test` — Evidence:
  [docs/testing/results/drel-1-5-0-109-inbox-channel/verification.md](docs/testing/results/drel-1-5-0-109-inbox-channel/verification.md)
- The push address card wears the Drel product mark: the official channel
  keeps the standard blue-violet gradient while a self-hosted channel shows
  the same mark in a teal variant. — Scope: `App` — Verified: `simulator` —
  Evidence:
  [docs/testing/results/drel-1-5-0-110-brand-merge/verification.md](docs/testing/results/drel-1-5-0-110-brand-merge/verification.md)
- Scanning a self-hosted pairing code now binds the whole service at once:
  the same origin's gateway descriptor is fetched and saved automatically,
  so the gateway never needs a separate import. — Scope: `App` — Verified:
  `server-test` — Evidence:
  [docs/testing/results/drel-1-5-0-110-brand-merge/verification.md](docs/testing/results/drel-1-5-0-110-brand-merge/verification.md)
- The default-startup-app list matches the favorites row style, preferring
  each app's manifest-declared icon. — Scope: `App` — Verified:
  `simulator` — Evidence:
  [docs/testing/results/drel-1-5-0-110-brand-merge/verification.md](docs/testing/results/drel-1-5-0-110-brand-merge/verification.md)
- The official edge matches the retired Swift relay's wire semantics:
  passive pushes go out at apns-priority 5, a positive ttl becomes a capped
  apns-expiration, direct pushes carry no self-hosted tag, and unmatched
  paths answer a clean 404 after the legacy upstream was unbound. — Scope:
  `Push`, `Server` — Verified: `server-test` — Evidence:
  [docs/testing/results/drel-1-5-0-110-brand-merge/verification.md](docs/testing/results/drel-1-5-0-110-brand-merge/verification.md)
- Key-scoped private HTML app registration: a paired device key can
  register app manifests on the official gateway without the admin key.
  Private manifests never appear in anonymous catalog listings, are visible
  only through `GET /api/v1/html-apps?key=<deviceKey>`, shadow a same-id
  global manifest for the owning key only, and are capped at 20 per key.
  The app scopes its official-gateway catalog fetch with the device push
  identity, so private apps activate through the same on-demand push path
  as global ones. — Scope: `Gateway`, `App` — Verified: `server-test`,
  `simulator` — Evidence:
  [docs/testing/results/drel-1-5-0-119-keybind/verification.md](docs/testing/results/drel-1-5-0-119-keybind/verification.md)

### Changed

- The inbox presents one three-segment view — Unread (the default),
  Recent, Groups — replacing the previous display-mode control plus
  filter menu. — Scope: `App` — Verified: `simulator` — Evidence:
  [docs/testing/results/drel-1-5-0-109-inbox-channel/verification.md](docs/testing/results/drel-1-5-0-109-inbox-channel/verification.md)
- Tapping a notification banner switches the inbox view and the in-app
  sending context to the channel that delivered the message, then opens
  it. — Scope: `App` — Verified: `manual` — Evidence:
  [docs/testing/results/drel-1-5-0-109-inbox-channel/verification.md](docs/testing/results/drel-1-5-0-109-inbox-channel/verification.md)

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

- The app clears expired manifest records and the seeded development fixtures
  on launch, so an upgraded install no longer shows leftover Tetris, notes,
  news, and shop entries in Storage. The manifest store now actually consults
  its expiry predicate, and saves happen after the lock so cleanup cannot
  deadlock. — Scope: `App` — Verified: `simulator` — Evidence:
  [docs/testing/results/drel-1-5-0-113-cleanup/verification.md](docs/testing/results/drel-1-5-0-113-cleanup/verification.md)
- Store builds strip every bundled HTML fixture and fixture stylesheet. The
  six Drel 1.0 Bridge pages now live only on the website under their versioned
  `/test/bridge/v1/` path; the app had never loaded the bundle duplicates.
  — Scope: `App` — Verified: `simulator` — Evidence:
  [docs/testing/results/drel-1-5-0-113-cleanup/verification.md](docs/testing/results/drel-1-5-0-113-cleanup/verification.md)
- The action demo manifest now declares the location action with its actual
  wire name, `getLocation`, and the site gate verifies all seven declared
  actions so review testing cannot drift from the Store allowlist. —
  Scope: `Website` — Verified: `server-test` — Evidence:
  [docs/testing/results/drel-1-5-0-113-cleanup/verification.md](docs/testing/results/drel-1-5-0-113-cleanup/verification.md)
- Third-party approval submits now carry only the one-time ticket, request
  identifier, action, revision and structured values. The temporary approval
  identity screen, device key-pair and signed actor assertion were removed so
  any service can accept a Drel approval with just a short-lived ticket. —
  Scope: `App`, `Server` — Verified: `simulator` — Evidence:
  [docs/testing/results/drel-1-5-0-112-one-time-ticket/verification.md](docs/testing/results/drel-1-5-0-112-one-time-ticket/verification.md)
- Receiving multiple unread push notifications with URLs no longer triggers
  bulk automatic browser navigation on background import; only the single
  notification explicitly tapped by the user opens its destination. — Scope:
  `App`, `Push` — Verified: `simulator` — Evidence:
  [docs/testing/results/drel-1-5-0-111-batch-push-routing/verification.md](docs/testing/results/drel-1-5-0-111-batch-push-routing/verification.md)
- The message detail bottom navigation pill order places "Previous" on the
  left and "Next" on the right, matching standard reading and swipe directions.
  — Scope: `App` — Verified: `simulator` — Evidence:
  [docs/testing/results/drel-1-5-0-111-batch-push-routing/verification.md](docs/testing/results/drel-1-5-0-111-batch-push-routing/verification.md)
- The official inbox view again shows the official messages that the
  migration-window edge mistakenly tagged as self-hosted; genuine
  self-hosted relay messages remain scoped to their channel. — Scope:
  `App`, `Push` — Verified: `manual` — Evidence:
  [docs/testing/results/drel-1-5-0-109-inbox-channel/verification.md](docs/testing/results/drel-1-5-0-109-inbox-channel/verification.md)
- The in-app test send, address copy and ringtone try actions follow the
  selected push channel instead of always hitting the official server. —
  Scope: `App` — Verified: `simulator` — Evidence:
  [docs/testing/results/drel-1-5-0-108-channel-fixes/verification.md](docs/testing/results/drel-1-5-0-108-channel-fixes/verification.md)
- A test-send response that is HTTP 200 but not the push JSON is reported
  as a failure instead of "sent", so a misrouted gateway can no longer mask
  itself as success. — Scope: `App` — Verified: `manual` — Evidence:
  [docs/testing/results/drel-1-5-0-108-channel-fixes/verification.md](docs/testing/results/drel-1-5-0-108-channel-fixes/verification.md)
- Bark path pushes (`GET /<key>/<title>/<body>`) deliver instead of falling
  into the push-discovery document on the official edge. — Scope: `Push` —
  Verified: `server-test` — Evidence:
  [docs/testing/results/drel-1-5-0-108-channel-fixes/verification.md](docs/testing/results/drel-1-5-0-108-channel-fixes/verification.md)
- The notifications tab unread badge counts only the channel the inbox is
  viewing, while the app icon keeps the global count; both refresh the
  moment the channel switches. — Scope: `App` — Verified: `physical-device`
  — Evidence:
  [docs/testing/results/drel-1-5-0-108-channel-fixes/verification.md](docs/testing/results/drel-1-5-0-108-channel-fixes/verification.md)
- The self-hosted Go relay serves a one-time QR pairing page at
  `/self-hosted/pair`, so a deployment pairs with one scan instead of a
  manual API call. — Scope: `Server` — Verified: `server-test` — Evidence:
  [docs/testing/results/drel-1-5-0-108-channel-fixes/verification.md](docs/testing/results/drel-1-5-0-108-channel-fixes/verification.md)
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
- Opening an app from an inbox message detail now routes through the push
  catalog coordinator: the gateway manifest is fetched and the activation
  recorded before the app resolves and opens, so a first open no longer
  dead-ends with `应用未注册` when the local catalog has not synced yet.
  — Scope: `App` — Verified: `simulator` — Evidence:
  [docs/testing/results/drel-1-5-0-119-keybind/verification.md](docs/testing/results/drel-1-5-0-119-keybind/verification.md)

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
