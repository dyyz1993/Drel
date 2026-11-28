# Drel 1.5.6 App Review Notes

Status: prepared 2026-11-28 for build 161 (TestFlight). Not submitted to App
Review yet; 1.5.5 is still in review.

## What changed

1.5.6 changes how Drel behaves when a push asks it to open an HTML app that
it cannot verify or that is not registered:

- It now falls back to opening the app's website in the normal in-app browser
  and shows a dismissible notice. This is strictly a plain web page: the
  normal WebKit view, no manifest loader, no Bridge capabilities, no offline
  package.
- When no address is available it shows a plain-language reason with a link
  to the local diagnostics screen.
- The My Apps section reports the real reason when the app service cannot be
  reached, and offers an "enter an app address" screen that opens a URL or
  verifies an app id before adding it.

No entitlement, permission prompt or data collection was added, changed or
removed. The capability surface is identical to 1.5.5.

## Capability surface

The Store build exposes the same 10 native actions as 1.5.5:

- `haptic`, `vibrate`, `share`, `fullscreen`, `addToHomeScreen` — transient,
  in-session, no standing grant
- `clipboard`, `getLocation` — require explicit persistent, user-revocable grant
- `sensors` — transient accelerometer/gyroscope stream, no standing grant
- `getCapabilities` — read-only query for actions declared and granted to the
  current trusted app
- `audioLevel` — live microphone sound level, requires system microphone
  permission + explicit grant

## Web fallback is not a trust bypass

A fallback target is only ever opened as a normal web page. Unverified catalog
data is used solely to pick the address, and derived addresses are restricted
to public HTTPS hosts (loopback, link-local, private, CGNAT, multicast,
`.local` and IPv6 are rejected; URLs with userinfo are rejected). Nothing from
an unverified app reaches the trust registry, the permission ledger or the
offline installer.
