# Drel 1.5.5 Build 160 Release Verification

Verified: 2026-11-27. Build 160 was uploaded by the `Build IPA` workflow,
accepted by App Store Connect, attached to a new 1.5.5 App Store version and
submitted for review. Physical-device acceptance of build 160 is still open.

## Change

- 1.5.5 is the first Store release of the fixes recorded under 1.5.4. App
  Store Connect approved 1.5.4 as build 143 on 2026-11-10; that build predates
  builds 145-159, where the fixes landed, and the version was never released.
  The App Store still serves 1.5.3.
- Build 160 is archived from `main`. The release records were committed
  in `8b2d6ee`; the `v1.5.5+160` tag points at `eba47bc`, the commit that
  taught the publish script and the action policy gate about 1.5.5. Its app
  sources
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
| `tools/verify-release-notes.py`, `tools/verify-release-identity.py --marketing 1.5.5 --build 160`, `tools/verify-repo-hygiene.py`, `tools/verify-docs-links.py`, `tools/verify-drel-developer-docs.py`, `tools/verify-drel-v2-action-policy.sh` | All passed on the release commit before the tag was pushed. |
| Tag build `v1.5.5+160` (`Build IPA` workflow: archive with project signing, distribution contract checks, TestFlight upload) | Run `46018205985` passed (archive, export, upload, archive verification before and after upload). The earlier tag pushes did not produce a build: two pointed at commits whose message carried the workflow skip marker, and one stopped before archiving because the publish script did not know 1.5.5 yet. |
| App Store Connect processing state of build 160 | `VALID`, uploaded 2026-11-27T14:50Z, build id `d532e4c5-1b19-4c16-b62a-60161b014513`, `internalBuildState=IN_BETA_TESTING`. |
| App Store version 1.5.5 | Created from 1.5.4's metadata (`asc release stage`), What's New replaced with the 1.5.5 text in de-DE, zh-Hans, ja, ko and en-US, review notes updated, readiness report 0 errors / 0 blocking. Submitted 2026-11-27T15:03Z: submission `ff1d3de7-69b8-439a-8209-b7e5709f4844`, version id `6c20da1c-bb0c-4f0f-aa57-ec961036f29a`, state `WAITING_FOR_REVIEW`, release type `MANUAL`. |
| Physical-device acceptance | Open. Build 160 is installable from TestFlight. |

## Open item

The Drel Device Grant authorization prompt has not been confirmed on a
physical device (the VOT fast-login case). The feature is therefore not
called out in the Store release notes.
