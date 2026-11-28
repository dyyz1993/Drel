# Self-hosting Drel: gateway, push relay, or both

Use this when the user wants to run Drel's services on their own
infrastructure: a private push relay, a private gateway for app identity and
strong offline packages, or both.

The application itself is never part of a self-hosting deployment. It is a web
page on any static host and needs no server of its own.

## Choose the smallest option that satisfies the request

| The user wants | Option | Deploy |
| --- | --- | --- |
| To send notifications to their own phone, and keep using the hosted apps | **A** | Go relay only |
| A private app market: app identity, strong offline packages, declared native actions | **B** | Go server only |
| Both | **C** | One Go server, or split Go services across hosts |

Ask which one they mean before producing commands. The difference matters:
option A does not need an Ed25519 gateway key, and option B does not need an
APNs `.p8`.

## Two facts that decide the architecture

1. **The Go binary serves both roles from one 6 MB file.** Since 2026-10-23 it
   implements `/api/v1/gateway` and `/api/v1/html-apps`. Set `GATEWAY_KEY_ID`
   and `GATEWAY_PRIVATE_KEY` to enable the gateway half.
2. **The Swift server was removed on 2026-11-28.** Existing operators migrate
   to Go; its historical signatures remain compatible with stored phone trust.

## Prepare first, always

```bash
bash tools/prepare-drel-deployment.sh <gateway|relay|both> --domain <hostname>
```

It generates the Ed25519 gateway key (option B and C), writes an environment
file with the TODO values marked, and prints the deployment and verification
commands for the chosen shape. Never hand-write the key generation or the
compose invocation from memory — use the script so the seed encoding and the
file layout match what the server expects.

## Deployment shapes

| Shape | Stack | Use it for |
| --- | --- | --- |
| Go binary + systemd | Go 1.23, static, 6 MB, push + gateway | Recommended for every new deployment |
| Go binary + Docker | same, scratch image | Want Compose, still no dependencies |
| Cloudflare Worker | Workers + Durable Objects | Push only, no server at all |

The gateway cannot run on Cloudflare: it needs an Ed25519 private key for
long-lived signing and durable application manifests. A Worker can do the
push half — `infra/cloudflare/drel-api-proxy/` is a running example that keeps
the device registry in a Durable Object and signs APNs JWTs from a Worker
secret. For the gateway half on a server, prefer the Go binary.

## Fully self-hosted: their own build, their own key, direct to APNs

Apple routes a notification by topic, and the topic is the app's bundle id.
A relay can therefore only deliver to a phone whose app was signed for the
same topic. The stock Drel build uses `com.webbridgekit.superapp`, so a
fully independent deployment needs its own build.

Generate one:

```bash
bash tools/rebrand-drel-selfhosted.sh \
  --bundle-id com.acme.drel \
  --team-id YOUR_TEAM_ID \
  --key-id YOUR_APNS_KEY_ID \
  --gateway https://hub.acme.com
```

It copies the tree and rewrites every identity: bundle id, app group,
keychain service, URL scheme, the APNs topic, and the compiled-in default
gateway. The official checkout is never modified. The output tree carries a
`BUILD-NOTES.md` with the remaining steps.

The operator then needs, from the Apple developer portal:

- an App ID with the new bundle id and Push Notifications enabled;
- an APNs key (the `.p8` is downloadable only once);
- an App Group matching the new bundle id, enabled for the app and its
  Notification Service Extension.

The relay then signs the provider JWT itself and posts straight to APNs.
There is no official relay in that path.

If the operator has no Apple developer account, first offer the community-key
route in “Option A”: the stock Drel App can pair with their relay, which uses
Drel's intentionally published production-only topic key. A gateway-only
deployment is the alternative when notifications may pass through the official
channel after registration.

## Option A — push relay only

The user gets a push address on their own hostname, usable by any
Bark-compatible script.

### Build and install the Go binary

```bash
bash tools/build-drel-selfhosted-native.sh
scp Server/native/dist/drel-selfhosted root@server:/usr/local/bin/
scp Server/native/drel-selfhosted.service root@server:/etc/systemd/system/
```

`/etc/drel-selfhosted/drel-selfhosted.env` (the service listens on
`127.0.0.1:8080` only):

```dotenv
DREL_LISTEN_ADDR=127.0.0.1:8080
DREL_SELF_HOSTED_PUBLIC_BASE_URL=https://push.example.com
DREL_DATA_DIR=/var/lib/drel-selfhosted
APNS_ENVIRONMENT=production
APNS_TOPIC=com.webbridgekit.superapp
APNS_KEY_ID=4M53447M36
APNS_TEAM_ID=B45VZCNYU3
APNS_KEY_PATH=/etc/drel-selfhosted/secrets/AuthKey_4M53447M36.p8
```

```bash
systemctl daemon-reload && systemctl enable --now drel-selfhosted
curl https://push.example.com/health   # apnsReady must be true
```

### Docker alternative

```bash
cd Server
cp .env.example .env
docker compose -f docker-compose.self-hosted-native.yml up -d --build
```

The `.p8` is mounted read-only. Never `COPY` it into an image.

### Public exposure and the domain

The service listens on `127.0.0.1` only, so no inbound 443 or 8080 rule is
needed. Three ways to give it a name:

| Method | What to do | Best for |
| --- | --- | --- |
| Cloudflare Tunnel | Install `cloudflared`, point the public hostname at `push.example.com`, set the origin service to `http://127.0.0.1:8080` | No public IP, no certificate to manage |
| Existing reverse proxy | Forward public HTTPS traffic to `http://127.0.0.1:8080` | The host already runs Nginx or Caddy |

### Verify before pairing

```bash
curl https://push.example.com/health
# { "status": "ok", "apnsReady": true }
```

`apnsReady` must be true. A relay without a valid signer returns 503 and
refuses pairing on purpose — that is the correct behaviour, not a bug to work
around.

### Pairing

The user scans or pastes `https://push.example.com` in
**Drel → Settings → Self-hosted push**. The client validates the health
endpoint, then registers the APNs token with that server only. The resulting
push address is `https://push.example.com/<device-key>`.

### The APNs authority boundary

Direct APNs delivery needs a signer authorized for the app's topic. The stock
Drel build can use Drel's intentionally published community key because it is
bound to the official topic and Apple production. A fully independent relay
for another bundle requires the operator's own signed Drel build and their own
private topic-specific `.p8`. Say this plainly rather than implying that the
community key covers a rebranded install. Without a valid key the relay must
fail closed: it reports `apnsReady: false` and refuses pairing.

## Option B — gateway only

The user keeps using any compatible push relay — including the hosted one —
but controls app identity, offline packages and native action declarations.
For the hosted push service, the gateway must first be registered with the
official channel before it can deliver app notifications; see
`docs/guides/deployment.md`, section “3.6 让应用通知经由官方通道送达”.

### Generate the signing key

```bash
openssl genpkey -algorithm ed25519 -out gateway-ed25519.pem
openssl pkey -in gateway-ed25519.pem -outform DER 2>/dev/null \
  | tail -c 32 | base64 | tr '+/' '-_' | tr -d '='
```

The output is `GATEWAY_PRIVATE_KEY` (a Base64URL 32-byte raw seed). The public
key is served by the gateway itself:

```bash
curl https://hub.example.com/api/v1/gateway
# { "publicKeyId": "...", "publicKey": "..." }
```

### Configure and start

`Server/.env`:

```dotenv
ADMIN_API_KEY=<custom admin key>
GATEWAY_ID=example-gateway
GATEWAY_NAME=Example Team Gateway
GATEWAY_PUBLIC_BASE_URL=https://hub.example.com
GATEWAY_KEY_ID=gw-2026-10-23
GATEWAY_PRIVATE_KEY=<generated>
```

```bash
cd Server
docker compose -f docker-compose.self-hosted-native.yml up -d --build
```

Use an existing Cloudflare Tunnel or reverse proxy when the host already owns
public TLS.

### Register an application

```bash
curl -X POST https://hub.example.com/api/v1/html-apps \
  -H "Authorization: Bearer <ADMIN_API_KEY>" \
  -H "content-type: application/json" \
  -d '{"schemaVersion":"1","appId":"com.example.orders",
       "name":"Order Assistant",
       "startURL":"https://app.example.com/app/index.html",
       "allowedOrigins":["https://app.example.com"],
       "capabilities":[], "capabilities_v2":[],
       "routes":["/app/index.html"],
       "cache":{"strategy":"networkOnly","version":"1","persistent":false}}'
```

The response carries the Ed25519 signature. For a strong offline package,
bind the resource manifest as well — see
[offline packages](offline-packages.md).

### Import on the phone

Drel → Settings → Gateway → scan or paste:

```json
{
  "schemaVersion": "1",
  "id": "example-gateway",
  "displayName": "Example Team Gateway",
  "baseURL": "https://hub.example.com",
  "healthEndpoint": "/health",
  "manifestEndpoint": "/api/v1/html-apps",
  "publicKeyId": "gw-2026-10-23",
  "publicKey": "<Base64URL 32-byte raw public key>"
}
```

The client verifies the health JSON, the response origin, every app manifest,
the origin restrictions, the key id and the manifest signature, then shows a
report. It saves nothing until the user confirms. Changing the gateway or the
key identity drops the old grants — grants never follow to another identity.

## Option C — both

### C1 · One host (simplest)

One Go service provides both roles, because it registers the gateway and
push routes together.

Add the APNs settings to the same `Server/.env`:

```dotenv
APNS_KEY_ID=4M53447M36
APNS_TEAM_ID=B45VZCNYU3
APNS_TOPIC=com.webbridgekit.superapp
APNS_ENVIRONMENT=production
```

```bash
cd Server
docker compose -f docker-compose.self-hosted-native.yml up -d --build
```

One hostname then serves everything:

- `https://hub.example.com/<key>` — the push address
- `https://hub.example.com/api/v1/html-apps` — the app manifests
- `https://hub.example.com/health` — health

The optional Node admin console adds a graphical push console at
`/admin-push` with a device list.

### C2 · Split hosts

Run a Go gateway on one host and a Go relay for push on another. The two are
independent trust relationships: the phone imports
each address separately, so an outage in one does not affect the other.

Use this when different teams own the two jobs, or when you want the failure
domains separated. The cost is two services and two certificates.

## Safety rules to repeat every time

1. **Never publish an operator-owned APNs `.p8`.** A topic-scoped key still
   lets the holder forge alerts to known device tokens. The repository's
   community key is the intentional exception: official topic only, production
   only, and independently revocable.
2. **The gateway configuration carries public endpoints and a public key
   only.** Never put an APNs token, device key, API secret, admin token,
   password or private key in it — the client rejects those fields before
   parsing.
3. **A production gateway must be an exact HTTPS origin.** Only development
   builds accept `localhost` over HTTP.
4. **A push address is a bearer capability.** Keep it out of source control,
   screenshots and public URLs.

## Do not

- Do not tell the user the community key can cover a rebranded Drel install.
  It cannot; a rebranded install needs its own topic-specific `.p8`, and every
  relay must fail closed without a valid signer.
- Do not skip the "readiness" check. A relay that reports `apnsReady: false`
  and refuses pairing is behaving correctly.
- Do not suggest the application needs changes. It never does.
