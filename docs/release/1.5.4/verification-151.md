# Drel 1.5.4 Build 151 Release Verification

Verified: 2026-11-14

## Change

- Makes the duplicated `drel_offline.version` field optional.
- A manifest that omits the field inherits the signed parent cache version.
- A manifest that still declares the field keeps the old compatibility path.
- The resource manifest remains the authoritative package version and digest
  target; parent-cache version still must match it during installation.

## Gates

- WebBridgeKit PR
  [#5](https://github.com/dyyz1993/WebBridgeKit-Framework/pull/5) merged as
  `cebf08ee3ea32ce90a2fb7fa4dfe525ba977c0e2`.
- Framework PR CI: build, SwiftLint, architecture, design, CoreA, CoreB,
  Handlers, and Modules unit tests passed.
- Simulator targeted tests: `HTMLAppOfflinePackageInstallerTests` 18 passed,
  0 failed; `HTMLAppRuntimeModelsTests` 26 passed, 0 failed.
- VOT generator was updated to stop emitting the duplicated field; generated
  package `0.4.10.2` has 7 files and manifest SHA-256
  `2ff546031a874bc8b7df0d7434608fce73681b643d3fa97f74cc0b6ba7b30e7d`.
- App Store Connect confirms build 151 is `processingState=VALID` and
  `internalBuildState=IN_BETA_TESTING`. The release workflow missed the first
  poll because the old script treated a not-yet-enabled beta state as a
  terminal result; the polling script now waits for both processing and beta
  states.
- Physical delete/reinstall and package-update acceptance remains required
  after TestFlight build 151 processing.
