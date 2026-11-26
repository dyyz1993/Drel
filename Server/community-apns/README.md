# Community APNs key

`AuthKey_4M53447M36.p8` is an Apple Push Notification service (APNs) provider
key. Unlike every other `.p8` in this project, it is **published here on
purpose**.

## Why it is public

The stock Drel app is signed by team `B45VZCNYU3`. Apple only accepts a push
for an app when it is signed by a key from the team that owns the app, so a
self-hosted push relay needs a key from that team to reach the stock app —
even when the relay belongs to someone else.

Publishing this key lets anyone run the Go relay (`Server/native`) or their
own instance of the Cloudflare Worker and keep using the stock Drel app
**without an Apple Developer account**. Their notifications travel from their
own relay straight to Apple. They do not pass through the official
`api.drel.app` service and do not consume its quota.

## What it can and cannot do

| | |
|---|---|
| Key ID | `4M53447M36` |
| Team ID | `B45VZCNYU3` |
| Type | Topic-specific, registered to exactly one topic |
| Topic | `com.webbridgekit.superapp` — the stock Drel app |
| Environment | Production only: TestFlight and App Store builds, not debug builds |
| Revocation | Any time, from the Apple Developer portal, without touching any other key |

- It is registered to one topic, so Apple refuses pushes for any other app
  of the team.
- It is refused on the sandbox endpoint (`403 BadEnvironmentKeyInToken`), so
  it cannot reach debug builds.
- Whoever holds it can send notifications to devices whose APNs tokens they
  know. A relay only learns the tokens of devices that paired with it, which
  in practice is the operator's own users.
- It grants no read access of any kind.

Verified on 2026-11-27 against APNs with a non-existent device token: the
production endpoint accepts the key for `com.webbridgekit.superapp`
(`400 BadDeviceToken`, the token is fake) and the sandbox endpoint refuses it.

## Using it

The relay reads `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_KEY_PATH`, `APNS_TOPIC`
and `APNS_ENVIRONMENT`:

```sh
APNS_ENVIRONMENT=production
APNS_TOPIC=com.webbridgekit.superapp
APNS_KEY_ID=4M53447M36
APNS_TEAM_ID=B45VZCNYU3
APNS_KEY_PATH=/etc/drel-selfhosted/secrets/AuthKey_4M53447M36.p8
```

`tools/prepare-drel-deployment.sh relay|both` and
`Server/docker-compose.self-hosted-native.yml` default to these values.
The step-by-step guide is `docs/guides/deployment.md`, 方案 A.

Running your own build of the app (`tools/rebrand-drel-selfhosted.sh`)?
That bundle ID belongs to your team, so this key cannot sign for it. Create
your own APNs key instead.

## Revoking or replacing it (maintainers)

1. Revoke: Apple Developer → Certificates, Identifiers & Profiles → Keys →
   `Drel Community Push Production` (`4M53447M36`) → Revoke. Every relay
   still using it stops delivering until it picks up the replacement.
2. Rotate without an outage: register a new topic-specific key for
   `com.webbridgekit.superapp` in Production → replace this file and the Key
   ID in `Server/docker-compose.self-hosted-native.yml`,
   `tools/prepare-drel-deployment.sh`, `tools/build-drel-selfhosted-package.sh`
   and `docs/guides/deployment.md`, and the pinned hash under
   `PUBLIC_CREDENTIALS` in `tools/verify-repo-hygiene.py` → publish → revoke
   the old key.

`tools/verify-repo-hygiene.py` pins this file by SHA-256 and refuses any
other `.p8` in the repository. Never put a team-scoped key or an App Store
Connect API key here.

---

**中文说明**：这是有意公开的 APNs 钥匙，只对官方 Drel App
（`com.webbridgekit.superapp`）的生产环境有效，别的 App 和沙盒都推不了，
可随时单独吊销。没有 Apple 开发者账号的人用它就能「官方 App + 自建推送
中继」，推送直连 Apple，不经过官方服务器。详见 `docs/guides/deployment.md`。
