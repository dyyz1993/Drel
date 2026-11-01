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

## 2026-11-02 TestFlight and permission follow-up

- Build 136 uploaded successfully via Actions run 41325833823 and was installed on iPhone 13 / iOS 18.7.3; the settings screen confirmed 1.5.2 (136).
- Two device-scoped manifests were signed by the existing gateway, signature-verified and read back. Both use a temporary development-Mac-backed HTTPS preview and are not production app listings or an App Review demo.
- Voice Jump: no unsolicited prompt on entry; cancelling the in-app microphone permission left the game stopped. On first system permission approval, the app incorrectly reported that foreground was required; a second tap started the game and the score advanced. This build did not pass first-authorization acceptance.
- Dandelion: entering the page did not prompt; tapping start displayed its own in-app permission, and allowing it started Bridge calibration. Actual physical blowing and revocation remain separate checks.
- Framework fix `3e82898abda5791ddf2a60c1d804d1aebd2dbf1e`: wait briefly for an inactive permission transition to become active, while failing closed on background, cancellation, revocation, or timeout. Handler tests: 13 passed, 0 failed (`/tmp/wbk-voice137-handler.xcresult`).
- Build 137 and physical first-authorization retest remain pending; do not claim the permission race is verified on a fresh physical permission state.

### Physical-device follow-up on build 136

- Dandelion: the owner blew into iPhone 13 and reported that the seeds dispersed with suitable sensitivity.
- Opening the in-app permission center ended page capture; the page displayed “离开页面，麦克风已关闭。” and the stop button was disabled on return.
- Revoking the stored microphone grant removed it from the permission center; tapping start again showed a new Drel permission prompt. Cancelling kept capture stopped.
- The page was already stopped by navigation before revocation, so the device test did not independently prove active-stream revocation; handler tests cover the cancellation path.
- Build 137 Simulator `Drel152Release` compiled successfully with framework `3e82898`; the built app reports 1.5.2 (137). TestFlight run 41330248700 is pending.

### Build 137 and Voice Jump tuning

- TestFlight upload: Actions run 41330248700 succeeded. TestFlight listed 1.5.2 (137), installed on iPhone 13; Drel settings confirmed Build 137.
- Voice Jump started via Drel Bridge on 137. The owner reported the green level meter moved but the character did not jump. This is a real-device gameplay failure, not a Bridge-delivery pass for the game.
- A deterministic test reproduces this with a moderate calibrated sound level. The H5 update lowers the jump threshold and delays the first obstacle; automated regression passes for both quiet background and a moderate sound stimulus. The updated temporary test page is deployed; physical feedback is pending.
- This phone had already granted iOS microphone access on 136. The exact first-ever iOS permission transition cannot be re-established by merely upgrading, so the 137 race fix is supported by state-machine tests but not a fresh-permission physical-device retest.
