# Drel voice-level Bridge and H5 games

**Date**: 2026-11-01  
**Target**: Original local test configuration (then labelled 1.5.1/135); subsequent release target is 1.5.2/136, pending revalidation  
**Status**: simulator and adapter verification passed; microphone hardware and TestFlight acceptance remain open.

## Scope

- `audioLevel` is a signed-manifest action in the future microphone-enabled build.
- The declaration requires `.always`; the user chooses a reusable or one-time consent scope in the branded panel.
- First `start` requires a foreground user gesture. `stop`, session end, revocation, background, and interruption stop capture.
- The native handler publishes RMS level only (`0...1`). It never exposes PCM samples or recording.
- Both games use the shared `test_resources/voice-games/audio-level.js` adapter and fall back to `getUserMedia` in ordinary browsers.

## Results

| Check | Result |
|---|---|
| Sound adapter cancellation, denial, forwarding, and stop paths (`node tools/test-voice-level.js`) | PASS |
| Voice Jump / Dandelion authorization-to-start and hide-page cleanup (`node tools/test-voice-games.js`) | PASS |
| Framework `CoreTests/WebJavaScriptBridgeTests` | 33 tests, 0 failures |
| Framework `HandlerTests/WebAudioLevelHandlerTests` | 9 tests, 0 failures |
| Drel UI authorization/cancel for Voice Jump and Dandelion | 2 tests, 0 failures |
| `Drel151Release` iOS Simulator build, scheme `Drel151Store` | BUILD SUCCEEDED |
| `bash tools/ci-lint.sh` | 18 passed, 0 failed |
| `bash tools/verify-drel-v2-action-policy.sh` | PASS |

Latest result bundles used during verification: `/tmp/wbk-core-final-*.xcresult`, `/tmp/wbk-audio-handler2-*.xcresult`, `/tmp/drel-voice-both-*.xcresult`. Latest build log: `/tmp/drel-151-final-sim.log`.

## Not yet accepted

- Real microphone amplitude, calibration feel, jump height, and blow sensitivity require a physical iPhone.
- Strong-offline packages, signed gateway deployment, release archive, and TestFlight are outside this pass.
- The H5 fixtures remain versioned source files; they are not bundled into the Store app by Release.

## 2026-11-02 isolated 1.5.2 / 136 verification

- Isolated framework commit: `f101796ffbbb412930950557e524bc7b2b807080`.
- Drel `Drel152Release` Simulator build: `BUILD SUCCEEDED`; built plist reports 1.5.2 (136) and the live-level microphone usage purpose.
- Bridge CoreTests: 33 passed, 0 failed (`/tmp/wbk-voice152-core.xcresult`).
- Audio handler tests: 9 passed, 0 failed (`/tmp/wbk-voice152-handler.xcresult`).
- Drel authorization/cancellation UI tests: 2 passed, 0 failed (`/tmp/drel-voice152-ui.xcresult`). These UI tests used the existing local 8081 fixture server; the corrected animation was separately exercised via the isolated preview host.
- Voice adapters: `node tools/test-voice-level.js` passed. Both games: `node tools/test-voice-games.js` passed, including the added two-frame regression that first reproduced and then verified the dandelion fix.
- Local manifest contract/signature: `node tools/test-voice-manifests.mjs` passed for both games with a test signing key; no claim of live gateway registration.
- `swiftlint --quiet`: both repositories exited 0 after removing an existing duplicate Lucide branch; existing warnings remain. `bash tools/ci-lint.sh`: 18 passed, 0 failed. Crash scan: total 0.
- Interactive local browser practice: jump character moved and score advanced; dandelion seeds moved after simulated blow. This does not prove real microphone behavior.
- Temporary, network-only preview origin: `https://drel-voice152.shanbox.19930810.xyz:8443`; verified TLS and SHA-256 match for both game pages and their shared adapter. It depends on the development Mac and must not be used as a permanent App Review demo.
- Two device-scoped manifest inputs are prepared in `test_resources/voice-games/manifests/`; they are not registered or production-signed yet.
- iPhone is paired, but PUA startup failed while enabling UI automation; no device acceptance or TestFlight publication is claimed.
