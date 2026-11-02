# Drel 1.5.3 (141) verification

- Simulator: four targeted capability-query and offline identity tests passed, including grant revocation, foreign origin, modified file, mismatched package, an authorized offline sensor action, and same-version reinstallation.
- Simulator: 15 offline installer regression tests passed, including same-version legacy metadata upgrade.
- Simulator: Drel UI loaded its installed offline entrypoint in a real WKWebView and queried the declared clipboard capability without displaying permission UI; 1/1 UI test passed.
- Simulator Drel153Release build: passed; built app Info.plist reports 1.5.3 (141). TestFlight upload completed in GitHub Actions run 41547019768; Apple processing state `VALID` and internal build state `IN_BETA_TESTING`. Physical-device checks remain pending.
- Existing installed offline packages without the retained verified resource manifest support the trusted entrypoint; reinstalling the offline package enables verified additional-page mapping.
- Build 139 was cancelled during setup. Build 140 was cancelled after archive, while upload may have started; no successful 140 receipt was observed and Apple-side status was not independently confirmed. Build 141 is the intended test build.
