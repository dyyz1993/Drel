#!/usr/bin/env bash
# Deploy the Drel Go server to a self-hosted machine.
#
# The script produces a complete, ready-to-run deployment package:
#
#   dist/drel-selfhosted          the static Linux binary
#   dist/drel-selfhosted.service  the systemd unit
#   dist/drel.env                 the environment file to fill in
#   dist/reverse-proxy.conf       an Nginx or Caddy snippet
#   dist/DEPLOY.md                the steps for the target machine
#
# The binary is CGO-free and statically linked, so the target machine needs
# no Docker, no Swift toolchain and no language runtime at all.
#
# Usage:
#   bash tools/build-drel-selfhosted-package.sh --arch arm64 --domain hub.example.com
#   bash tools/build-drel-selfhosted-package.sh --arch amd64 --domain hub.example.com --out /tmp/pkg
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ARCH="amd64"
DOMAIN=""
OUT=""
GATEWAY_ONLY=0

say() { printf '\n\033[0;34m== %s ==\033[0m\n' "$*"; }
ok()  { printf '\033[0;32m[OK]\033[0m %s\n' "$*"; }
bad() { printf '\033[0;31m[FAIL]\033[0m %s\n' "$*"; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --arch) ARCH="$2"; shift 2 ;;
    --domain) DOMAIN="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    *) bad "Unknown argument: $1" ;;
  esac
done

[[ "$ARCH" =~ ^(amd64|arm64|arm)$ ]] || bad "Unsupported architecture: $ARCH"
[[ -n "$DOMAIN" ]] || bad "Pass --domain <your-hostname>."
OUT="${OUT:-$ROOT/build/selfhosted-package}"

command -v go >/dev/null 2>&1 || bad "Go is required to build the binary."

say "Building the static Linux binary for $ARCH"
mkdir -p "$OUT/dist"
GOOS=linux GOARCH="$ARCH" CGO_ENABLED=0 \
  go build -trimpath -ldflags='-s -w' \
  -o "$OUT/dist/drel-selfhosted" "$ROOT/Server/native/main.go"
[[ -f "$OUT/dist/drel-selfhosted" ]] || bad "The build produced no binary."
ok "Built $(ls -lh "$OUT/dist/drel-selfhosted" | awk '{print $5}') static binary"

# Confirm it really is a static Linux executable.
if command -v file >/dev/null 2>&1; then
  file "$OUT/dist/drel-selfhosted" | grep -qi "statically linked" \
    || bad "The binary is not statically linked."
  ok "Verified: statically linked, no runtime dependencies"
fi

say "Copying the systemd unit and the reverse-proxy snippet"
cp "$ROOT/Server/native/drel-selfhosted.service" "$OUT/dist/"
cp "$ROOT/Server/nginx/drel-self-hosted.conf.template" "$OUT/dist/reverse-proxy.nginx.conf" 2>/dev/null || true

cat > "$OUT/dist/reverse-proxy.caddyfile" <<EOF
# Caddy: automatic TLS. The whole Drel surface is proxied, including the
# gateway routes and the Bark-compatible push paths.
$DOMAIN {
    encode zstd gzip
    reverse_proxy 127.0.0.1:8080
}
EOF

say "Generating the environment file"
GATEWAY_KEY="$(
  openssl genpkey -algorithm ed25519 -out /tmp/drel-pkg-gw.pem 2>/dev/null
  openssl pkey -in /tmp/drel-pkg-gw.pem -outform DER 2>/dev/null \
    | tail -c 32 | base64 | tr '+/' '-_' | tr -d '='
)"
rm -f /tmp/drel-pkg-gw.pem

cat > "$OUT/dist/drel.env" <<EOF
# Drel self-hosted server — generated $(date -u +%Y-%m-%d)
# Fill in every TODO, then: chmod 600 drel.env
#
# The GATEWAY_PRIVATE_KEY below is the Ed25519 private key. It signs the
# application manifests the phone trusts. Anyone holding it can publish
# applications to your gateway, so treat it like a password.

# ── Where the phone reaches this server ─────────────────────────────
DREL_SELF_HOSTED_PUBLIC_BASE_URL=https://$DOMAIN
DREL_SELF_HOSTED_NAME=Drel Self-hosted
DREL_LISTEN_ADDR=127.0.0.1:8080
DREL_DATA_DIR=/var/lib/drel-selfhosted

# ── The gateway (app identity, offline packages, native actions) ───
GATEWAY_ID=$DOMAIN
GATEWAY_NAME=Drel Gateway
GATEWAY_PUBLIC_BASE_URL=https://$DOMAIN
GATEWAY_KEY_ID=gw-$(date -u +%Y%m%d)
GATEWAY_PRIVATE_KEY=$GATEWAY_KEY

# ── Management authentication ───────────────────────────────────────
# Required for POST and DELETE on /api/v1/html-apps.
ADMIN_API_KEY=TODO-generate-a-long-random-value

# ── APNs delivery (only needed to deliver to a phone) ───────────────
APNS_ENVIRONMENT=production
APNS_TOPIC=com.webbridgekit.superapp
APNS_KEY_ID=TODO-your-apns-key-id
APNS_TEAM_ID=TODO-your-apple-team-id
APNS_KEY_PATH=/etc/drel/secrets/AuthKey_TODO.p8
EOF
chmod 600 "$OUT/dist/drel.env"
ok "Wrote $OUT/dist/drel.env (mode 600)"

cat > "$OUT/DEPLOY.md" <<EOF
# Deploying Drel on this machine

The package contains a single static binary. The machine needs no Docker,
no Go, no Swift and no language runtime.

## 1. Copy the files

\`\`\`bash
scp dist/drel-selfhosted        user@$DOMAIN:/usr/local/bin/drel-selfhosted
scp dist/drel-selfhosted.service user@$DOMAIN:/etc/systemd/system/
scp dist/drel.env               user@$DOMAIN:/etc/drel/drel.env
\`\`\`

## 2. Fill in the environment file

\`\`\`bash
ssh user@$DOMAIN
sudo mkdir -p /etc/drel /etc/drel/secrets /var/lib/drel-selfhosted
sudo chmod 600 /etc/drel/drel.env
sudo nano /etc/drel/drel.env
\`\`\`

Set \`ADMIN_API_KEY\` to a long random value. If you deliver to a phone, also
put your \`AuthKey_XXXX.p8\` in \`/etc/drel/secrets/\` and set \`APNS_KEY_PATH\`
to its path. Keep the file mode at 0640.

## 3. Start the service

\`\`\`bash
sudo systemctl daemon-reload
sudo systemctl enable --now drel-selfhosted
sudo systemctl status drel-selfhosted
\`\`\`

## 4. Put it behind HTTPS

Caddy (automatic TLS) — copy \`dist/reverse-proxy.caddyfile\` to
\`/etc/caddy/Caddyfile\`.

Nginx — copy \`dist/reverse-proxy.nginx.conf\` to
\`/etc/nginx/conf.d/$DOMAIN.conf\` and replace the placeholders, then
\`sudo nginx -t && sudo systemctl reload nginx\`.

## 5. Verify

\`\`\`bash
curl https://$DOMAIN/health
# { "status": "ok", "version": "...", "apnsReady": true }

curl https://$DOMAIN/api/v1/gateway
# { "publicKeyID": "...", "publicKey": "..." }
\`\`\`

Then run the full contract suite from the repository:

\`\`\`bash
bash tools/verify-drel-backend-contract.sh \\
  --base https://$DOMAIN \\
  --admin-key "\$(the ADMIN_API_KEY you set)"
\`\`\`

## 6. Import it on the phone

Drel → Settings → Self-hosted Push (or Gateway) → scan or paste
\`https://$DOMAIN\`.
EOF

say "Package ready"
ok "$OUT"
echo
echo "  dist/drel-selfhosted          the binary"
echo "  dist/drel-selfhosted.service  systemd unit"
echo "  dist/drel.env                 environment file (fill in the TODOs)"
echo "  dist/reverse-proxy.caddyfile   Caddy config"
echo "  dist/reverse-proxy.nginx.conf  Nginx config"
echo "  DEPLOY.md                      the steps for the target machine"
