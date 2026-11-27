# Drel 1.5.5 App Review Notes

Status: notes for the 1.5.5 App Store submission (build 160), prepared
2026-11-27.

## What changed

One entitlement was added since the version currently on the App Store
(1.5.3): `com.apple.developer.usernotifications.time-sensitive`. This allows
notifications with `interruption-level: time-sensitive` (set by the sender via
`level=timeSensitive`) to break through Focus mode and the silent switch.

The rest of 1.5.5 is a set of fixes to how Drel opens HTML apps from push
notifications and to how strong-offline packages are launched, downloaded and
diagnosed:

- A push launch is the single explicit cold-start destination, so the app no
  longer opens a second, normal page after the pushed one.
- A strong-offline package whose local entrypoint fails to load falls back to
  its signed online start URL.
- On a confirmed offline cold start, an installed package that passes
  integrity verification opens even when a newer version exists.
- Offline package downloads show the verified total size and progress, and
  the update action is offered only for strictly newer remote versions.
- A local-only diagnostics screen in Settings records per-launch stages of
  offline app launches. It stores no message content and never leaves the
  device.

No Bridge action, permission surface, or data collection was added. See the
capability surface below.

## Capability surface

The Store build exposes 10 native actions. Version 1.5.3 added the permission
status query; 1.5.5 restores `audioLevel`:

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

## Relationship to 1.5.4

App Store Connect approved 1.5.4 as build 143 on 2026-11-10. That build
predates the fixes listed above and was never released; the App Store still
serves 1.5.3. 1.5.5 is the first Store release that contains them, so its
What's New describes the whole distance from 1.5.3.
