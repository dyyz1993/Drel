# Drel 1.5.0 (113) cleanup verification

Date: 2026-10-29

Status: local and simulator verification in progress. Build 113 has not yet
completed TestFlight processing or App Store review at the time this file was
created.

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

The Bridge browser matrix is stored in
`build/reports/bridge-v1-113/http-matrix.json`; screenshots are under
`build/reports/bridge-v1-113/`. These are local verification artifacts and are
not release package contents.

## Production dependency

The official gateway Durable Object returned Cloudflare `1101` with:

```text
Exceeded allowed rows written in Durable Objects free tier.
```

The free quota resets at 00:00 UTC. The signed production action manifest must
be published and verified after reset, or after the Cloudflare Workers plan is
upgraded. A static unsigned reference manifest does not satisfy App Review's
signed-gateway demo precondition.

## Remaining release steps

1. Publish the corrected action manifest to the official gateway.
2. Verify the signed `getLocation` declaration is returned by
   `/api/v1/html-apps/dev.drel.action-demo`.
3. Archive and upload build 113; wait for ASC `VALID`.
4. Create the 1.5.0 App Store Connect version, attach build 113, and run the
   physical-device TestFlight walkthrough.
5. Submit only after the signed demo and walkthrough are both available.
