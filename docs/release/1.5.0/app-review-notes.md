# Drel 1.5.0 App Review Notes

Status: owner-review draft for the future 1.5.0 App Store version. Build
`1.5.0 (90)` is the TestFlight implementation under review, but the reviewer
demo path still needs the production gateway manifest and a physical-device
recording before this text is pasted into App Store Connect.

## Summary

Drel is a developer push-notification utility and a container for HTML apps
that the user has explicitly trusted. Version 1.5.0 adds a narrowly scoped
Manifest v2 action runtime for four low-impact actions only:

- `haptic`
- `vibrate`
- `share`
- `fullscreen`

This is not a general JavaScript-to-native Bridge and it is not remotely
extensible. Ordinary web pages, strong-offline packages, and unregistered apps
do not receive the Bridge. Drel 1.5 does not enable camera scanning, photo
library access, Bluetooth, microphone, speech, contacts, location, motion,
file import/export, or generic device control.

## Trust and runtime boundary

1. A network-managed HTML app must have an Ed25519-signed gateway manifest.
2. Every action must be declared in that signed manifest for the exact app
   action and origin.
3. Drel's build policy exposes only the four actions listed above; all other
   Bridge actions are rejected before handler dispatch.
4. The page must be active in the foreground, and the call must consume a
   recent one-use touch gesture.
5. No persistent privacy grant is written for these four actions. A manifest
   declaration is an allowlist, not standing user consent.
6. A manifest update that removes an action also removes dependent future
   grant identity; legacy broad capability markers cannot authorize a v2
   action.

## Per-action behavior

| Action | Review-visible behavior | Explicitly does not do |
|---|---|---|
| `haptic` | Brief tactile feedback after a foreground user tap | Access data, make network requests, or show a permission prompt |
| `vibrate` | Brief, bounded vibration after a foreground user tap | Play arbitrary sounds, loop indefinitely, or access data |
| `share` | Opens the native iOS share sheet with the page-provided content | Send content in the background, choose a destination, or retain the user's selection |
| `fullscreen` | Hides host navigation/status chrome and keeps a host-owned edge return control | Rotate the device, trap the user, disable scrolling, or dismiss Drel |

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
4. Tap the fullscreen control. Host chrome disappears while a draggable edge
   return control remains available.
5. Tap the edge control once to expand it, then tap the return area to leave
   fullscreen without closing the HTML app.
6. From app details, observe that the declared action inventory is visible.

### Negative checks

- An undeclared action is rejected.
- Calling an approved action without a recent foreground tap is rejected.
- Ordinary web pages and offline packages do not receive the Bridge.
- The host action catalog contains only the four listed actions.

## Permissions and privacy

The first 1.5.0 action train intentionally avoids sensitive system prompts:
camera, photos, Bluetooth, microphone, speech, contacts, location, and motion
are not enabled by Drel's host policy. Share is mediated each time by Apple's
system sheet; Drel does not record the shared payload or selected destination.

The linked SDK still contains generic handler code for developers building
other hosts. Drel's 1.5 Store build strips the deferred iOS purpose strings
and rejects those actions at the host allowlist before handler dispatch. The
upload analysis may therefore report references to Bluetooth/location APIs as
non-fatal warnings even though those capabilities cannot be invoked in Drel.

## App Review recording outline

Record on a physical iPhone with the production-signed TestFlight build. Do
not show device tokens, personal push content, gateway secrets, or reviewer
test credentials.

1. 0–3s: Drel Home and optional notification-enabled state.
2. 3–8s: Open the signed Manifest v2 demo from the trusted app list.
3. 8–12s: Tap haptic/vibrate and caption that only brief feedback occurs.
4. 12–18s: Tap share, show the iOS system sheet, cancel the sheet.
5. 18–24s: Tap fullscreen, show the edge return control, leave fullscreen.
6. 24–30s: Show an undeclared-action rejection or state that the catalog is
   limited to these four actions.

## Service and contact facts

- Official service: `https://api.drel.app`
- Support: `https://drel.app/support/`
- Privacy Policy: `https://drel.app/privacy/`
- Terms of Use: `https://drel.app/terms/`
- No login, account, purchase, subscription, advertising, or analytics is
  required for review.

## Preconditions before ASC use

- Owner approves this exact action catalog and copy.
- Production gateway serves a signed demo app whose manifest declares only the
  four review actions.
- Physical-device TestFlight walkthrough confirms haptic/vibrate on supported
  hardware, the system share sheet, fullscreen, and the host exit control.
- Record and privately attach the walkthrough only after those checks pass.
- Create or edit only the new 1.5.0 App Store version; do not modify Drel
  1.4.1 or its release state.
