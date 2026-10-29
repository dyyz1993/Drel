# Drel 1.5.0 App Store version

Date: 2026-10-29

App Store Connect now has a `1.5.0` version record in
`PREPARE_FOR_SUBMISSION`. The record is not submitted for review.

## Identity

```text
App Store version ID: 5f394085-1ddb-41f4-bef1-263ba39112a0
Version:              1.5.0
Build:                118
Build ID:             1b65a4bd-2a15-42c2-a1ba-7bc4b3ee15e9
Build state:          VALID
Release:              manual, after approval
```

## Locales

| Locale | Localization ID | Source |
|---|---|---|
| `zh-Hans` | `46811434-a078-47a9-ae08-c53ec923dd78` | [app-store-metadata.json](app-store-metadata.json) |
| `en-US` | `6d31e7a9-6237-4ee7-ba16-0db0a0c2aafa` | [app-store-metadata.json](app-store-metadata.json) |

The existing 6.1-inch and 6.5-inch screenshot sets were copied from the
preceding version by App Store Connect. They contain four store images:
push, Inbox, favorites, and offline apps.

## Review information

- Review detail ID: `6289bf69-b784-4e20-9f4c-5d9291881a59`
- Source notes: [app-review-submission-notes.txt](app-review-submission-notes.txt)
- Notes length: 3,807 characters
- Demo account required: false
- The notes disclose all seven action wire names, including `clipboard` and
  `getLocation`, plus their data flow.

## Final verification state

Build 118 is processed as `VALID` in App Store Connect and was installed on a
physical iPhone 13. The signed production gateway, all seven declared actions,
permission revocation, fullscreen exit, add-to-Home-Screen, undeclared-camera
rejection, local tests, and crash scan are recorded in
[verification-118.md](verification-118.md).

No private review recording is attached by default. The public signed demo and
the notes provide the primary review path; add a recording only if Apple asks
for additional reproduction help.
