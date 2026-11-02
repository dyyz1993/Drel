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
- Temporary, network-only preview origin: `https://drel-voice152.legacy-infra.example.invalid:8443`; verified TLS and SHA-256 match for both game pages and their shared adapter. It depends on the development Mac and must not be used as a permanent App Review demo.
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

### 2026-11-02 stable H5 path and voice tail

- Owner confirmed the revised jump threshold responds to voice; sustained-tail descent tuning remains pending physical feel assessment. Automated game test confirms sustained sound slows falling and quiet background does not trigger jump.
- Published the three H5 resources under `https://drel.app/sound/` using Cloudflare Pages production deployment `50c6f3db`. All three live files matched their source SHA-256; the pre-existing home page matched its previous SHA-256. All 87 previously staged public files matched the preview before production deployment; four existing ZIPs were preserved from production.
- A path-scoped Pages Function enables web microphone permission only under `/sound/`; production returned the expected policy and 200. The original site policy remains intact elsewhere.
- Device-scoped signed manifests updated to version 2 under `https://drel.app` and verified by Ed25519 signature and private readback. The device catalog showed both drel.app entries. Voice Jump opened through that catalog, requested a new drel.app grant, and started via Bridge after one-time consent.
- The test apps remain device-scoped and absent from the anonymous catalog; stable public catalog distribution and physical tail feel are not yet accepted.

### 2026-11-02 double jump and catalog compatibility preparation

- User confirmed the tuned single jump responds to voice; requested a second jump after voice falls and rises, while sustained sound slows descent. The H5 logic implements one additional jump per airborne session; automated tests verify moderate-sound descent, no repeat for continuously held sound, a second jump after release and rise, and rejection of a third jump. Production H5 at `https://drel.app/sound/voice-jump/` matches source SHA-256; Pages deployment `19ca0bb5`; homepage hash unchanged. Physical game-feel confirmation is pending.
- Old 1.5.1 controlled-action decoding rejects unknown `audioLevel` declarations and gateway decoding treats the manifest list as a whole. The public catalog must not expose those entries to legacy clients.
- A locally implemented opt-in catalog filter requires `supportedActions=audioLevel`; the 1.5.2 (138) client advertises it for its scoped official gateway. The gateway keeps full signed manifests intact, removes unsupported dynamic audio manifests from legacy lists, and adds the two official games only for opted-in clients. Not deployed yet.
- Gateway tests: 53 passed, 0 failed. Client gateway-key scope tests: 6 passed, 0 failed on iOS Simulator; 138 `Drel152Release` Simulator build succeeded and the compiled product contains the negotiation marker. Design/repository lint: 18 passed, 0 failed. No claim of public-catalog live verification or TestFlight 138 delivery.

### 2026-11-02 retained-tail second-jump correction

- The owner reported the prior two-jump version did not trigger in physical use. Its arm threshold required near-silence, conflicting with the requested retained tail.
- A deterministic retained-tail test reproduced the failure. The trigger now detects a meaningful decrease from the airborne peak followed by an increase, without requiring complete silence. Continuous sound cannot retrigger and only one extra airborne jump is allowed; regression checks pass.
- Pages production `a9676a30` serves the updated game with matching SHA-256 and unchanged homepage. Awaiting physical feedback; no claim of physical acceptance.

### 2026-11-02 triple jump

- User requested multiple jumps. The game allows two additional jumps per airborne session; each requires a meaningful drop and subsequent rise in sound, while sustained sound slows descent. The count resets on the next grounded jump.
- Automated game tests passed: continuous sound does not repeatedly jump, retained-tail release/rise triggers second and third jumps, a fourth midair jump is blocked, and landing restores jumping.
- Pages deployment `f1d63337` serves the revised page with matching source SHA-256; homepage matches the previous production baseline. Physical feel confirmation is pending.

### 2026-11-02 138 release in progress

- User chose to keep the current three-jump behavior without further adjustment; this does not establish a separate physical pass for the three-jump feel.
- Before changing the official gateway, downloaded its deployed Worker source and compared it with the pre-change source bundle: exact match after normalization of an automatically generated bundle symbol. Deployed gateway `29b82e9f-be88-4035-9121-fbd61ac5a5f1`; `/health` reports `2026.11.02-audio-catalog`.
- Production legacy catalog returned no audioLevel declaration; a request declaring audioLevel support returned the two additional official games with valid Ed25519 signatures and stable drel.app paths. Gateway tests 53/53; no claim of 138 device catalog verification yet.
- Release commit `238b033`, tag `v1.5.2+138`; TestFlight Actions run `41382142553` started. Upload and physical install are pending.
