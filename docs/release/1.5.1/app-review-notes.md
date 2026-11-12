# Drel 1.5.1 App Review Notes

Status: prepared for the UI-only 1.5.1 (135) release. Re-read the exact ASC
build after upload and before submission.

## Summary

Drel 1.5.1 contains only the browser interface fixes accepted from the
build 134 TestFlight train. It adds no native action, no microphone or audio
capability, no new permission, and no new data collection.

The Store capability surface remains the same as the approved Drel 1.5.0
(118) release:

- `haptic`
- `vibrate`
- `share`
- `fullscreen`
- `clipboard`
- `getLocation`
- `addToHomeScreen`
- `sensors`

There is still no microphone, camera, Bluetooth, contacts, photo-library, or
speech capability in Drel's host action allowlist.

## Review walkthrough

No account, login, purchase, subscription, or credentials are required.

1. Open the signed Manifest v2 demo app from Drel's trusted app list.
2. Enter immersive fullscreen. The floating edge control remains available.
3. Tap More to open the custom bottom function panel; the edge control
   collapses while the panel is open and returns after the panel closes.
4. Use link copy and observe the unified short feedback.
5. Open an ordinary HTTPS page in the browser, use More to hide the status
   bar, then show it again; the page and navigation state remain unchanged.
6. Use the existing native-action, permission, and revocation flows if a
   fuller regression is needed; their behavior is unchanged from 1.5.0.

## Privacy

This release adds no new data type, permission prompt, analytics service, or
network endpoint. Clipboard, location, and sensors remain explicit, local,
and revocable as described in the approved 1.5.0 review model.
