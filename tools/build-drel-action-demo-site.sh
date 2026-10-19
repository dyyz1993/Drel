#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/test_resources/action-demo/v1"
STAGE="${1:-$ROOT/build/drel-site-staging}"
PUBLIC_ROOT="https://drel.app/test/actions"

case "$STAGE" in
  "$ROOT"/build/*) ;;
  *) echo "Refusing to replace a staging directory outside $ROOT/build" >&2; exit 2 ;;
esac

if [[ ! -d "$STAGE/test/offline" ]]; then
  bash "$ROOT/tools/build-drel-offline-network-demo-site.sh" "$STAGE"
fi
mkdir -p "$STAGE/test/actions/v1"
cp "$SOURCE/index.html" "$STAGE/test/actions/v1/index.html"

cat > "$STAGE/test/actions/manifest.webmanifest" <<'EOF'
{
  "id": "https://drel.app/test/actions/",
  "name": "Drel Action Demo",
  "short_name": "Action Demo",
  "start_url": "https://drel.app/test/actions/v1/index.html",
  "scope": "https://drel.app/test/actions/",
  "display": "standalone",
  "theme_color": "#4d50d8",
  "background_color": "#f5f7fb",
  "icons": [{
    "src": "https://drel.app/test/offline/assets/app-icon.png",
    "sizes": "512x512",
    "type": "image/png",
    "purpose": "any"
  }]
}
EOF

WEB_MANIFEST_SHA256=$(shasum -a 256 "$STAGE/test/actions/manifest.webmanifest" | awk '{print $1}')
cat > "$STAGE/test/actions/gateway-manifest.json" <<EOF
{
  "schemaVersion": "1",
  "appId": "dev.drel.action-demo",
  "name": "Drel Action Demo",
  "startURL": "https://drel.app/test/actions/v1/index.html",
  "allowedOrigins": ["https://drel.app"],
  "capabilities": [],
  "capabilities_v2": [
    {"action": "haptic", "origins": ["https://drel.app"], "purposeId": "action-demo-haptic", "purpose": "Demonstrate brief haptic feedback", "scope": "appSession"},
    {"action": "vibrate", "origins": ["https://drel.app"], "purposeId": "action-demo-vibrate", "purpose": "Demonstrate brief vibration", "scope": "appSession"},
    {"action": "share", "origins": ["https://drel.app"], "purposeId": "action-demo-share", "purpose": "Share the Drel action demo", "scope": "appSession"},
    {"action": "fullscreen", "origins": ["https://drel.app"], "purposeId": "action-demo-fullscreen", "purpose": "Present the demo immersively", "scope": "appSession"},
    {"action": "clipboard", "origins": ["https://drel.app"], "purposeId": "action-demo-clipboard", "purpose": "Read or write clipboard content for this demo", "scope": "always"},
    {"action": "location", "origins": ["https://drel.app"], "purposeId": "action-demo-location", "purpose": "Get the current position for this demo", "scope": "always"},
    {"action": "addToHomeScreen", "origins": ["https://drel.app"], "purposeId": "action-demo-home", "purpose": "Add this demo to the Drel home screen", "scope": "appSession"}
  ],
  "routes": ["/test/actions/v1/index.html"],
  "webManifest": {"url": "https://drel.app/test/actions/manifest.webmanifest", "sha256": "$WEB_MANIFEST_SHA256"},
  "cache": {"strategy": "networkOnly", "version": "2", "persistent": false, "restoresLastState": true}
}
EOF

echo "stage=$STAGE"
echo "entry=$PUBLIC_ROOT/v1/index.html"
