#!/usr/bin/env bash
# Public search-index audit using the user's existing Chrome extension channel.
# Never bypasses CAPTCHA: if a CAPTCHA appears, records it as needs_human=true
# and leaves the existing Chrome tab untouched for manual intervention.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_DIR="$ROOT/build/reports/search-index"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="$REPORT_DIR/drel-search-index-$STAMP.json"
LATEST="$REPORT_DIR/latest.json"
TASK="drel-index-check"
TAB_URL_PREFIX="https://www.google.com/search?q=site%3Adrel.app"

mkdir -p "$REPORT_DIR"

status="$(xbrowser chrome-bridge status 2>/dev/null || true)"
if ! grep -q 'running.*true' <<<"$status"; then
  printf '{"schema":"drel.search_index.v1","error":"chrome_bridge_unavailable","checked_at_utc":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$OUT"
  cp "$OUT" "$LATEST.tmp"; mv "$LATEST.tmp" "$LATEST"
  cat "$OUT"
  exit 0
fi

# Reuse the managed check tab if it exists, otherwise create it.
LIST="$(xbrowser chrome-bridge task list 2>/dev/null || true)"
export LIST
TAB_ID="$(python3 -c 'import re,os,sys; text=os.environ.get("LIST",""); m=re.search(r"name:\s*drel-index-check.*?id:\s*(\d+)",text,re.S); print(m.group(1) if m else "")')"
if [[ -z "$TAB_ID" ]]; then
  OPEN="$(xbrowser chrome-bridge task open --action open --name "$TASK" --url "$TAB_URL_PREFIX" 2>/dev/null || true)"
  TAB_ID="$(awk '/tabId/{gsub(/^.*tabId.*: */,""); print; exit}' <<<"$OPEN" | tr -d '[:space:]')"
  sleep 5
fi

probe() {
  local engine="$1" url="$2"
  xbrowser chrome-bridge exec --cmd navigate --args "{\"tabId\":$TAB_ID,\"url\":\"$url\"}" --tab-id "$TAB_ID" --timeout 20000 >/dev/null 2>&1 || true
  sleep "${3:-5}"
  xbrowser chrome-bridge exec --cmd evaluate --args '{"tabId":'"$TAB_ID"',"expression":"JSON.stringify({url:location.href,title:document.title,text:(document.body&&document.body.innerText||\"\"),captcha:!!document.querySelector(\".passMod_dialog-body,[class*=captcha],iframe[src*=captcha],iframe[src*=wappass]\")})"}' --tab-id "$TAB_ID" --timeout 20000 2>/dev/null || true
}

GOOGLE_RAW="$(probe google 'https://www.google.com/search?q=site%3Adrel.app&hl=en' 6)"
BAIDU_RAW="$(probe baidu 'https://www.baidu.com/s?wd=site%3Adrel.app' 6)"

printf '%s\n' "$GOOGLE_RAW" > "$REPORT_DIR/google-$STAMP.raw.txt"
printf '%s\n' "$BAIDU_RAW" > "$REPORT_DIR/baidu-$STAMP.raw.txt"

python3 - "$REPORT_DIR/google-$STAMP.raw.txt" "$REPORT_DIR/baidu-$STAMP.raw.txt" <<'PYX'
import json, pathlib, re, sys
def extract(path):
    s=pathlib.Path(path).read_text(encoding='utf-8', errors='ignore')
    if 'value' not in s:
        return {}
    import re
    m=re.search(r'value[^{]*(\{.*)',s)
    raw=m.group(1).rsplit('persistent',1)[0].strip().rstrip(',') if m else ''
    try:
        return json.loads(raw)
    except Exception:
        return {}
pathlib.Path(sys.argv[1]).with_name('google-parsed.tmp.json').write_text(json.dumps(extract(sys.argv[1]),ensure_ascii=False))
pathlib.Path(sys.argv[2]).with_name('baidu-parsed.tmp.json').write_text(json.dumps(extract(sys.argv[2]),ensure_ascii=False))
PYX
GOOGLE_JSON="$(cat "$REPORT_DIR/google-parsed.tmp.json")"
BAIDU_JSON="$(cat "$REPORT_DIR/baidu-parsed.tmp.json")"

python3 "$ROOT/tools/render-search-index-report.py" "$OUT" "$STAMP" "$REPORT_DIR/google-parsed.tmp.json" "$REPORT_DIR/baidu-parsed.tmp.json"
cat "$OUT"
