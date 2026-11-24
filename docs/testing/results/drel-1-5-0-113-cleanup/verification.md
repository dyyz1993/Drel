# Drel 1.5.0 (113) cleanup verification

Date: 2026-10-29

Status: local, simulator, signing, and TestFlight verification passed. App Store
review has not yet been submitted at the time this file was created.

Build 113 remains the cleanup baseline. The final submission candidate is
build 118; see `docs/release/1.5.0/verification-118.md`.

## Scope

- Remove expired and seeded development manifests from upgraded installs.
- Keep all debug HTML and fixture CSS out of the Store package.
- Publish the Drel 1.0 Bridge fixtures from one website source, with version
  markers, shared styling, dark mode, and structured request/response traces.
- Align the public action demo manifest with the seven wire action names used
  by the Store allowlist.

## Evidence

| Check | Result | Evidence |
|---|---|---|
| DrelTests | PASS, 31/31 | `xcodebuild test ... -only-testing:DrelTests` |
| Debug simulator test build | PASS | `xcodebuild ... -only-testing:DrelTests` |
| Drel15Release build | PASS | `BUILD SUCCEEDED` |
| Release package HTML files | PASS, 0 | `find Drel.app -name '*.html'` |
| Release fixture stylesheets | PASS, 0 | `find Drel.app -name '*fixtures*.css'` |
| Design and fixture lint | PASS, 18/18 | `bash tools/ci-lint.sh` |
| Site integrity | PASS | `python3 tools/verify-drel-site.py` |
| Action declarations | PASS, 7 exact wire names | `getLocation` present; `location` absent |
| Bridge fixture pages | PASS, 12/12 viewport/theme runs | 6 pages × light/dark; 390px and 1280px had no horizontal overflow or failed requests |
| Bridge debug trace | PASS | Mocked call showed request, response, duration, per-call copy, and copy-all |
| Diagram freshness | PASS, 8/8 | `bash tools/build-drel-diagrams.sh --check` |
| Distribution archive | PASS | `Drel15Store` / `Drel15Release`, commit `856e886` |
| Distribution signature | PASS | Apple Distribution / team `B45VZCNYU3` |
| Store entitlements | PASS | production APNs, communication notifications, `get-task-allow=false` |
| TestFlight build 113 | PASS, `VALID` | ASC build ID `957fd228-fc84-4947-b216-51df36b8fc95` |
| IPA SHA-256 | PASS | `753c0707e48010c7ffb861aaf08988ae09a7ed981274418e637fd7d423711deb` |
| Physical installed build | PASS | Build version（截图保留在内部记录） |
| Physical storage cleanup | PASS | Storage screen（截图保留在内部记录） |

The Bridge browser matrix is stored in
`build/reports/bridge-v1-113/http-matrix.json`; screenshots are under
`build/reports/bridge-v1-113/`. These are local verification artifacts and are
not release package contents.

## Signing recovery

The original login keychain search list contained an invalid `login-db` entry
and the Apple Development / Distribution certificates did not have usable local
private keys. A new Distribution certificate was created without revoking the
existing certificates. Two active versioned profiles were created:

```text
WebBridgeKit App Store 113      AMD4S65KD9  profile 791515df-807b-47b4-a40a-b7715dbc7dcc
WebBridgeKit NSE App Store 113  AZW526CUNK  profile ba05b0d3-8984-4a11-8986-1d60b65ecfc8
```

The signing identity is stored in
`~/Library/Keychains/drel-release.keychain-db`; its password is stored as a
dedicated generic-password item in the login keychain. Neither private material
nor its password is committed to the repository. The user search list was
restored to the login and system keychains after the build.

## Production dependency

The official gateway Durable Object returned Cloudflare `1101` with:

```text
Exceeded allowed rows written in Durable Objects free tier.
```

The free quota resets at 00:00 UTC. The signed production action manifest must
be published and verified after reset, or after the Cloudflare Workers plan is
upgraded. A static unsigned reference manifest does not satisfy App Review's
signed-gateway demo precondition.

## Historical next steps

These steps were completed during the build-114 through build-118 release
hardening. Build 118 carries the final signed gateway and physical-device
evidence.
