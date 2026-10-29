# Drel 1.5.0 build 119

Date: 2026-10-29

Build 119 adds key-scoped private HTML app registration and fixes the inbox
app-open activation gap.

## Package identity

```text
CFBundleShortVersionString = 1.5.0
CFBundleVersion = 119
TestFlight build ID = pending upload
IPA SHA-256 = pending upload
```

## What changed

- The official gateway accepts HTML app registration bound to a paired
  device key, without the admin key. Private manifests are invisible to
  anonymous catalog listings and visible only to the owning key
  (`GET /api/v1/html-apps?key=…`), capped at 20 manifests per key. Deployed
  as Worker version `2026.10.29-keybind`.
- The app scopes official-gateway catalog fetches with the device push
  identity, so key-private manifests reach the phone through the same
  on-demand activation path as global ones. SDK endpoint paths now accept
  query strings (origin checks unchanged).
- Opening an app from an inbox message detail routes through the push
  catalog coordinator: the manifest is fetched and activated before the
  open, removing the misleading `应用未注册` dead end.

## Local and package gates

Detailed commands and pass counts live in
[`drel-1-5-0-119-keybind/verification.md`](../../testing/results/drel-1-5-0-119-keybind/verification.md).

```text
Worker unit tests:         50/50 passed
Gateway contract gate:     5/5 passed (api.drel.app)
DrelTests:                 35/35 passed
Simulator release build:   green
```

## Production dependency

The deployed Worker is `e9a18441-8a5f-49dc-884e-db2afcb4e4a7`
(`2026.10.29-keybind`). Official demo manifests continue to be served from
built-in storage; the key-binding feature is additive and the anonymous
catalog shape is unchanged, so build 118 and earlier keep working against
this deployment.
