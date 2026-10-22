---
name: drel-app-development
description: Build a web app that runs in Drel — an iOS container for HTML apps and a Bark-compatible push client. Use when a developer wants to ship a web app inside Drel, make it work offline, route a push into a specific screen, or call a declared native action. Covers the app manifest, the signed gateway manifest, strong offline packages, push routes, and graceful fallback when the native bridge is absent.
---

# Drel App Development

Build a **normal, standards-compatible web app first**. A Drel app is not a
proprietary format: any browser must still be able to load it. Use Drel-specific
metadata only for the opt-in, verified offline-installation path.

## Compatibility contract

| Item | Current public contract |
| --- | --- |
| Skill | `1.1.0` |
| Drel app | `1.5.x` |
| Offline package | `1` |
| Container protocol | `1` |
| Native actions | Manifest v2, 7 declared actions |

## Choose the smallest applicable path

- **A normal web destination** — use HTTPS and ordinary web APIs. A push may
  open it. Nothing else to build.
- **A named Drel application** — add a standard Web App Manifest and have an
  operator sign a parent Drel manifest. Read
  [web app manifest](references/web-app-manifest.md).
- **A durable offline app** — additionally publish the verified resource
  manifest and the `drel_offline` declaration. Read
  [offline packages](references/offline-packages.md) before generating files.
- **A push into an app route** — send a supported `appId + route + params`
  message. Read [push and testing](references/push-and-testing.md).
- **A native action** — declare it in the signed manifest, then call it behind
  a fallback. See the action contract below.

## The app is independent of the push service

This is the single most common misunderstanding. Say it out loud to the
developer:

- The app is a **web page on any static host**. It needs no server of its own.
- The **push service** only delivers a wake-up (a URL, or `appId + route`). It
  is never required for the app to work.
- The **gateway** signs app manifests. It is needed only for app-center
  identity, offline packages and native actions.
- A gateway and a push relay **may share one host, domain and certificate, or
  run entirely apart**. Both shapes are supported.

Never tell a developer they need a push server to ship an app.

## Non-negotiable boundaries

1. **Write the fallback first.** Every native call must be behind a
   `typeof window.BarkBridge?.call === 'function'` check with a working
   non-native path. A page that breaks without the bridge is not a valid Drel
   app.
2. **A push supplies navigation data, not authority.** It must never approve an
   action, grant permission, install a package, update a package, or create an
   app without a foreground user action.
3. **A Web App Manifest does not make an app offline.** Never describe Service
   Worker or WebKit cache as Drel's durable offline mode.
4. **Treat query parameters, `DrelRuntime` and the User-Agent as hints for
   layout and compatibility only.** They are not authentication or
   authorization.
5. **Keep access tokens, one-time codes and device push addresses out of
   `start_url`, screenshots, fixtures, logs, and generated documentation.**

## Declared native actions (Manifest v2)

Drel 1.5 exposes seven actions. Each must be declared in the signed manifest
with an exact origin list, a unique `purposeId`, a human-readable `purpose`
and a scope.

| Action | Scope | Behaviour |
| --- | --- | --- |
| `haptic` | `appSession` | Brief tactile feedback after a user tap |
| `vibrate` | `appSession` | Brief, bounded vibration |
| `share` | `appSession` | Opens the native iOS share sheet; the user picks the destination |
| `fullscreen` | `appSession` | Hides host chrome, keeps a host-owned edge return control |
| `clipboard` | `always` | Reads or writes the clipboard behind a native prompt |
| `location` | `always` | Reads the position behind a native prompt |
| `addToHomeScreen` | `appSession` | Adds the registered app to the Drel home screen |

Declaration shape:

```json
{
  "action": "clipboard",
  "origins": ["https://app.example.com"],
  "purposeId": "paste-order-number",
  "purpose": "把订单号粘贴到表单里",
  "scope": "always"
}
```

Rules: `purposeId` is unique per app (a grant is bound to it); `origins` must
be a non-empty subset of `allowedOrigins`; grant actions use `always`, others
use `appSession`; a declaration is an allowlist, **not** user consent.

**Not available**: camera scanning, photo library, Bluetooth, microphone,
speech, contacts, motion, file import/export, generic device control, and any
general JavaScript-to-native bridge. Do not invent these.

### Calling an action

```js
const bridgeAvailable = typeof window.BarkBridge?.call === 'function';

if (bridgeAvailable) {
  try {
    const result = await window.BarkBridge.call('clipboard', { action: 'read' });
    if (result?.success) {
      input.value = result.data;
    } else {
      showManualPasteHint();
    }
  } catch {
    showManualPasteHint();
  }
}
```

### Runtime detection

```js
const runtime = window.DrelRuntime;
const isInstalledOffline = runtime?.isOfflinePackage === true;
const bridgeVersion = Number(runtime?.bridgeVersion ?? 0);
```

Feature-detect. Never sniff the user agent. The app version is not an
authorization level.

## Working procedure

1. Define a stable `appId`, an HTTPS origin, a scoped start route, and an
   ordinary Web App Manifest. Remove credentials and temporary query parameters
   from the start route. `start_url` and `scope` must not carry a query string.
2. Add safe-area insets and `prefers-color-scheme` support before anything
   else. A page that renders badly in Drel will be rejected by the user before
   any feature is noticed.
3. For offline support, publish immutable versioned assets. Produce the exact
   resource-manifest bytes and hashes before signing the parent manifest; do
   not mutate a file at an already published version URL. **A missing chunk
   means a white screen offline** — include every asset, and use relative
   paths with no CDN dependency.
4. Give users explicit actions to download, update, or delete a package. A
   failed update must leave the prior complete version launchable.
5. Keep live data on the network and label cached data honestly. The package
   holds the UI shell, not the data.
6. Send a test push to the exact `appId + route`; test both the online fallback
   before installation and the local package launch after installation.
7. Validate on a physical iPhone: cold start in airplane mode, local
   interaction, recovery after the network returns, interrupted update, invalid
   hash rejection, deletion, and upgrade preservation. The simulator does not
   prove APNs or airplane-mode release behavior.

## Container adaptation

```html
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
```

```css
body {
  padding-top: env(safe-area-inset-top);
  padding-bottom: env(safe-area-inset-bottom);
}
```

Launch parameters arrive as ordinary query parameters:

```js
const params = new URLSearchParams(location.search);
const orderId = params.get('orderId');
```

## Reference fixtures

Live examples that prove each path:

| Fixture | Proves |
| --- | --- |
| `https://drel.app/test/offline/` | Strong offline install and hash verification |
| `https://drel.app/test/offline-network/` | Offline fallback with honest caching |
| `https://drel.app/test/actions/` | Declared native actions and the consent prompt |
| `https://drel.app/test/template/` | A reusable app skeleton and its packaging |

## When requirements exceed this skill

Do not invent an API to solve a request for native camera, scanning, clipboard,
file export, contacts, notifications, or background execution. Those are a
future Drel security-and-review decision, not a compatibility shortcut.
Explain the missing capability and keep the web app functional without it.
