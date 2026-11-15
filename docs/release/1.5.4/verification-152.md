# Drel 1.5.4 Build 152 Release Verification

Verified: 2026-11-15

## Change

- Preserves the signed trusted HTTPS page separately from the current document
  URL in `WebBrowserViewModel`.
- Store builds with `nativeBridgeEnabled == false` now receive that fallback
  context from the launch payload.
- `WebBrowserViewController` offline navigation recovery uses the trusted page
  instead of the local file URL that may have overwritten it.
- The change covers app-center, push, external link, and default startup paths
  because all immersive launches deliver `webbridgekitPageURL`.

## Gates

- WebBridgeKit PR
  [#6](https://github.com/dyyz1993/WebBridgeKit-Framework/pull/6) merged as
  `42f6358ef0fe6a028089766a08a8b4bc283521a0`.
- Framework CI: architecture, design, SwiftLint, build, CoreA, CoreB,
  Handlers, and Modules all passed.
- Simulator targeted test:
  `testStoreBrowserPreservesTrustedOfflineFallbackContextWithoutNativeBridge`
  passed as part of `WebBrowserSessionRestoreTests` (4 tests, 0 failures).
- Production VOT package `0.4.10.2` was opened in real Chrome from `file://`,
  including Drel launch query parameters. CSS and both scripts loaded, the
  document completed, `VOT_OFFLINE_PACKAGE=0.4.10.2`, and the login screen
  rendered.
- Drel Build 151 was confirmed on the user's device before isolating this
  remaining Store-specific fallback-context gap.
- Physical delete/reinstall acceptance remains required after TestFlight
  build 152 processing.
