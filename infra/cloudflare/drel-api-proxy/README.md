# Official Drel API Worker

`api.drel.app` is the public origin for the official Drel push and HTML-app
gateway. Since 2026-10-26 this Cloudflare Worker serves the API directly; it no
longer proxies to the retired legacy backend Swift relay. The `UPSTREAM_ORIGIN`
variable stays commented in `wrangler.jsonc` only as an explicit rollback
switch and must not be re-enabled for normal production traffic.

The Worker also contains the **disabled-by-default**
`drel.managed-encrypted-push.v1` service. When deliberately enabled, only
`/managed-push/*` and `/.well-known/drel-managed-push.json` expose that
service. It stores the APNs device token plus the iPhone's X25519 public key in
a Durable Object and signs an opaque APNs request with the Drel-operated
credential. The Worker never accepts `title`, `body`, URL, or other plaintext
fields at that endpoint.

## Secret boundary

Store these **only as Cloudflare Worker secrets**, never in Git, GitHub Actions
variables, build logs, or `.dev.vars`:

- `DREL_MANAGED_PUSH_ENABLED` — exact value `1` enables the managed surface.
- `APNS_AUTH_KEY_P8` — the topic-specific Apple provider key, including PEM armor.
- `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_TOPIC` — signing identity metadata;
  production Drel uses `com.webbridgekit.superapp`.
- `DREL_PUSH_AT_EDGE` — exact value `1` serves the official push surface at the edge.

The GitHub Actions deployment is deliberately limited to
`CLOUDFLARE_ACCOUNT_ID` and an account/zone-scoped `CLOUDFLARE_API_TOKEN`. GitHub
deploys source but cannot read or replace APNs secrets.

## Deployment

```bash
cd infra/cloudflare/drel-api-proxy
npm run test
npm run check
npm run deploy
```

The `custom_domain` route owns `api.drel.app`; do not add a direct CNAME to a
self-hosted relay or the retired `:8443` Swift service.

## Verification

```bash
curl -sS https://api.drel.app/health
curl -sSI https://api.drel.app/health
npm run test:approval
```

The health response must contain `servedBy: "edge"` and the current
`DREL_EDGE_VERSION`. Before changing the app's bundled default URL, also verify
`/register`, push routing, and `/api/v1/html-apps`. `/ws/stream` belonged to the
retired Swift relay and is intentionally not an official Worker route.

## Approval state

`ApprovalRegistry` is a Durable Object keyed by approval `requestId`. Native
`poll` and `webhook` approvals are recorded after APNs accepts the push;
`thirdParty` approvals are render-only and never create an official status row.
Authenticated clients use:

```text
GET  /api/v1/approvals/{requestId}
POST /api/v1/approvals/{requestId}/respond
```

Both require `Authorization: Bearer <deviceKey>`. The first valid response wins,
increments `revision`, and later responses return `409`. Expired requests become
`expired`; records survive Worker restarts in Durable Object storage.
