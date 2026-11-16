# Drel 1.5.4 Build 154 Release Verification

Verified: 2026-11-16

## Change

- Trusted HTML app opens now record local-only offline diagnostics covering
  launch, package lookup, WebKit navigation, visible page state, online
  fallback, and app API stages. Records are whitelist-only (controlled error
  domains, digest prefixes, no tokens/query values/absolute paths), capped at
  20 attempts and 96 KiB, and clearable locally.
- Settings gains a user-facing offline app diagnostics screen (normal
  preferences section, not DEBUG-only) with app filtering, copy, and local
  clear.
- All six launch paths (direct, restore, notification, push, external link,
  catalog) pass an explicit online fallback URL plus the diagnostics context
  into the managed browser; navigation failures and "finished but never
  visible" pages attempt one online fallback before offering diagnostics and
  retry.
- WebBridgeKit Framework PR #9 fixes two probe defects found in review: the
  probe previously reported exactly once after DOMContentLoaded, so
  late-rendering pages were misjudged and switched to the online fallback
  unnecessarily, and the media check ignored CSS-hidden elements.

## Gates

- WebBridgeKit PR
  [#9](https://github.com/dyyz1993/WebBridgeKit-Framework/pull/9) merged as
  `e4bc3cc11a168391beb043a537d33e8cfc05fa66`; framework-revision.txt pins it.
- Framework CI: architecture, design, SwiftLint, build, CoreA, CoreB,
  Handlers, and Modules all passed, including the new
  `OfflineDiagnosticsPageProbeTests` (4 tests: CSS-hidden media produce no
  ready report, late renders are detected inside the bounded watch, visible
  text reports ready once, double install is guarded). Local targeted run:
  ModelsTests 7/7.
- Drel PR CI: Build passed with the pinned framework; SwiftLint, Repository
  Conventions, Release Purity, Design System Lint, Smoke Tests, and UI
  Fidelity jobs recorded on the PR.
- Drel integration PR #16 merged as 02bf37a with all nine CI jobs green
  (Build, SwiftLint, Repository Conventions, Release Purity, Design System
  Lint, Smoke Tests, UI Fidelity Tests included).
- Drel Debug simulator build: BUILD SUCCEEDED.
- SwiftLint on all touched app files: exit 0 (pre-existing warnings only).
- Simulator VOT UI suite `OfflineVOTDiagnosticsTests` (iPhone Store Asset
  simulator, iOS 18.3): 4/4 passed in 292.6s — both VOT identities opened
  their local 0.4.10.3 packages and rendered the login shell, delete →
  redownload → cold restart passed, an invalid workspace token recorded
  `apiUnauthorized`, and a blank local entrypoint attempted exactly one
  online fallback and recorded the fallback stages.
- Privacy: the simulator diagnostics file was scanned and contained no
  secrets, query markers, tokens, or absolute on-device paths; unknown error
  domains are reduced to `controlled` with numeric codes only.

## Scope

Probe coverage is proven for the tested DOM strategies (visible text,
CSS-visible media, data-drel-ready markers, and late renders inside the 7s
watch window). Arbitrary pages remain best-effort: custom zero-size WebGL
canvases, shadow-DOM-only trees, and intentionally empty pages still end in
the documented timeout/fallback path, and this verification does not claim
general-page reliability.

## Outstanding

- Physical-device acceptance after TestFlight build 154 processing: open the
  App Center offline packages on the physical iPhone, confirm the new
  diagnostics screen records real opens, and re-check airplane-mode
  delivery. The device currently runs 1.5.4 (153) without these changes.
- Real-device API-success and server-failure E2E cases remain covered by
  implementation plus unit-level sanitization; the deterministic simulator
  case covers the unauthorized path.
