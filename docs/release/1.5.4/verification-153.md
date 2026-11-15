# Drel 1.5.4 Build 153 Release Verification

Verified: 2026-11-16

## Change

- The offline package installer validates the signed resource manifest, then
  reports total package bytes and file count before downloads start.
- URLSession download progress is forwarded per file and accumulated across
  files; Drel renders cumulative bytes against the verified total.
- WebBridgeKit Framework PR #7 merged as
  `4ceb2392368d2a1deac5df573af235a16de66122`.

## Gates

- Local targeted framework tests:
  `HTMLAppOfflinePackageInstallerTests` — 19/19 passed, including
  `testInstallReportsExpectedSizeAndDownloadedBytes`.
- Framework PR CI: architecture, design, SwiftLint, build, CoreA, CoreB,
  Handlers, and Modules all passed before merge.
- Physical acceptance remains required in Drel 1.5.4 (153): open App Center,
  prepare a VOT offline package, and confirm the HUD shows
  `预计下载 431.1 KB（7 个文件）` followed by cumulative
  `已下载 / 总大小` progress.
