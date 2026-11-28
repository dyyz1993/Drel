# 1.5.6 (161) — Verification

Build 161 is archived from `main` at the 1.5.6 release commit (see the tag
`v1.5.6+161`). It carries the "open untrusted apps as web pages" rework and
the My Apps surface rebuild that landed with PR #31 (`316aece`,
`f9b8125`, `9e51ff4`) and pins WebBridgeKit `7a1ba90` (1.4.2).

## What was checked before tagging

| Check | Result |
|---|---|
| `DrelTests/DrelAppOpenFallbackTests` | 8/8 pass; negative control (host guard removed) fails 14 assertions |
| Framework `HTMLAppGatewayOnboardingTests` | 16/16 pass (new: rejected catalog still exposes the untrusted start URL) |
| `tools/verify-l10n-keys.py` | 574 referenced keys, 2 locales, 0 missing |
| `tools/architecture-lint.sh --ci` | 0 errors |
| docs-links / developer-docs / repo-hygiene / release-notes / deliverable-boundaries / ci-lint / actionlint | all exit 0 |
| Simulator Debug build (`Drel`, iPhone 13, iOS 18.3) | succeeded |
| `DrelUITests/DrelSmokeTests.testAppLaunchesSuccessfully` on a clean simulator | passed (18.6 s) |
| PR #31 CI (all 7 jobs incl. UI fidelity + smoke) | green |
| Independent security review of the fallback (10 checks) | 3 must-fix items fixed; one reviewer claim disproven by test (`APP.DEV.DREL.x`) |

## Not verified on a physical device

- The fallback notice bar and the "couldn't open" sheet have only been seen in
  the prototype (`outputs/drel-open-flow-proto.html`) and through unit tests;
  no TestFlight install has exercised them yet.
- The Home Screen guide now emits `drel://app` links; the Safari "Add to Home
  Screen" hand-off on a real iPhone has not been re-run for 1.5.6.
- `drel.app/launch` universal links are still not configured (no applinks
  entitlement, no AASA file); that path is unchanged and still does not open
  Drel.

## TestFlight acceptance steps (1.5.6)

1. Install build 161 from TestFlight.
2. Open a push that carries an unregistered app and tap "open app": it should
   open the app's site in the normal browser with the "opened as web" notice,
   not a jargon alert.
3. Tap the same notification's banner: a failure must now show a sheet with a
   reason and a diagnostics link instead of silence.
4. Home → "My Apps" with the gateway unreachable: the empty state should name
   the reason and offer Retry / View Diagnostics.
5. Home → "My Apps" → "enter an app address": a valid https URL opens in the
   browser; an appId that verifies opens its catalog detail.
