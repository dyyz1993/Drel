# Drel 1.5.4 Build 149 Release Verification

Verified: 2026-11-14

## Change

- WebBridgeKit writes installer metadata to `installed.json` and preserves the
  downloaded resource manifest instead of overwriting `package.json`.
- Cold launch verifies either the retained resource descriptor or a legacy
  `package.json` digest before activating a package.
- Drel retries the saved default startup app while the Gateway trust registry
  finishes loading.
- Recent-session restore rejects absolute `file://` URLs so stale package paths
  cannot survive an app update or restart.

## Gates

- WebBridgeKit `HTMLAppOfflinePackageInstallerTests`: 17 passed, 0 failed.
- WebBridgeKit `WebBrowserSessionRestoreTests`: 2 passed, 0 failed.
- WebBridgeKit PR [#3](https://github.com/dyyz1993/WebBridgeKit-Framework/pull/3)
  merged as `4815bcc1011d838c7100834b947f0c7f490df14d`.
- Drel PR [#13](https://github.com/dyyz1993/Drel/pull/13) merged as
  `3c21b059c4db6949b82453a86dba4eb07759e6c3`; Build, Smoke, SwiftLint, Design
  System, and Repository Conventions passed.
- Drel simulator build passed on Xcode 27.2.
- App Store Connect reports build 149 `processingState=VALID`.
- App Store Connect reports internal `IN_BETA_TESTING`; external state is
  `READY_FOR_BETA_SUBMISSION`.
- The first release run uploaded successfully but timed out at its original
  10-minute processing poll; the poll window is now 30 minutes for future
  releases.
- Physical acceptance remains required before shipping the TestFlight build.
