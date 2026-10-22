#!/usr/bin/env bash
# Start the complete local acceptance environment for Drel.
#
# Brings up four things so a change can be judged the way a user would see it:
#
#   1. the three local services (backend :8080, fixtures :8081, prototype :8083)
#   2. the website preview on :8788 (reproduces the Cloudflare Pages _headers)
#   3. a signed local gateway, so the app can import a self-hosted gateway
#   4. the Drel app on a booted simulator
#
# Usage:
#   bash tools/preview-drel-env.sh            # start everything
#   bash tools/preview-drel-env.sh --no-app   # skip the simulator build
#   bash tools/preview-drel-env.sh --stop     # stop everything
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SITE_PORT=8788
BUILD_APP=1
SIM_UDID="${WBK_PREVIEW_SIM_UDID:-}"
APP_DD="/tmp/drel-preview-dd"

say() { printf '\n\033[0;34m== %s ==\033[0m\n' "$*"; }
ok()  { printf '\033[0;32m[OK]\033[0m %s\n' "$*"; }
bad() { printf '\033[0;31m[FAIL]\033[0m %s\n' "$*"; exit 1; }

stop_all() {
  say "Stopping the local environment"
  pkill -f "serve-drel-site.py" 2>/dev/null || true
  pkill -f "WebBridgeServer" 2>/dev/null || true
  bash scripts/services.sh stop >/dev/null 2>&1 || true
  ok "Stopped"
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-app) BUILD_APP=0; shift ;;
    --stop) stop_all ;;
    *) bad "Unknown argument: $1" ;;
  esac
done

# -- 1. Local services ------------------------------------------------------
say "Starting local services (:8080 / :8081 / :8083)"
bash scripts/services.sh start >/dev/null 2>&1 || bad "Failed to start the local services"
# `verify` writes a colored report; check the exit status rather than
# grepping a pipe, because `grep -q` closes the pipe early and `pipefail`
# would turn the resulting SIGPIPE into a false failure.
bash scripts/services.sh verify >"$ROOT/build/services-verify.log" 2>&1 \
  || bad "Service health check failed, see build/services-verify.log"
ok "All three services ready"

# -- 2. Website preview -----------------------------------------------------
say "Building and starting the website preview (:$SITE_PORT)"
bash tools/build-drel-site.sh >"$ROOT/build/drel-site-build.log" 2>&1 \
  || bad "Site build failed, see build/drel-site-build.log"
python3 tools/verify-drel-site.py --dir build/drel-site-staging >/dev/null \
  || bad "Site verification failed"
nohup python3 tools/serve-drel-site.py --port "$SITE_PORT" --dir build/drel-site-staging \
  >"$ROOT/build/drel-site-preview.log" 2>&1 &
for _ in $(seq 1 20); do
  sleep 0.3
  curl -fsS -m 2 "http://127.0.0.1:$SITE_PORT/health" >/dev/null 2>&1 && break
done
curl -fsS -m 3 "http://127.0.0.1:$SITE_PORT/health" >/dev/null 2>&1 \
  || bad "The website preview did not start, see build/drel-site-preview.log"
ok "Website preview: http://127.0.0.1:$SITE_PORT"

# -- 3. Signed gateway ------------------------------------------------------
say "Starting the signed local gateway"
# The stock local service runs without a signing key, so the app cannot
# import it. A temporary key makes the self-hosted gateway path testable.
if [[ ! -f /tmp/drel-preview-gw.key ]]; then
  openssl genpkey -algorithm ed25519 -out /tmp/drel-preview-gw.pem 2>/dev/null
  openssl pkey -in /tmp/drel-preview-gw.pem -outform DER 2>/dev/null \
    | tail -c 32 | base64 | tr '+/' '-_' | tr -d '=' > /tmp/drel-preview-gw.key
fi
GW_KEY="$(cat /tmp/drel-preview-gw.key)"

lsof -ti:8080 2>/dev/null | xargs kill -9 2>/dev/null || true
sleep 1
(
  cd "$ROOT/Server"
  GATEWAY_KEY_ID=gw-local-preview \
  GATEWAY_PRIVATE_KEY="$GW_KEY" \
  GATEWAY_PUBLIC_BASE_URL="http://127.0.0.1:8080" \
  GATEWAY_NAME="Local Preview Gateway" \
  GATEWAY_ID=local-preview \
  SERVER_PORT=8080 ADMIN_API_KEY=preview-admin-key \
  DATA_DIR="$ROOT/.data" \
  nohup .build/debug/WebBridgeServer >"$ROOT/build/backend-preview.log" 2>&1 &
)

GW_INFO=""
for _ in $(seq 1 30); do
  sleep 0.3
  # Assign to a variable instead of piping into `grep -q`: an early pipe close
  # turns into SIGPIPE, and `pipefail` would report a false failure.
  GW_INFO="$(curl -fsS -m 2 http://127.0.0.1:8080/api/v1/gateway 2>/dev/null || true)"
  [[ "$GW_INFO" == *publicKey* ]] && break
done
[[ "$GW_INFO" == *publicKey* ]] \
  || bad "The signed gateway did not start, see build/backend-preview.log"
ok "Signed gateway: http://127.0.0.1:8080"

# -- 4. The app on the simulator --------------------------------------------
if [[ "$BUILD_APP" == "1" ]]; then
  say "Building and installing Drel on the simulator"
  xcodebuild build -workspace Drel.xcworkspace -scheme Drel -sdk iphonesimulator \
    -arch arm64 -derivedDataPath "$APP_DD" CODE_SIGNING_ALLOWED=NO \
    >"$ROOT/build/preview-app-build.log" 2>&1 \
    || bad "App build failed, see build/preview-app-build.log"

  if [[ -z "$SIM_UDID" ]]; then
    SIM_UDID="$(xcrun simctl list devices booted 2>/dev/null | grep -oE '[0-9A-F-]{36}' | head -1)"
  fi
  [[ -n "$SIM_UDID" ]] \
    || bad "No booted simulator. Run xcrun simctl boot <device> first."

  APP="$(find "$APP_DD" -name "Drel.app" -maxdepth 5 | head -1)"
  xcrun simctl install "$SIM_UDID" "$APP" || bad "Install failed"
  xcrun simctl launch "$SIM_UDID" com.webbridgekit.superapp >/dev/null || bad "Launch failed"
  ok "Drel is running on simulator $SIM_UDID"
else
  ok "Skipped the app build and install"
fi

# -- Summary ----------------------------------------------------------------
say "Local acceptance environment ready"
cat <<EOF

  Website preview   http://127.0.0.1:$SITE_PORT/
  Docs overview     http://127.0.0.1:$SITE_PORT/docs/
  App guide         http://127.0.0.1:$SITE_PORT/docs/app/
  Bridge API        http://127.0.0.1:$SITE_PORT/docs/bridge/
  Live demos        http://127.0.0.1:$SITE_PORT/test/
  Action demo       http://127.0.0.1:$SITE_PORT/test/actions/
  Offline package   http://127.0.0.1:$SITE_PORT/test/offline/

  Backend           http://127.0.0.1:8080/health
  Static fixtures   http://127.0.0.1:8081/
  Prototype         http://127.0.0.1:8083/

  Stop: bash tools/preview-drel-env.sh --stop
EOF
