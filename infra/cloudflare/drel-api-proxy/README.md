# Official Drel API Worker

`api.drel.app` is the public origin for the official Drel push and HTML-app
gateway. Since 2026-10-26 this Cloudflare Worker serves the API directly; it no
longer proxies to the retired legacy-infra Swift relay. The `UPSTREAM_ORIGIN`
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

## OAuth / PKCE authorization v1

`drel-oauth-pkce-v1` is disabled by default and owns reserved
`/oauth/*`, `/.well-known/oauth-authorization-server`, and `/.well-known/jwks.json`
paths. With `DREL_OAUTH_AT_EDGE` set to any value other than `1`, those paths
always return `404`; they never fall through to a legacy upstream. With the flag
on, discovery reports `temporarily_unavailable` until the signing key, grant and
rate-limit Durable Objects, and Apple App Attest verifier are all configured.

Required runtime values:

- `DREL_OAUTH_AT_EDGE=1` — explicitly enables the OAuth routes.
- `DREL_OAUTH_ATTESTATION_MODE=apple-app-attest` — production device proof mode.
- `DREL_OAUTH_DEVICE_ATTESTATION_VERIFIER_URL` — HTTPS service that receives the
  submitted App Attest payload plus public JWK and returns
  `{ valid: true, publicKeyThumbprint }`; the thumbprint must bind the verified
  attestation to the exact registration key.
- `DREL_OAUTH_SIGNING_KEY` — base64url 32-byte Ed25519 seed.
- `DREL_OAUTH_SIGNING_KEY_ID` — stable key identifier published in JWKS and JWTs.
- `DREL_OAUTH_SIGNING_KEY_REGISTRY_VERSION` — increment for every key-registry
  change.
- `DREL_OAUTH_RETIRED_SIGNING_KEYS` — optional JSON array of retired
  `{ kid, x }` public keys. JWKS keeps them published during token lifetime.
- `DREL_OAUTH_ADMIN_API_KEY` — timing-safe compared credential for
  `GET /oauth/v2/admin/status`.

The only registered first-party client is `app.vot.example.invalid` with
`drel://oauth/callback` and `https://vot.example.invalid:8443`. Authorization codes
last 10 minutes and are consumed atomically by `OAuthGrantRegistry`; access JWTs
are EdDSA-signed, expire after five minutes, and bind the device key with
`cnf.jkt`. Device registration uses explicit debug fixtures only when
`DREL_OAUTH_ATTESTATION_MODE=debug-fixture` and
`DREL_OAUTH_ALLOW_DEBUG_ATTESTATION=1`; both settings must never be enabled in
production.

`DREL_OAUTH_GRANT_REGISTRY` and `DREL_OAUTH_RATE_LIMITER` map to the two v5
Durable Object classes. Per-bucket limits can be tuned with
`DREL_OAUTH_<BUCKET>_LIMIT`; an unavailable limiter fails closed with
`temporarily_unavailable` rather than silently bypassing rate protection.
