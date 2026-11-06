# Drel voice-level Bridge and H5 games

**Date**: 2026-11-01  
**Target**: Drel 1.5.1 (135) / WebBridgeKit local workspace  
**Status**: simulator and adapter verification passed; microphone hardware and TestFlight acceptance remain open.

## Scope

- `audioLevel` is a signed-manifest action in 1.5.1 only.
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
