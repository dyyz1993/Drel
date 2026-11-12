# Drel 1.5.4 Build 145 Release Verification

Verified: 2026-11-12

## Release identity

- Marketing version: `1.5.4`
- Build: `145`
- Source commit: `7d46d91`
- Release scheme: `Drel15Store`

## Automated gate

Command:

```bash
DREL_RELEASE_GATE_SCHEME=Drel15Store \
DREL_RELEASE_GATE_MARKETING_VERSION=1.5.4 \
DREL_RELEASE_GATE_BUILD_NUMBER=145 \
DREL_RELEASE_GATE_AUTOMATIC_SIGNING=1 \
DREL_RELEASE_GATE_ALLOW_PROVISIONING_UPDATES=1 \
WBK_SIMULATOR_ID=DF7E7D35-D223-4D75-8DC1-E2B76F45A2B5 \
bash tools/run-release-gate.sh
```

Result: `20 passed, 0 failed`. The report records services, deliverable
boundaries, release identity, docs, hygiene, lint, Debug build, crash scan,
archive identity, release HTML/DEBUG purity, managed action policy, WebView
regression, Store settings, critical-alert policy, APNs policy, and staging
archive surface.

Exported IPA verification:

- SHA-256:
  `b4a15ecfea15abfe3725ac8c28ab748d78b5e536af1a5d6de0d602fbe7ca5cf4`
- Bundle version: `1.5.4 (145)`
- Distribution signing and production APNs profile: PASS
- Required privacy strings: PASS
- `audioLevel` allowlist marker: PASS
- `getCapabilities` capability: PASS

## App Store Connect

- IPA upload succeeded with delivery UUID
  `31d81e66-30b5-4be5-a088-fa07e90068fa`.
- ASC build ID: `31d81e66-30b5-4be5-a088-fa07e90068fa`.
- Processing state: `VALID`.
- Internal beta state: `IN_BETA_TESTING`.

## Still required before Store submission

1. Install build 145 from TestFlight.
2. Physically verify normal notification delivery.
3. Physically verify Time Sensitive Notifications, including user-disabled
   Time Sensitive setting.
4. Physically verify `audioLevel` grant, live level, and revocation.
5. Verify the ten-action surface.
6. Attach these results and submit in App Store Connect.
