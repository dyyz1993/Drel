# Drel 1.5.4 Build 155 Release Verification

Verified: 2026-11-17

## Change

- The App Center offline package action previously showed "更新离线包"
  whenever the installed and remote version strings differed, including
  downgrades. The action title and the pending summary now compare versions
  numerically component-by-component: "更新离线包" /
  "强离线包待更新（当前 X → Y）" appears only when the remote version is
  strictly newer. Same version, missing version data, downgrades, and
  non-numeric (uncomparable) versions fall back to "重新下载离线包" /
  "强离线包需重新下载". Deleting any installed package, old or current,
  remains available.

## Gates

- New unit regression `DrelTests/OfflinePackageUpdateLabelTests` (9 tests:
  not-installed download, same-version redownload, empty/missing versions,
  strictly-newer update, numeric 0.4.9.9 → 0.4.9.10 compare, downgrade, four
  uncomparable targets, whitespace trimming, differing component counts):
  9/9 passed on the iPhone 17 simulator with the Drel scheme (Debug).
  xcodebuild reported `** TEST SUCCEEDED **` and `Executed 9 tests, with
  0 failures`.
- SwiftLint on the three touched Swift files: exit 0 (pre-existing
  file_length warning only).
- App Store Connect query (app 6802806992): latest build 154, uploaded
  2026-11-16, processingState VALID — this release uses build 155, so no
  duplicate build number.
- `verify-release-notes.py`, `verify-release-identity.py --marketing 1.5.4
  --build 155`, and `verify-repo-hygiene.py` must pass before push; PR CI
  (Build, SwiftLint, Repository Conventions, Release Purity, Design System
  Lint, Smoke Tests, UI Fidelity) must be green before merge and the
  `v1.5.4+155` tag.

## Scope

UI copy and version-comparison logic only; no download/install pipeline,
manifest schema, or Bridge behavior changes. The strict-newer rule gates only
the label: "重新下载" still fetches and activates the remote package, which
remains correct for hash-mismatch repairs. Numeric overflow (components above
Int.max) is treated as uncomparable and falls back to redownload.
