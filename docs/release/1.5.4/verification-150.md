# Drel 1.5.4 Build 150 Release Verification

Verified: 2026-11-14

## Change

- Extends the strong-offline online fallback to `WebBrowserViewController`.
- VOT and other immersive apps now retry their signed HTTPS page once if the
  verified local entrypoint fails after reinstall or package replacement.
- The fallback remains bounded to one attempt and cannot grant extra trust.
- The failure HUD is suppressed during the bounded fallback to avoid showing a
  fatal error for a recoverable navigation.

## Gates

- WebBridgeKit PR [#4](https://github.com/dyyz1993/WebBridgeKit-Framework/pull/4)
  merged as `c99ccec3bdd8b484693405f1b511e4b0b55a91a3`.
- CI build, SwiftLint, architecture, design, and all unit-test groups passed.
- Local `CoreTests/WebBrowserSessionRestoreTests`: 3 passed, 0 failed.
- The VOT `0.4.10.1` package manifest and all seven resources were revalidated
  by hash over HTTPS before diagnosing the host-side fallback gap.
- Physical delete/reinstall acceptance remains required after TestFlight build
  150 processing.
