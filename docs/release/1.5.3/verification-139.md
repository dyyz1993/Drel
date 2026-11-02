# Drel 1.5.3 (139) verification

- Simulator: four targeted capability-query and offline identity tests passed, including grant revocation, foreign origin, modified file, mismatched package, and an authorized offline sensor action.
- Simulator: 14 offline installer regression tests passed.
- Simulator Drel153Release build: passed; built app Info.plist reports 1.5.3 (139). TestFlight upload and physical-device checks: pending.
- Existing installed offline packages without the retained verified resource manifest support the trusted entrypoint; reinstalling the offline package enables verified additional-page mapping.
