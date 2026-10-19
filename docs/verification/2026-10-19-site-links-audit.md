# Website and split-repository link audit — 2026-10-19

## Scope and isolation

Prepared in `chore/website-links-20261019` from Drel `a8e07d8` and the paired
Framework branch `chore/repository-links-20261019` from `5616579`.
The active `study-ios` checkouts were not edited. The four original untracked
Drel files were hashed before work and matched after verification.

## Changes

- Homepage and navigation link to the verified Drel App Store product page.
  Apple Lookup returned Drel 1.4.1; Chrome rendered the product heading `Drel`.
  The explicit CN URL is retained because the regionless link redirected to a
  storefront homepage in the audit environment. Other storefronts need their
  own browser verification before replacing it with a regionless link.
- App issue URLs and all three server discovery implementations identify Drel.
  Private source links are labelled as requiring access; email/website support
  remains available. The private Framework podspec identifies its own repository.
- The existing public skill command is preserved and labelled legacy distribution.
  GitHub still contains `skills/drel-app-development/SKILL.md` in the public
  WebBridgeKit repository. Drel and Framework repositories are private.
- English and Chinese Bark migration guides explain basic request compatibility,
  separate credentials, parameter verification and independent product ownership.
  Homepage and push docs link to them. No full-parity or ranking claims are made.
- Thirteen product/documentation pages have canonical and Open Graph metadata;
  the guides have reciprocal language alternatives. The homepage has factual
  SoftwareApplication JSON-LD. Sitemap and robots.txt are included; fixture and
  artifact noindex headers are configured for the hosting platform.
- Contributor setup and Drel README use the split repository and Drel target names.

## Full-site build repair

Individual demo builders reset staging. A complete website needs offline,
network-offline, data-template, skill distribution and action-demo outputs.
`tools/build-drel-site.sh` composes them without losing previous outputs.

The data-template source had been omitted from Git by `test_resources/*`.
The retained legacy file was copied into this branch and explicitly unignored;
its SHA-256 matches the published resource:
`0ce3ba92f9b32e5f97d8e2f0abd13fff4ab99e80ccc6ab7de15c92866df7c993`.
The legacy directory was not edited. All three generated offline package JSON
files match the current public copies byte-for-byte.

At audit time, the live action-demo page and the skill SKILL.md/ZIP URLs returned
404. The complete staging build contains these resources. This is a prepared
repair; it does not prove production was deployed.

## Verification

- Complete site build: PASS.
- Sitemap: 13 pages; exactly one H1 and canonical targets; internal links/assets:
  PASS against generated staging. Skill ZIP integrity and SKILL.md entry: PASS.
- Offline public verifier against localhost: PASS, 4 resources and 8 ZIP entries.
- Chrome: desktop homepage at 1440px, mobile homepage and both Bark guides at
  390px; checked screenshots and no horizontal overflow. Homepage copy command
  produces success feedback with the preserved install command.
- Chrome: App Store URL opens the Drel detail page, not the Today storefront.
- Node syntax check and build-script shell syntax: PASS.
- Go server tests: PASS using `env -u GOROOT /usr/local/bin/go test ./...`.
  The inherited GOROOT referred to a different Go installation and initially
  prevented vet from starting; the process-local override fixes the toolchain.
- Targeted SwiftLint: zero errors, three existing PushRoutes.swift warnings
  (file length, optional data-string conversion and trailing comma).
- `git diff --check`: PASS.

Screenshots are retained outside Git in the paired worktree parent directory:
`home-desktop.png`, `home-mobile.png`, `bark-zh-mobile.png`.

## Release boundary

These are local branch changes. Website deployment, server deployment and an
updated App Store binary are separate delivery steps. App issue links take
effect only in a future binary; server discovery links require service deployment.
Publishing the static site does not ship the app/server changes. No App Store
submission or release version change is part of this task.

Search Console submission, actual index inclusion, field Core Web Vitals and
rankings have not been measured. The sitemap provides discovery information;
search results are not guaranteed.

Framework validation: Ruby syntax and `pod ipc spec` passed; source URL resolves
to the private Framework repository with the existing version/tag unchanged.
The new remote has no tags, so tagged CocoaPods installation remains unavailable
until an SDK tag is intentionally published. Local-path integration remains the
documented working setup. ZCode delegation completed as
`sess_6365b012-fe87-4570-87e2-17610a7bf482`; its diff was reviewed and corrected
for the current Drel target name and the missing remote tag.
