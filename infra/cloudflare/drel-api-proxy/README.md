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
- `DREL_REGISTERED_GATEWAYS` — the JSON-array allowlist of self-hosted gateways
  that may send app notifications through the official channel. It is a registry,
  not a private key.

The GitHub Actions deployment is deliberately limited to
`CLOUDFLARE_ACCOUNT_ID` and an account/zone-scoped `CLOUDFLARE_API_TOKEN`. GitHub
deploys source but cannot read or replace APNs secrets.

## Registered gateway push

A self-hosted gateway can send an app notification through the official channel
only after its origin is registered in `DREL_REGISTERED_GATEWAYS`. The secret is
a JSON array:

```json
[
  {
    "origin": "https://hub.example.com",
    "keyId": "gw-2026-11-27",
    "publicKey": "<base64url of the 32-byte raw Ed25519 public key>"
  }
]
```

`origin` must use https. An unset or empty secret means no gateway is
registered. A gateway publishes `publicKeyID` and `publicKey` from
`GET https://<gateway>/api/v1/gateway`; the gateway operator gives that response
to the official-channel operator, who stores it in the secret.

The gateway must use JSON `POST https://api.drel.app/push` with `deviceKey` and
`drelSourceChannel: "drel.selfhosted.<gateway-origin>"`. The request includes:

- `X-Drel-Gateway-Timestamp` — Unix seconds, within 10 minutes of server time.
- `X-Drel-Gateway-Signature` — base64url of Ed25519 over
  `UTF-8("drel.gateway-push.v1\n" + timestamp + "\n" + hex SHA-256 of the raw
  request body)`, signed with the 32-byte seed stored as
  `GATEWAY_PRIVATE_KEY`.
- `X-Drel-Gateway-Key-Id` — optional.

Once accepted, the tag is relayed to the phone in its canonical form
(`drel.selfhosted.` plus the lowercase origin without a trailing slash), so a
gateway's messages always land in the same self-hosted channel.

`Server/examples/drel-official-gateway-push.mjs` builds and signs this request;
`DREL_PUSH_URL` overrides the endpoint. Bark-style query-parameter URLs cannot
carry the source tag. Unregistered, unsigned, stale, or invalid gateway pushes
return 403. A `DREL_REGISTERED_GATEWAYS` value that is set but is not a JSON
array returns 503 instead of silently unregistering every gateway. Ordinary
official-identity pushes may not name an HTML app unless
that app is an official built-in app or is registered with the official gateway
and visible to that device; the official gateway answers 403 otherwise, and
503 while its manifest registry cannot be reached. End-to-end-encrypted pushes are
opaque to the server and are therefore outside this allowlist. Official-channel
deliveries consume the official channel's request quota.

## Deployment

### Deploying your own instance

The committed `wrangler.jsonc` is the production configuration: it owns the
`api.drel.app` custom domain and the `drel-api-proxy` worker name. To deploy an
independent copy, change both before the first deploy:

```bash
npx wrangler login
# In wrangler.jsonc: set "name" to your own worker name, remove the "routes"
# block, and set "workers_dev": true (or point "routes" at a zone you own).
npm run test
npm run check
npx wrangler secret put APNS_AUTH_KEY_P8      # plus APNS_KEY_ID / APNS_TEAM_ID / APNS_TOPIC
npm run deploy
```

Durable Object migrations in the file create their own storage per worker, so
an independent instance never shares state with the official deployment.

### Official deployment

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
