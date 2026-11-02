# Drel 1.5.3 (141) verification

- Simulator: four targeted capability-query and offline identity tests passed, including grant revocation, foreign origin, modified file, mismatched package, an authorized offline sensor action, and same-version reinstallation.
- Simulator: 15 offline installer regression tests passed, including same-version legacy metadata upgrade.
- Simulator: Drel UI loaded its installed offline entrypoint in a real WKWebView and queried the declared clipboard capability without displaying permission UI; 1/1 UI test passed.
- Simulator Drel153Release build: passed; built app Info.plist reports 1.5.3 (141). TestFlight upload and physical-device checks: pending.
- Existing installed offline packages without the retained verified resource manifest support the trusted entrypoint; reinstalling the offline package enables verified additional-page mapping.
