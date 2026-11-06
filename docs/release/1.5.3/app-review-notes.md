# Drel 1.5.3 App Review Notes

Status: owner-review draft for the 1.5.3 App Store submission. This release
contains no app changes: the binary is the same code train as the
`READY_FOR_SALE` 1.5.2 (build 138) release, re-uploaded as build 142 because
App Store Connect binds a build to a single version. The capability surface
below is unchanged from the shipped 1.5.2 build and is restated here so the
reviewer sees the exact, complete list.

## Summary

Drel is a developer push-notification utility and a container for HTML apps
that the user has explicitly trusted. The Store build exposes exactly nine
native actions, and no others:

- `haptic`
- `vibrate`
- `share`
- `fullscreen`
- `clipboard`
- `getLocation`
- `addToHomeScreen`
- `sensors`
- `audioLevel`

This is not a general JavaScript-to-native Bridge and it is not remotely
extensible. Ordinary web pages, strong-offline packages, and unregistered
apps do not receive the Bridge.

## Trust and runtime boundary

1. A network-managed HTML app must have an Ed25519-signed gateway manifest.
2. Every action must be declared in that signed manifest for the exact app
   action and origin.
3. Drel's build policy exposes only the nine actions listed above; all other
   Bridge actions are rejected before handler dispatch.
4. The page must be active in the foreground, and the call must consume a
   recent one-use touch gesture.
5. `haptic`, `vibrate`, `share`, `fullscreen`, `addToHomeScreen`, and
   `sensors` write no persistent privacy grant; a manifest declaration is an
   allowlist, not standing user consent.

## Permissions and privacy

- `clipboard` and `getLocation` read device/user data. Both require an
  explicit, persistent, user-revocable grant: Drel asks separately before a
  trusted app reads either, and the grant can be revoked at any time in the
  permission center, which stops further reads immediately.
- `audioLevel` exposes a live sound-level value so trusted web apps can drive
  sound-powered interactions (the Voice Jump and Dandelion demos shipped in
  1.5.2). It runs only after the user grants the system audio-input
  permission for Drel; without that grant the action is unavailable, and the
  grant can be revoked at any time in iOS Settings or Drel's permission
  center.
- No other sensitive capability is offered: the Store build does not enable
  camera scanning, photo library access, Bluetooth, speech recognition,
  contacts, file import/export, or generic device control.

## What changed in this submission

Nothing in the binary. 1.5.3 adds Japanese, Korean, and German App Store
metadata, refines the English listing, and switches the primary store locale
to English (US). Screenshots and the review account are unchanged from
1.5.2.
