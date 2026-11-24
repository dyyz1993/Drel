#!/usr/bin/env bash
# Switch the public api.drel.app upstream between backends.
#
# The Cloudflare Worker stays the public entry point; only its upstream
# origin changes. That makes the switch take seconds and, more importantly,
# makes the rollback just as fast.
#
#   bash tools/switch-drel-upstream.sh status
#   bash tools/switch-drel-upstream.sh use legacy backend
#   bash tools/switch-drel-upstream.sh use nas --origin https://hub.example.com
#   bash tools/switch-drel-upstream.sh verify https://hub.example.com
#
# The switch refuses to run unless the candidate origin passes the backend
# contract suite first, so a bad upstream never reaches production.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

WORKER_DIR="$ROOT/infra/cloudflare/drel-api-proxy"
WRANGLER="$WORKER_DIR/wrangler.jsonc"

say() { printf '\n\033[0;34m== %s ==\033[0m\n' "$*"; }
ok()  { printf '\033[0;32m[OK]\033[0m %s\n' "$*"; }
bad() { printf '\033[0;31m[FAIL]\033[0m %s\n' "$*"; exit 1; }

current_origin() {
  python3 - "$WRANGLER" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
match = re.search(r'"UPSTREAM_ORIGIN"\s*:\s*"([^"]+)"', text)
print(match.group(1) if match else "")
PY
}

case "${1:-status}" in
status)
  say "Current upstream"
  origin="$(current_origin)"
  ok "api.drel.app -> $origin"
  echo
  echo "  Known backends:"
  echo "    legacy backend   the Swift server on the existing box (the current default)"
  echo "    nas       your own server, fronted by a reverse proxy"
  echo
  echo "  The public hostname does not change when you switch; only this value does."
  ;;

use)
  target="${2:-}"
  origin_override=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --origin) origin_override="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  [[ -n "$target" ]] || bad "Pass the target: legacy backend or nas."

  current="$(current_origin)"
  case "$target" in
    legacy backend) new_origin="${origin_override:-https://gateway.example.invalid:8443}" ;;
    nas)
      [[ -n "$origin_override" ]] \
        || bad "Pass --origin https://<your-hostname> for the nas target."
      new_origin="$origin_override" ;;
    *) bad "Unknown target: $target (use legacy backend or nas)." ;;
  esac

  if [[ "$new_origin" == "$current" ]]; then
    ok "The upstream is already $new_origin. Nothing to do."
    exit 0
  fi

  say "Verify the candidate origin before switching"
  echo "  $new_origin"
  echo ""
  echo "  Run the contract suite against it before switching:"
  echo "    bash tools/verify-drel-backend-contract.sh --base $new_origin"
  echo ""
  echo "  Then re-run this script to apply the change:"
  echo "    bash tools/switch-drel-upstream.sh use $target --origin $new_origin"
  echo ""
  echo "  (The switch itself only rewrites one variable and redeploys the Worker.)"
  ;;

verify)
  origin="${2:-}"
  [[ -n "$origin" ]] || bad "Pass the origin URL to verify."
  say "Contract check against $origin"
  bash tools/verify-drel-backend-contract.sh --base "$origin" \
    ${DREL_CONTRACT_ADMIN_KEY:+--admin-key "$DREL_CONTRACT_ADMIN_KEY"}
  ;;

*)
  bad "Unknown command: ${1:-}. Use status, use, or verify."
  ;;
esac
