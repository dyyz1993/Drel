# Drel 1.5.4 Submission Checklist

Status: ready-to-execute checklist as of 2026-11-12. Do not submit until every
`PENDING` item has a dated, linked result.

## Release identity

- Marketing version: `1.5.4`.
- Latest repository tag: `v1.5.3+142`; choose the next unused ASC build and
  never reuse builds 141-143.
- Final build number: **PENDING**.
- Release train: `Drel15Store` with `MARKETING_VERSION=1.5.4` and
  `CURRENT_PROJECT_VERSION=<BUILD>` overrides.
- Final tag after archive/upload passes: `v1.5.4+<BUILD>` (**PENDING**).

## Owner decisions

- Confirm the final ASC build number before archiving.
- Confirm whether 1.5.4 should be released worldwide immediately or withheld
  from China mainland until the App filing number exists. Current preference:
  wait for the JD Cloud filing result; do not enter a placeholder filing
  number.
- Confirm whether the existing 1.5.3 screenshots remain acceptable. No visual
  product change is documented for 1.5.4.

## Repository gates

Run from the repository root after replacing `<BUILD>`:

```bash
python3 tools/verify-release-identity.py --marketing 1.5.4 --build <BUILD>
python3 tools/verify-release-notes.py
python3 tools/verify-repo-hygiene.py
swiftlint --quiet
bash tools/ci-lint.sh
DREL_RELEASE_GATE_SCHEME=Drel15Store \
DREL_RELEASE_GATE_MARKETING_VERSION=1.5.4 \
DREL_RELEASE_GATE_BUILD_NUMBER=<BUILD> \
bash tools/run-release-gate.sh
```

Required archive assertions:

- ITMS-90683 regression: release bundle contains
  `NSBluetoothAlwaysUsageDescription`.
- Release binary contains the `audioLevel` action marker.
- Release policy exposes exactly the ten documented actions.
- Archive/App version is `1.5.4 (<BUILD>)`.
- Release gate report and individual logs are retained under
  `build/reports/`.

## TestFlight acceptance

These require a physical iPhone; simulator acceptance is insufficient for
Focus-mode and silent-switch behavior.

1. Install the TestFlight build.
2. Send a normal notification and verify banner/lock-screen, sound, badge, and
   Inbox entry.
3. Send `level=timeSensitive`; verify the notification can break through Focus
   mode and the silent switch when system/user settings permit it.
4. Disable Time Sensitive Notifications for Drel in Settings and verify the
   system honors that choice.
5. Verify the microphone permission prompt appears only for `audioLevel`, then
   run the Voice demo and confirm the live level updates.
6. Revoke the microphone grant in Settings and verify app behavior is safe.
7. Verify the ten-action surface matches
   `docs/release/1.5.4/app-review-notes.md`.
8. Record device model, iOS version, payload identifiers, screenshots, and
   command exit codes in a new verification file under this directory or
   `docs/testing/results/`.

## Submission package

- Paste the localized metadata from
  `docs/release/1.5.4/app-store-metadata.json` into App Store Connect. Keep
  public What's New text free of internal build-number history.
- Keep App Review notes aligned with
  `docs/release/1.5.4/app-review-notes.md`.
- Declare the Time Sensitive Notifications entitlement exactly as implemented;
  do not describe it as bypassing notification permission.
- Record the uploaded IPA SHA-256, archive path, upload receipt, and ASC build
  processing state.
- After Apple accepts the build, attach the TestFlight acceptance evidence
  before pressing Submit for Review.

## China mainland availability

Do not enable China mainland for 1.5.4 until the App filing number is issued.
Track the filing separately in
`docs/release/china-app-filing/README.md`. If a reviewer or provider requires
the China runtime default to use the filed domain, create a separate release
plan; do not silently change `DrelGatewayConfiguration` while preparing this
submission.
