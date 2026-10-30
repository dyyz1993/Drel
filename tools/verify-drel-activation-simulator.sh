#!/bin/bash
# 模拟器推送激活端到端验证（2026-10-30 用户反馈沉淀：开发完成必须先在
# 模拟器自测完整激活链路，再交给真机验收）。
#
# 链路：安装 Debug 构建 → 前台启动 → simctl push 投递带 appId+route 的
# 推送 → 等待协调器按需拉清单/验签/记录激活 → 断言该 appId 同时出现在
# 受信清单与激活账本（首页卡片的两个必要条件），并截图存证。
#
# 依赖：已构建的模拟器 Debug 产物（默认 /tmp/drel-dd，可用 APP_PATH 覆盖）。
# 用法：bash tools/verify-drel-activation-simulator.sh [appId] [udid]
# 示例：bash tools/verify-drel-activation-simulator.sh dev.vot.workspace

set -euo pipefail

APP_ID="${1:-dev.vot.workspace}"
ROUTE="${2:-/}"
UDID="${3:-$(xcrun simctl list devices | sed -n 's/.*(\([A-F0-9-]\{36\}\)) (Booted).*/\1/p' | head -1)}"
APP_PATH="${APP_PATH:-$(find /tmp/drel-dd/Build/Products/Debug-iphonesimulator -maxdepth 1 -name 'Drel.app' 2>/dev/null | head -1)}"
BUNDLE="com.webbridgekit.superapp"
MANIFESTS_KEY="com.webbridgekit.html-app-runtime.manifests"
ACTIVATION_KEY="com.webbridgekit.html-app-runtime.push-activated-app-ids"
REPORT_DIR="build/reports"
mkdir -p "$REPORT_DIR"

[[ -n "$UDID" ]] || { echo "FAIL: 未找到已启动的模拟器（先 boot 一个）"; exit 1; }
[[ -n "$APP_PATH" && -d "$APP_PATH" ]] || { echo "FAIL: 未找到 Drel.app（先构建或用 APP_PATH 指定）"; exit 1; }

if xcrun simctl listapps "$UDID" 2>/dev/null | grep -q "\"com.webbridgekit.superapp\"" \
   || xcrun simctl listapps "$UDID" 2>/dev/null | grep -q "com.webbridgekit.superapp"; then
  # 重装（同 bundle 覆盖 install）会使 simctl push 的前台投递失效：推送
  # 只进通知中心、不触发 willPresent，激活路径测不到。已安装就复用。
  echo "== 已安装，复用现有安装 =="
else
  echo "== 安装 Debug 构建 =="
  xcrun simctl install "$UDID" "$APP_PATH"
fi
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
sleep 5

echo "== 投递模拟推送（前台到达路径）=="
PAYLOAD="$(mktemp -d)/payload.json"
cat > "$PAYLOAD" <<EOF
{
  "aps": {"alert": {"title": "激活验证", "body": "$APP_ID 端到端"}, "sound": "default", "mutable-content": 1},
  "messageId": "activation-e2e-$(date +%s)",
  "title": "激活验证",
  "body": "$APP_ID 端到端",
  "appId": "$APP_ID",
  "route": "$ROUTE"
}
EOF
xcrun simctl push "$UDID" "$BUNDLE" "$PAYLOAD"

read_prefs_once() {
  # UserDefaults 由 cfprefd 缓存，App 运行中 plist 不落盘：必须先终止再读。
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  sleep 2
  CONTAINER="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)"
  python3 - "$CONTAINER/Library/Preferences/$BUNDLE.plist" "$1" "$APP_ID" <<'PY'
import plistlib, sys
path, key, app_id = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    prefs = plistlib.load(open(path, 'rb'))
except Exception:
    sys.exit(1)
value = prefs.get(key)
# 受信清单是 bytes blob，激活账本是字符串数组：两种形态都要能匹配。
found = (app_id.encode() in value) if isinstance(value, bytes) else (app_id in (value or []))
sys.exit(0 if found else 1)
PY
}

echo "== 等待激活（webManifest 阶段较慢）=="
FAIL=0
for KEY in "$MANIFESTS_KEY" "$ACTIVATION_KEY"; do
  OK=0
  for ATTEMPT in 45 30 30; do
    sleep "$ATTEMPT"
    if read_prefs_once "$KEY"; then OK=1; break; fi
    # 激活只发生在推送到达那一刻；重试前重新前台投递一次。
    xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
    sleep 3
    xcrun simctl push "$UDID" "$BUNDLE" "$PAYLOAD" >/dev/null
  done
  if (( OK )); then echo "PASS: $KEY 含 $APP_ID"; else echo "FAIL: $KEY 不含 $APP_ID"; FAIL=1; fi
done

xcrun simctl io "$UDID" screenshot "$REPORT_DIR/activation-e2e-$(date +%H%M%S).png" >/dev/null 2>&1 || true

if (( FAIL )); then
  echo "Summary: 1 failed, 0 passed."
  exit 1
fi
echo "Summary: 2 passed, 0 failed. （受信清单与激活账本均包含 "$APP_ID"，首页卡片条件满足）"
