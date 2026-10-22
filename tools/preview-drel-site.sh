#!/usr/bin/env bash
# Start the Drel website preview for local acceptance.
#
#   bash tools/preview-drel-site.sh            # build + serve on :8788
#   bash tools/preview-drel-site.sh --no-build # serve the existing staging
#   bash tools/preview-drel-site.sh --port 9000
#   bash tools/preview-drel-site.sh --stop
#
# The preview server reproduces the Cloudflare Pages `_headers` rules, so
# `manifest.webmanifest` gets the right MIME type and versioned assets get
# the immutable cache policy. A plain `python3 -m http.server` does not, and
# the strong-offline fixtures will not install against it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PORT=8788
BUILD=1
STAGE="$ROOT/build/drel-site-staging"
PID_FILE="$ROOT/build/drel-site-preview.pid"

say() { printf '\033[0;34m== %s ==\033[0m\n' "$*"; }
ok()  { printf '\033[0;32m[OK]\033[0m %s\n' "$*"; }
bad() { printf '\033[0;31m[FAIL]\033[0m %s\n' "$*"; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PORT="$2"; shift 2 ;;
    --no-build) BUILD=0; shift ;;
    --stop)
      if [[ -f "$PID_FILE" ]]; then
        kill "$(cat "$PID_FILE")" 2>/dev/null || true
        rm -f "$PID_FILE"
        ok "预览服务已停止"
      else
        pkill -f "serve-drel-site.py" 2>/dev/null || true
        ok "预览服务已停止"
      fi
      exit 0 ;;
    *) bad "未知参数: $1" ;;
  esac
done

# Stop a previous run so the port is free.
pkill -f "serve-drel-site.py" 2>/dev/null || true
sleep 0.5

if [[ "$BUILD" == "1" ]]; then
  say "构建站点"
  bash tools/build-drel-site.sh >"$ROOT/build/drel-site-build.log" 2>&1 \
    || bad "构建失败，详见 build/drel-site-build.log"
  ok "构建完成：$STAGE"
fi

[[ -f "$STAGE/index.html" ]] || bad "站点产物不存在：$STAGE（先去掉 --no-build 跑一次）"

say "校验站点"
python3 tools/verify-drel-site.py --dir "$STAGE" >/dev/null || bad "站点校验未通过"

say "启动预览服务"
mkdir -p "$(dirname "$PID_FILE")"
nohup python3 tools/serve-drel-site.py --port "$PORT" --dir "$STAGE" \
  >"$ROOT/build/drel-site-preview.log" 2>&1 &
echo $! > "$PID_FILE"

for _ in $(seq 1 20); do
  sleep 0.3
  if curl -fsS -m 2 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
    break
  fi
done

curl -fsS -m 3 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 \
  || bad "服务未能启动，详见 build/drel-site-preview.log"

ok "预览地址：http://127.0.0.1:$PORT"
echo ""
echo "主要入口："
echo "  首页          http://127.0.0.1:$PORT/"
echo "  文档总览      http://127.0.0.1:$PORT/docs/"
echo "  应用开发      http://127.0.0.1:$PORT/docs/app/"
echo "  Bridge API    http://127.0.0.1:$PORT/docs/bridge/"
echo "  体验站点      http://127.0.0.1:$PORT/test/"
echo "  原生操作演示  http://127.0.0.1:$PORT/test/actions/"
echo "  数据模板演示  http://127.0.0.1:$PORT/test/template/"
echo "  强离线包      http://127.0.0.1:$PORT/test/offline/"
echo "  离线+网络     http://127.0.0.1:$PORT/test/offline-network/"
echo "  技能页        http://127.0.0.1:$PORT/skills/drel-app-development/"
echo ""
echo "停止：bash tools/preview-drel-site.sh --stop"
