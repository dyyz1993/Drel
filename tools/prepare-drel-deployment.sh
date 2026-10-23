#!/usr/bin/env bash
# Prepare a self-hosted Drel deployment on this machine.
#
# The script is deliberately split into steps so the operator can run, check
# and stop at any point. It never invents a secret: it generates what it can
# locally (the Ed25519 gateway key) and refuses to continue when something
# only the operator can supply (the APNs provider key).
#
# Usage:
#   bash tools/prepare-drel-deployment.sh gateway    # option B: gateway only
#   bash tools/prepare-drel-deployment.sh relay      # option A: push only
#   bash tools/prepare-drel-deployment.sh both       # option C: one host
#   bash tools/prepare-drel-deployment.sh --domain push.example.com
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MODE=""
DOMAIN=""
OUT_DIR="$ROOT/build/deployment"

say() { printf '\n\033[0;34m== %s ==\033[0m\n' "$*"; }
ok()  { printf '\033[0;32m[OK]\033[0m %s\n' "$*"; }
bad() { printf '\033[0;31m[FAIL]\033[0m %s\n' "$*"; exit 1; }
warn(){ printf '\033[0;33m[NOTE]\033[0m %s\n' "$*"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    gateway|relay|both) MODE="$1"; shift ;;
    --domain) DOMAIN="$2"; shift 2 ;;
    *) bad "Unknown argument: $1" ;;
  esac
done

[[ -n "$MODE" ]] || {
  cat <<'EOF'
Usage:
  bash tools/prepare-drel-deployment.sh <gateway|relay|both> [--domain <your-hostname>]

  gateway   Option B - the gateway only (app identity, offline packages, actions)
  relay     Option A - the push relay only (your own push address)
  both      Option C  - both roles on one host
EOF
  exit 2
}

mkdir -p "$OUT_DIR"

# ── Step 1: the gateway signing key ────────────────────────────────
say "Step 1 - the Ed25519 gateway signing key"
if [[ "$MODE" == "relay" ]]; then
  warn "Option A does not need a gateway key. Skipping."
else
  KEYFILE="$OUT_DIR/gateway-ed25519.pem"
  if [[ -f "$KEYFILE" ]]; then
    ok "Reusing $KEYFILE"
  else
    openssl genpkey -algorithm ed25519 -out "$KEYFILE"
    ok "Generated $KEYFILE"
  fi
  # The server wants the raw 32-byte seed, Base64URL encoded.
  SEED="$(openssl pkey -in "$KEYFILE" -outform DER 2>/dev/null | tail -c 32 | base64 | tr '+/' '-_' | tr -d '=')"
  printf '%s' "$SEED" > "$OUT_DIR/gateway-private-key.txt"
  chmod 600 "$OUT_DIR/gateway-private-key.txt"
  ok "Wrote the Base64URL seed to $OUT_DIR/gateway-private-key.txt (mode 600)"
  warn "This file IS the private key. Move it to your server's secret store and delete the local copy."
fi

# ── Step 2: the environment file ───────────────────────────────────
say "Step 2 - the environment file"
ENVFILE="$OUT_DIR/drel.env"
if [[ -f "$ENVFILE" ]]; then
  ok "Reusing $ENVFILE"
else
  if [[ -n "$DOMAIN" ]]; then
    PUBLIC="https://$DOMAIN"
  else
    PUBLIC="https://push.example.com"
  fi

  {
    echo "# Drel self-hosted deployment - generated $(date -u +%Y-%m-%d)"
    echo "# Fill in every value marked TODO, then copy this file to your server."
    echo ""
    if [[ "$MODE" != "relay" ]]; then
      echo "## Gateway (option B and C)"
      echo "ADMIN_API_KEY=TODO-generate-a-long-random-value"
      echo "GATEWAY_ID=example-gateway"
      echo "GATEWAY_NAME=Example Gateway"
      echo "GATEWAY_PUBLIC_BASE_URL=$PUBLIC"
      echo "GATEWAY_KEY_ID=gw-$(date -u +%Y%m%d)"
      echo "GATEWAY_PRIVATE_KEY=TODO-paste-the-seed-from-step-1"
      echo ""
    fi
    if [[ "$MODE" != "gateway" ]]; then
      echo "## Push relay (option A and C)"
      echo "DREL_SELF_HOSTED_NAME=Drel Self-hosted Push"
      echo "DREL_SELF_HOSTED_PUBLIC_BASE_URL=$PUBLIC"
      echo "DREL_DATA_DIR=/var/lib/drel-selfhosted"
      echo "APNS_ENVIRONMENT=production"
      echo "APNS_TOPIC=com.webbridgekit.superapp"
      echo "APNS_KEY_ID=TODO-your-apns-key-id"
      echo "APNS_TEAM_ID=TODO-your-apple-team-id"
      echo "APNS_KEY_PATH=/run/secrets/drel/AuthKey_TODO.p8"
      echo ""
    fi
    echo "## TLS (Caddy reads this)"
    echo "DREL_SELF_HOSTED_DOMAIN=${DOMAIN:-push.example.com}"
    echo "DREL_SELF_HOSTED_ACME_EMAIL=TODO-you@example.com"
  } > "$ENVFILE"
  ok "Wrote $ENVFILE"
  warn "Fill in the TODO values before starting the service."
fi

# ── Step 3: the deployment command ─────────────────────────────────
say "Step 3 - how to start it"
cat <<EOF

  Option A (relay only), Go binary:
    bash tools/build-drel-selfhosted-native.sh
    scp Server/native/dist/drel-selfhosted root@server:/usr/local/bin/
    scp Server/native/drel-selfhosted.service root@server:/etc/systemd/system/
    # copy $ENVFILE to /etc/drel-selfhosted/drel-selfhosted.env, then:
    systemctl daemon-reload && systemctl enable --now drel-selfhosted

  Option A (relay only), Docker:
    cd Server
    cp $ENVFILE .env
    docker compose -f docker-compose.self-hosted-native.yml up -d --build

  Option B or C (gateway, or both), Docker with automatic TLS:
    cd Server
    cp $ENVFILE .env
    docker compose -f docker-compose.self-hosted.yml up -d

  Behind an existing Nginx instead of Caddy:
    cd Server
    cp $ENVFILE .env
    docker compose -f docker-compose.self-hosted-nginx.yml up -d
    # then adapt Server/nginx/drel-self-hosted.conf.template

EOF

# ── Step 4: verification ───────────────────────────────────────────
say "Step 4 - verify it"
cat <<EOF

  curl $PUBLIC/health
    -> { "status": "ok", "apnsReady": true }
       apnsReady MUST be true, otherwise the relay refuses pairing on purpose.

  curl $PUBLIC/api/v1/gateway
    -> { "publicKeyId": "...", "publicKey": "..." }
       Copy these into the phone's gateway import.

EOF

ok "Prepared $OUT_DIR"
echo ""
echo "Next: fill in the TODO values in $ENVFILE, deploy it, then import the"
echo "address on the phone under Settings."
