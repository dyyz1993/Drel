# Drel 1.5.5 Build 160 Release Verification

Verified: pending. This record is completed once the `v1.5.5+160` build has
been uploaded and accepted by App Store Connect.

## Change

- 1.5.5 is the first Store release of the fixes recorded under 1.5.4. App
  Store Connect approved 1.5.4 as build 143 on 2026-11-10; that build predates
  builds 145-159, where the fixes landed, and the version was never released.
  The App Store still serves 1.5.3.
- Build 160 is archived from `main`. The release records were committed
  in `8b2d6ee`; the `v1.5.5+160` tag points at the commit that adds this
  line. Its app sources
  differ from build 159 (`3c2c35d`) only in a demo-data placeholder string
  (`bdc4ebb`); everything else added since is CI, documentation, server code
  and the self-hosting material, none of which is compiled into the app.

## What the build contains since 1.5.3

- Builds 146-155: the fixes listed in
  [the 1.5.4 release notes](../1.5.4/RELEASE-NOTES.md).
- Build 156 (`c141893`, includes #18): an installed strong-offline package
  launches on a confirmed offline cold start when it passes integrity
  verification, even if a newer version exists.
- Builds 157-159 (includes #20): Drel Device Grant v1, a device-bound login
  for HTML apps that the user approves once.

## Gates

| Gate | Result |
|---|---|
| CI on `main` before the release commit | Run `46004526398` (`d004c2e`): SwiftLint, Build, Repository Conventions, Design System Lint, Release Purity, Smoke Tests and UI Fidelity Tests all passed. |
| `tools/verify-release-notes.py`, `tools/verify-release-identity.py --marketing 1.5.5 --build 160`, `tools/verify-repo-hygiene.py`, `tools/verify-docs-links.py`, `tools/verify-drel-developer-docs.py` | pending |
| Tag build `v1.5.5+160` (`Build IPA` workflow: archive with project signing, distribution contract checks, TestFlight upload) | pending |
| App Store Connect processing state of build 160 | pending |
| Physical-device acceptance | pending |

## Open item

The Drel Device Grant authorization prompt has not been confirmed on a
physical device (the VOT fast-login case). The feature is therefore not
called out in the Store release notes.
