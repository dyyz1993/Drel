# Drel 1.5.0 App Review Notes

Status: owner-review draft for the future 1.5.0 App Store version. This text
describes the full native action surface of the 1.5 Store build, including
the data-reading actions, so that review sees the real capability set
rather than discovering an undisclosed action during testing. It must be
re-checked against the final build before it is pasted into App Store
Connect.

## Summary

Drel is a developer push-notification utility and a container for HTML apps
that the user has explicitly trusted. Version 1.5.0 adds a narrowly scoped
Manifest v2 action runtime. The Store build exposes exactly eight native
actions, and no others:

- `haptic`
- `vibrate`
- `share`
- `fullscreen`
- `clipboard`
- `getLocation`
- `addToHomeScreen`
- `sensors`

This is not a general JavaScript-to-native Bridge and it is not remotely
extensible. Ordinary web pages, strong-offline packages, and unregistered apps
do not receive the Bridge. Drel 1.5 does not enable camera scanning, photo
library access, Bluetooth, microphone, speech, contacts, file
import/export, or generic device control.

We are disclosing the full list deliberately. Three of the eight actions read
device/user data (`clipboard`, `getLocation`, and `sensors`); they require an explicit,
persistent, user-revocable grant, and both are described below and in the
Permissions and privacy section. Nothing in this list is hidden behind a
generic capability name.

## Trust and runtime boundary

1. A network-managed HTML app must have an Ed25519-signed gateway manifest.
2. Every action must be declared in that signed manifest for the exact app
   action and origin.
3. Drel's build policy exposes only the eight actions listed above; all other
   Bridge actions are rejected before handler dispatch.
4. The page must be active in the foreground, and the call must consume a
   recent one-use touch gesture.
5. `haptic`, `vibrate`, `share`, `fullscreen` and `addToHomeScreen`
   write no
   persistent privacy grant. For these, a manifest declaration is an
   allowlist, not standing user consent.
6. `clipboard`, `getLocation` and `sensors` do require a persistent grant. The user
   approves each one explicitly, the grant is revocable at any time from
   Drel's permission center, and the permission center shows the active
   grant list.
7. A manifest update that removes an action also removes dependent future
   grant identity; legacy broad capability markers cannot authorize a v2
   action.

## Per-action behavior

| Action | Authorization | Review-visible behavior | Explicitly does not do |
|---|---|---|---|
| `haptic` | Declaration only | Brief tactile feedback after a foreground user tap | Access data, make network requests, or show a permission prompt |
| `vibrate` | Declaration only | Brief, bounded vibration after a foreground user tap | Play arbitrary sounds, loop indefinitely, or access data |
| `share` | Declaration only | Opens the native iOS share sheet with the page-provided content | Send content in the background, choose a destination, or retain the user's selection |
| `fullscreen` | Declaration only | Hides host navigation/status chrome and keeps a host-owned control with collapse, back-history, refresh, favorite and close actions | Rotate the device, trap the user, disable scrolling, or exit without the explicit close control |
| `sensors` | Persistent, revocable grant | Streams accelerometer or gyroscope samples at the page-requested interval after the user grants access and the page makes a foreground call; revoking the grant stops an active stream immediately, as do an explicit stop, page hide, or controller teardown | Read other sensors, retain motion history, or stream when the page is outside the active app session |
| `addToHomeScreen` | Declaration only | Adds the current page to the Drel app list, and separately to the iPhone Home Screen | Read user data, or add anything the user did not open from the app |
| `clipboard` | Persistent, revocable grant | Reads or writes the clipboard only after the user grants access; the grant is listed and revocable in Drel's permission center | Read the clipboard without a grant, or access the clipboard in the background |
| `getLocation` | Persistent, revocable grant | Requests the device location only after the user grants access, and shows the standard iOS location prompt; the grant is listed and revocable in Drel's permission center | Track location in the background, or access location without a grant |

### Where the grant-based actions are visible to the user

1. A trusted HTML app that declares `clipboard`, `getLocation`, or `sensors` and calls it
   after a foreground tap triggers Drel's own permission prompt.
2. Approving it creates a persistent grant for that app and origin.
3. Drel's permission center lists every active grant, shows its scope, and
   lets the user revoke it after an explicit confirmation.
4. Revoking the grant immediately blocks later calls and stops an active sensor stream; the app is not left
   holding a silent capability.

The grant list is stored on the device only. Drel does not upload clipboard
contents, location values, or grant state to the official service.

## Reviewer walkthrough

No account, login, purchase, subscription, or credentials are required.

### Existing Drel flows

1. Launch Drel and allow notifications if you want to test push delivery.
2. Use the built-in test-send controls to deliver a harmless test message.
3. Confirm notification permission remains optional and denied paths remain
   usable.

### Manifest v2 actions

The production walkthrough below must use the official signed gateway demo
app after the owner releases it. Do not substitute the simulator-only fixture.

1. Open the signed Manifest v2 demo app from Drel's trusted app list.
2. Tap the haptic or vibrate control and observe the brief feedback.
3. Tap the share control. Drel shows the iOS system share sheet; the reviewer
   may cancel without sharing anywhere.
4. Tap the fullscreen control. Host chrome disappears while the floating edge
   control remains available.
5. Tap the edge control once to expand it. The arrow collapses the control;
   the `×` closes the immersive page. A left-edge rightward swipe navigates
   the page's own history and does not close Drel or the page.
6. Tap the add-to-Home-Screen control. The page is offered to Drel's app
   list; the reviewer may decline.
7. Tap the clipboard control. Drel shows its own permission prompt naming
   the app and origin. Approve it, then observe the clipboard value appears
   in the page.
8. Tap the location control. Drel shows its own permission prompt, then the
   standard iOS location prompt. Approve or deny; both paths return to the
   page without an error screen.
9. Open the signed gyro demo, tap the sensor debug control, and start the
   accelerometer. Tilt the device and confirm the event count and game input
   follow the physical motion. This action has no privacy prompt or grant.
10. Open Drel's permission center. The clipboard and location grants for the
   demo app are listed with their scope.
11. Revoke the clipboard grant and confirm the confirmation prompt appears.
    Tap clipboard again in the demo app; the call is now rejected.

### Negative checks

- An undeclared action is rejected.
- Calling an approved action without a recent foreground tap is rejected.
- Ordinary web pages and offline packages do not receive the Bridge.
- The host action catalog contains only the eight listed actions.
- After a grant is revoked, later calls of that action are rejected.

## Permissions and privacy

Two of the eight actions reach user data, and both are declared above:

- `clipboard` reads or writes the clipboard, and `getLocation` reads the
  device location. Each requires a persistent, revocable grant that the user
  approves explicitly. Both grants are listed in Drel's permission center
  and can be revoked there at any time.
- The Store build keeps the matching iOS usage description for location.
  Drel does not access the clipboard or the location in the background, and
  it does not retain the returned values.

The remaining six actions do not read user data and do not create a
persistent grant. `share` is mediated each time by Apple's system sheet;
Drel does not record the shared payload or selected destination. `sensors`
streams CoreMotion samples only to the active page and keeps no motion
history.

The first 1.5.0 action train intentionally avoids other sensitive system
prompts: camera, photos, Bluetooth, microphone, speech, and contacts
are not enabled by Drel's host policy.

The linked SDK still contains generic handler code for developers building
other hosts. Drel's 1.5 Store build strips the deferred iOS purpose strings
and rejects those actions at the host allowlist before handler dispatch. The
upload analysis may therefore report references to Bluetooth APIs as
non-fatal warnings even though that capability cannot be invoked in Drel.

## Data-handling summary for the two data-reading actions

| Action | What is read | Where it goes | What is stored |
|---|---|---|---|
| `clipboard` | The clipboard content the user asked the page to read or write | Stays in the WebView; the page receives it in the page's own context | Nothing on the Drel service; the grant record is local |
| `getLocation` | The device location returned by the iOS location prompt | Stays in the WebView; the page receives it in the page's own context | Nothing on the Drel service; the grant record is local |

Neither value is forwarded to `https://api.drel.app` or any other Drel
service by the action itself.

## App Review recording outline

Record on a physical iPhone with the production-signed TestFlight build. Do
not show device tokens, personal push content, gateway secrets, or reviewer
test credentials.

1. 0–3s: Drel Home and optional notification-enabled state.
2. 3–8s: Open the signed Manifest v2 demo from the trusted app list.
3. 8–12s: Tap haptic/vibrate and caption that only brief feedback occurs.
4. 12–18s: Tap share, show the iOS system sheet, cancel the sheet.
5. 18–24s: Tap fullscreen, show the edge control, demonstrate arrow collapse,
   left-edge history back, and `×` close.
6. 24–30s: Tap add-to-Home-Screen, show that the app is offered to the Drel
   app list, and decline it.
7. 30–40s: Tap clipboard, show Drel's own permission prompt, approve it, and
   show the value in the page.
8. 40–50s: Tap location, show Drel's permission prompt and the iOS location
   prompt, and approve it.
9. 50–60s: Open the gyro demo, start the accelerometer, and show the debug
   event count plus tilt-driven movement.
10. 60–70s: Open Drel's permission center and show the two active grants.
11. 70–80s: Revoke the clipboard grant, then tap clipboard again and show
    that the call is rejected.
12. 80–90s: Show an undeclared-action rejection and state that the catalog is
    limited to these eight actions.

## Service and contact facts

- Official service: `https://api.drel.app`
- Support: `https://drel.app/support/`
- Privacy Policy: `https://drel.app/privacy/`
- Terms of Use: `https://drel.app/terms/`
- No login, account, purchase, subscription, advertising, or analytics is
  required for review.

## Preconditions before ASC use

- Owner approves this exact action catalog and copy.
- Production gateway serves signed demo apps whose manifests declare the
  eight review actions, using the wire action names
  (`getLocation`, not `location`).
- Physical-device TestFlight walkthrough confirms haptic/vibrate on supported
  hardware, the system share sheet, fullscreen, the host exit control,
  add-to-Home-Screen, the clipboard grant flow, the location grant flow, the
  revoke flow, and live accelerometer-driven game input.
- Record and privately attach the walkthrough only after those checks pass.
- Create or edit only the new 1.5.0 App Store version; do not modify Drel
  1.4.1 or its release state.
- The privacy policy page lists clipboard and location among the app's
  handled data, and matches this note.
