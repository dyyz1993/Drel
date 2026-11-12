# Drel 1.5.4 App Review Notes

Status: owner-review draft for the 1.5.4 App Store submission.

## What changed

One new entitlement was added:
`com.apple.developer.usernotifications.time-sensitive`. This allows
notifications with `interruption-level: time-sensitive` (set by the sender
via `level=timeSensitive`) to break through Focus mode and the silent switch.
No Bridge actions, permission surfaces, or app logic changed from the
previously approved 1.5.3 build.

## Capability surface

The Store build exposes 10 native actions. Version 1.5.3 added the permission
status query; 1.5.4 restores `audioLevel`:

- `haptic`, `vibrate`, `share`, `fullscreen`, `addToHomeScreen` — transient, in-session, no standing grant
- `clipboard`, `getLocation` — require explicit persistent, user-revocable grant
- `sensors` — transient accelerometer/gyroscope stream, no standing grant
- `getCapabilities` — read-only query for actions declared and granted to the current trusted app
- `audioLevel` — live microphone sound level, requires system microphone permission + explicit grant

## Time Sensitive Notifications

This entitlement does not change what data the app accesses or what actions
it can perform. It solely changes the presentation priority for notifications
already approved by the user. Users retain full control:

- Focus mode can be configured to allow or suppress time-sensitive
  notifications per Focus profile.
- The system Settings → Notifications → Drel screen allows users to disable
  "Time Sensitive Notifications" entirely for this app.
- No push bypasses the user's notification permission grant.
