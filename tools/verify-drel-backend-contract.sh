#!/usr/bin/env bash
# Contract test for Drel's HTTP surface.
#
# The same suite runs against ANY Drel backend — the portable Go binary, the
# Swift server, or the Cloudflare Worker — so "the two implementations are
# compatible" is a measured fact rather than a claim.
#
# The suite exercises the routes an operator and a phone actually touch:
#
#   GET    /health                       service readiness
#   GET    /api/v1/gateway               gateway metadata and Ed25519 public key
#   POST   /api/v1/html-apps             register an application manifest
#   GET    /api/v1/html-apps             list the signed manifests
#   GET    /api/v1/html-apps/{appId}     fetch one signed manifest
#   DELETE /api/v1/html-apps/{appId}     remove it
#   POST   /push                         the JSON push endpoint
#   GET    /<key>/<title>/<body>         the Bark-compatible push path
#
# Every manifest is verified with OpenSSL against the public key the backend
# published, so a signature that only the backend can produce is caught.
#
# Usage:
#   bash tools/verify-drel-backend-contract.sh --base http://127.0.0.1:8080
#   bash tools/verify-drel-backend-contract.sh --base https://push.example.com \
#        --admin-key "$ADMIN_KEY" --write-report build/reports/contract.md
#
# Exit codes: 0 pass, 1 fail, 77 skip (prerequisites missing).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BASE_URL=""
ADMIN_KEY=""
REPORT_PATH=""
EXPECT_VERSION=""

say() { printf '\033[0;34m== %s ==\033[0m\n' "$*"; }
ok()  { printf '\033[0;32m[OK]\033[0m %s\n' "$*"; }
bad() { printf '\033[0;31m[FAIL]\033[0m %s\n' "$*"; FAILED=$((FAILED + 1)); }
note() { printf '\033[0;33m[NOTE]\033[0m %s\n' "$*"; }

FAILED=0
PASSED=0
ROWS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE_URL="$2"; shift 2 ;;
    --admin-key) ADMIN_KEY="$2"; shift 2 ;;
    --write-report) REPORT_PATH="$2"; shift 2 ;;
    --expect-version) EXPECT_VERSION="$2"; shift 2 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

[[ -n "$BASE_URL" ]] || { echo "Usage: --base <url> [--admin-key <key>] [--write-report <path>]" >&2; exit 2; }
BASE_URL="${BASE_URL%/}"

command -v curl >/dev/null 2>&1 || { echo "SKIP: curl is required." >&2; exit 77; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 is required." >&2; exit 77; }
command -v openssl >/dev/null 2>&1 || { echo "SKIP: openssl is required to verify signatures." >&2; exit 77; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

record() {
  # record <name> <expected> <actual>
  ROWS+=("| $1 | $2 | $3 |")
}

# ── helpers ────────────────────────────────────────────────────────────
status_of() { curl -s -o /dev/null -w '%{http_code}' -m 15 "$@"; }

json_field() { python3 -c "
import json, sys
try:
    print(json.load(open(sys.argv[1])).get(sys.argv[2], ''))
except Exception:
    print('')
" "$1" "$2"; }

APP_ID="contract-$(date +%s)-$$"

MANIFEST=$(cat <<JSON
{
  "schemaVersion": "1",
  "appId": "$APP_ID",
  "name": "Contract Test App",
  "startURL": "https://app.example.com/index.html",
  "allowedOrigins": ["https://app.example.com"],
  "capabilities": [],
  "capabilities_v2": [
    {"action": "haptic", "origins": ["https://app.example.com"],
     "purposeId": "contract-haptic", "purpose": "Contract haptic check",
     "scope": "appSession"}
  ],
  "routes": ["/index.html"],
  "cache": {"strategy": "networkOnly", "version": "1", "persistent": false}
}
JSON
)

say "Contract suite against $BASE_URL"

# ── 1. health ──────────────────────────────────────────────────────────
code=$(status_of "$BASE_URL/health")
body="$(curl -s -m 15 "$BASE_URL/health")"
if [[ "$code" == "200" ]]; then
  version="$(echo "$body" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("version",""))' 2>/dev/null || echo '')"
  if [[ -n "$version" ]]; then
    ok "health 200 (version=$version)"
    record "GET /health" "200 + version" "200 + version=$version"
  else
    ok "health 200"
    record "GET /health" "200 + version" "200, no version field"
  fi
  PASSED=$((PASSED + 1))
  if [[ -n "$EXPECT_VERSION" && "$version" != "$EXPECT_VERSION" ]]; then
    bad "health version is '$version', expected '$EXPECT_VERSION'"
    record "GET /health version" "$EXPECT_VERSION" "$version"
  fi
else
  bad "health returned $code"
  record "GET /health" "200" "$code"
fi

# ── 2. gateway discovery ───────────────────────────────────────────────
code=$(status_of "$BASE_URL/api/v1/gateway")
curl -s -m 15 "$BASE_URL/api/v1/gateway" > "$WORK/gateway.json"
if [[ "$code" == "200" ]]; then
  pub="$(json_field "$WORK/gateway.json" publicKey)"
  key_id="$(json_field "$WORK/gateway.json" publicKeyID)"
  manifest_path="$(json_field "$WORK/gateway.json" manifestPath)"
  health_path="$(json_field "$WORK/gateway.json" healthPath)"
  if [[ -n "$pub" && -n "$key_id" && "$manifest_path" == "/api/v1/html-apps" && "$health_path" == "/health" ]]; then
    ok "gateway discovery 200 (keyID=$key_id)"
    record "GET /api/v1/gateway" "200 + publicKey + keyId + paths" "200, keyId=$key_id"
    PASSED=$((PASSED + 1))
  else
    bad "gateway discovery shape is wrong"
    record "GET /api/v1/gateway" "200 + publicKey + keyId + paths" "200 but incomplete"
  fi
else
  bad "gateway discovery returned $code"
  record "GET /api/v1/gateway" "200" "$code"
fi

# ── 3. register a manifest (auth) ─────────────────────────────────────
auth_args=()
if [[ -n "$ADMIN_KEY" ]]; then
  auth_args=(-H "Authorization: Bearer $ADMIN_KEY")
else
  auth_args=(-H "Authorization: Bearer contract-test")
fi
code=$(curl -s -o "$WORK/saved.json" -w '%{http_code}' -m 15 \
  -X POST "$BASE_URL/api/v1/html-apps" \
  -H "content-type: application/json" "${auth_args[@]}" \
  --data "$MANIFEST")
if [[ "$code" == "200" ]]; then
  ok "register manifest 200"
  record "POST /api/v1/html-apps" "200 + signature" "200"
  PASSED=$((PASSED + 1))
elif [[ "$code" == "401" ]]; then
  note "register returned 401 (admin key required); skipping the signed-manifest checks"
  record "POST /api/v1/html-apps" "200 + signature" "401 (no valid admin key)"
else
  bad "register returned $code"
  record "POST /api/v1/html-apps" "200 + signature" "$code"
fi

# ── 4. signature verification with OpenSSL ─────────────────────────────
if [[ "$code" == "200" && -n "$pub" ]]; then
  # Rebuild the unsigned payload exactly the way the phone does, extract the
  # signature and the public key, and verify with OpenSSL — a third party
  # independent of both the backend implementation and this script.
  python3 - "$WORK/saved.json" "$WORK/gateway.json" "$WORK" <<'PY'
import base64, json, sys

saved_path, gateway_path, work = sys.argv[1], sys.argv[2], sys.argv[3]

manifest = json.load(open(saved_path))
unsigned = {k: v for k, v in manifest.items() if k != "signature"}
canonical = json.dumps(unsigned, ensure_ascii=False, sort_keys=True,
                       separators=(",", ":")).encode("utf-8")
open(work + "/canonical.json", "wb").write(canonical)

signature = manifest.get("signature") or {}
if signature.get("algorithm") != "ed25519":
    raise SystemExit("signature algorithm is not ed25519: %r" % signature)
if not signature.get("keyId"):
    raise SystemExit("signature has no keyId: %r" % signature)
raw = base64.urlsafe_b64decode(signature["value"] + "=" * (-len(signature["value"]) % 4))
open(work + "/canonical.json.sig", "wb").write(raw)

config = json.load(open(gateway_path))
public = base64.urlsafe_b64decode(config["publicKey"] + "=" * (-len(config["publicKey"]) % 4))
if len(public) != 32:
    raise SystemExit("publicKey is not 32 bytes")
spki = bytes.fromhex("302a300506032b6570032100") + public
pem = ("-----BEGIN PUBLIC KEY-----\n"
       + base64.encodebytes(spki).decode()
       + "-----END PUBLIC KEY-----\n")
open(work + "/pub.pem", "w").write(pem)
PY
  if openssl pkeyutl -verify -pubin -inkey "$WORK/pub.pem" \
       -keyform PEM -rawin -in "$WORK/canonical.json" \
       -sigfile "$WORK/canonical.json.sig" >/dev/null 2>&1; then
    ok "Ed25519 signature verifies with OpenSSL against the published public key"
    record "signature (OpenSSL)" "verifies" "verifies"
    PASSED=$((PASSED + 1))
  else
    bad "the published signature does not verify with OpenSSL"
    record "signature (OpenSSL)" "verifies" "does not verify"
  fi
fi

# ── 5. list and fetch ─────────────────────────────────────────────────
code=$(status_of "$BASE_URL/api/v1/html-apps")
if [[ "$code" == "200" ]]; then
  count=$(curl -s -m 15 "$BASE_URL/api/v1/html-apps" | python3 -c '
import json,sys
try: print(len(json.load(sys.stdin).get("manifests", [])))
except Exception: print(0)')
  ok "list manifests 200 ($count manifest(s))"
  record "GET /api/v1/html-apps" "200 + manifests[]" "200, $count manifest(s)"
  PASSED=$((PASSED + 1))
else
  bad "list manifests returned $code"
  record "GET /api/v1/html-apps" "200" "$code"
fi

code=$(status_of "$BASE_URL/api/v1/html-apps/$APP_ID")
if [[ "$code" == "200" ]]; then
  ok "fetch one manifest 200"
  record "GET /api/v1/html-apps/{appId}" "200" "$code"
  PASSED=$((PASSED + 1))
else
  bad "fetch one manifest returned $code"
  record "GET /api/v1/html-apps/{appId}" "200" "$code"
fi

code=$(status_of "$BASE_URL/api/v1/html-apps/does-not-exist-$APP_ID")
if [[ "$code" == "404" ]]; then
  ok "unknown appId 404"
  record "GET /api/v1/html-apps/{unknown}" "404" "$code"
  PASSED=$((PASSED + 1))
else
  bad "unknown appId returned $code (expected 404)"
  record "GET /api/v1/html-apps/{unknown}" "404" "$code"
fi

# ── 6. auth is enforced ───────────────────────────────────────────────
code=$(status_of -X POST "$BASE_URL/api/v1/html-apps" \
  -H "content-type: application/json" \
  -H "Authorization: Bearer definitely-not-the-key" \
  --data "$MANIFEST")
if [[ "$code" == "401" ]]; then
  ok "a wrong admin key is rejected with 401"
  record "POST with a wrong admin key" "401" "$code"
  PASSED=$((PASSED + 1))
else
  bad "a wrong admin key returned $code (expected 401)"
  record "POST with a wrong admin key" "401" "$code"
fi

# ── 7. push surface is present ────────────────────────────────────────
code=$(status_of -X POST "$BASE_URL/push" \
  -H "content-type: application/json" \
  --data '{"deviceKey":"contract-test-key","title":"Contract","body":"Probe"}')
if [[ "$code" == "200" || "$code" == "400" || "$code" == "404" || "$code" == "503" ]]; then
  # 503 means no APNs credential, 404 means no paired recipient: both prove the
  # route exists and answers rather than falling through to the SPA handler.
  ok "push endpoint answers ($code)"
  record "POST /push" "a routed answer (200/400/404/503)" "$code"
  PASSED=$((PASSED + 1))
else
  bad "push endpoint returned $code"
  record "POST /push" "a routed answer" "$code"
fi

# ── 8. delete ─────────────────────────────────────────────────────────
code=$(status_of -X DELETE "$BASE_URL/api/v1/html-apps/$APP_ID" "${auth_args[@]}")
if [[ "$code" == "204" || "$code" == "404" ]]; then
  ok "delete manifest ($code)"
  record "DELETE /api/v1/html-apps/{appId}" "204" "$code"
  PASSED=$((PASSED + 1))
else
  bad "delete manifest returned $code"
  record "DELETE /api/v1/html-apps/{appId}" "204" "$code"
fi

code=$(status_of "$BASE_URL/api/v1/html-apps/$APP_ID")
if [[ "$code" == "404" ]]; then
  ok "the deleted manifest is gone"
  record "GET after delete" "404" "$code"
  PASSED=$((PASSED + 1))
else
  bad "the deleted manifest still resolves ($code)"
  record "GET after delete" "404" "$code"
fi

# ── report ────────────────────────────────────────────────────────────
if [[ -n "$REPORT_PATH" ]]; then
  mkdir -p "$(dirname "$REPORT_PATH")"
  {
    echo "# Drel backend contract report"
    echo
    echo "- Target: \`$BASE_URL\`"
    echo "- Result: **$([[ $FAILED -eq 0 ]] && echo PASS || echo FAIL)** ($PASSED passed, $FAILED failed)"
    echo
    echo "| Check | Expected | Actual |"
    echo "|---|---|---|"
    printf '%s\n' "${ROWS[@]}"
  } > "$REPORT_PATH"
  ok "wrote $REPORT_PATH"
fi

printf '\n'
if [[ $FAILED -eq 0 ]]; then
  printf '\033[0;32mSummary: %d passed, 0 failed.\033[0m\n' "$PASSED"
  exit 0
fi
printf '\033[0;31mSummary: %d passed, %d failed.\033[0m\n' "$PASSED" "$FAILED"
exit 1
