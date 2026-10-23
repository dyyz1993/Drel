#!/usr/bin/env bash
# Produce a self-hosted Drel build with your own Apple identity.
#
# A self-hosted relay can only deliver to a phone whose app was signed for
# the same Apple topic. That means the operator needs their own build:
#
#   bundle id      com.webbridgekit.superapp  ->  <your-bundle-id>
#   app group      group.com.webbridgekit.superapp -> group.<your-bundle-id>
#   keychain svc   com.webbridgekit.superapp.push-crypto -> <your-bundle-id>.push-crypto
#   APNs topic     the apns-topic header must equal the app's bundle id
#   URL scheme     drel -> <your-scheme>
#   gateway        the compiled-in default points at your own server
#
# The script rewrites those identifiers in a COPY of the tree, so the official
# checkout is never modified. It then prints the exact follow-up steps.
#
# Usage:
#   bash tools/rebrand-drel-selfhosted.sh --bundle-id com.acme.drel \
#        --team-id ABCDE12345 --key-id KEY1234567 \
#        --gateway https://hub.acme.com --out build/selfhosted-app
#
#   --bundle-id   required; the app's bundle id, also the APNs topic
#   --team-id     required; your Apple team id
#   --key-id      required; your APNs key id
#   --scheme      optional; the URL scheme (default: derived from the bundle id)
#   --gateway     optional; the default gateway baked into the build
#   --out         optional; where to write the rebranded tree
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BUNDLE_ID=""
TEAM_ID=""
KEY_ID=""
SCHEME=""
GATEWAY=""
OUT=""
P8_PATH=""

say() { printf '\n\033[0;34m== %s ==\033[0m\n' "$*"; }
ok()  { printf '\033[0;32m[OK]\033[0m %s\n' "$*"; }
bad() { printf '\033[0;31m[FAIL]\033[0m %s\n' "$*"; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle-id) BUNDLE_ID="$2"; shift 2 ;;
    --team-id) TEAM_ID="$2"; shift 2 ;;
    --key-id) KEY_ID="$2"; shift 2 ;;
    --scheme) SCHEME="$2"; shift 2 ;;
    --gateway) GATEWAY="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --p8) P8_PATH="$2"; shift 2 ;;
    *) bad "Unknown argument: $1" ;;
  esac
done

[[ -n "$BUNDLE_ID" ]] || bad "Pass --bundle-id <your.bundle.id>."
[[ "$BUNDLE_ID" =~ ^[A-Za-z0-9.-]+$ ]] || bad "The bundle id may only contain letters, digits, dots and hyphens."
[[ "$BUNDLE_ID" != "com.webbridgekit.superapp" ]] \
  || bad "That is the official bundle id. Use your own so your .p8 can sign for it."
[[ -n "$TEAM_ID" ]] || bad "Pass --team-id <your Apple team id>."
[[ -n "$KEY_ID" ]] || bad "Pass --key-id <your APNs key id>."

APP_GROUP="group.${BUNDLE_ID}"
KEYCHAIN_SERVICE="${BUNDLE_ID}.push-crypto"
[[ -n "$SCHEME" ]] || SCHEME="drel-$(printf '%s' "$BUNDLE_ID" | tr '.' '-' | tr '[:upper:]' '[:lower:]')"
# The official app registers "drel" and "webbridgekit". A self-hosted build
# must use a different scheme or the two apps steal each other's deep links.
[[ -n "$GATEWAY" ]] || GATEWAY="https://${BUNDLE_ID}.example.com"
[[ -n "$OUT" ]] || OUT="$ROOT/build/selfhosted-app"
GATEWAY_ID="gw-$(date -u +%Y%m%d)"
# The XcodeGen team prefix follows the bundle id's leading labels.
TEAM_PREFIX="$(printf '%s' "$BUNDLE_ID" | cut -d. -f1,2)"
case "$BUNDLE_ID" in
  *.*.*) TEAM_PREFIX="$(printf '%s' "$BUNDLE_ID" | cut -d. -f1,2,3)" ;;
esac

say "Copying the tree to $OUT"
rm -rf "$OUT"
mkdir -p "$OUT"
# Copy the sources the build needs, and skip the artifacts.
for item in SuperApp NotificationServiceExtension DrelTests SuperAppUITests Server tools scripts docs project.yml Podfile Podfile.lock Package.resolved; do
  [[ -e "$ROOT/$item" ]] || continue
  cp -R "$ROOT/$item" "$OUT/"
done
ok "Tree copied"

say "Rewriting the identifiers"
python3 - "$OUT" "$BUNDLE_ID" "$APP_GROUP" "$KEYCHAIN_SERVICE" "$SCHEME" "$GATEWAY" "$GATEWAY_ID" "$TEAM_ID" "$KEY_ID" "$TEAM_PREFIX" <<'PY'
import pathlib
import re
import sys

out, bundle, group, keychain, scheme, gateway, gateway_id, team, key_id, team_prefix = sys.argv[1:11]
out = pathlib.Path(out)

# (path suffix, pattern, replacement)
edits = [
    ("project.yml", r"com\.webbridgekit\.superapp", bundle),
    ("project.yml", r"bundleIdPrefix: com\.webbridgekit", f"bundleIdPrefix: {team_prefix}"),
    ("SuperApp/Sources/AppDelegate.swift", r"group\.com\.webbridgekit\.superapp", group),
    ("SuperApp/Sources/AppDelegate.swift", r"com\.webbridgekit\.superapp\.push-crypto", keychain),
    ("SuperApp/Sources/Managers/PendingMessageImporter.swift", r"group\.com\.webbridgekit\.superapp", group),
    ("SuperApp/Sources/Push/PushSoundInstaller.swift", r"group\.com\.webbridgekit\.superapp", group),
    ("SuperApp/Sources/Push/PushNotificationManager.swift", r"group\.com\.webbridgekit\.superapp", group),
    ("SuperApp/Sources/Views/Settings/PushEncryptionView.swift", r"group\.com\.webbridgekit\.superapp", group),
    ("SuperApp/Sources/Views/Settings/PushEncryptionView.swift", r"com\.webbridgekit\.superapp\.push-crypto", keychain),
    ("SuperApp/Sources/Views/Tools/UIAuditTool.swift", r"com\.webbridgekit\.superapp", bundle),
    ("NotificationServiceExtension/IconAvatarProcessor.swift", r"com\.webbridgekit\.superapp", bundle),
    ("SuperApp/Sources/Info.plist", r"<string>drel</string>", f"<string>{scheme}</string>"),
]

changed = 0
for relative, pattern, replacement in edits:
    path = out / relative
    if not path.is_file():
        continue
    text = path.read_text(encoding="utf-8")
    updated, count = re.subn(pattern, replacement, text)
    if count:
        path.write_text(updated, encoding="utf-8")
        changed += count

# The compiled-in default gateway has to point at the operator's own server.
gateway_file = out / "SuperApp/Sources/Configuration/DrelGatewayConfiguration.swift"
if gateway_file.is_file():
    text = gateway_file.read_text(encoding="utf-8")
    text = re.sub(r'baseURL:\s*"[^"]*"', f'baseURL: "{gateway}"', text)
    text = re.sub(r'publicKeyID:\s*"[^"]*"', f'publicKeyID: "{gateway_id}"', text)
    # The public key is filled in by the operator after the gateway is up.
    text = re.sub(r'publicKey:\s*"[^"]*"', 'publicKey: "REPLACE_WITH_YOUR_GATEWAY_PUBLIC_KEY"', text)
    text = re.sub(r'id:\s*"drel-gateway"', f'id: "{gateway_id}"', text)
    text = re.sub(r'name:\s*"[^"]*"', f'name: "{gateway}"', text)
    gateway_file.write_text(text, encoding="utf-8")
    changed += 1

# The relay topic must equal the app bundle id.
env_example = out / "Server/native/drel.env"
print(f"identifiers rewritten ({changed} edits)")
PY
ok "Identifiers rewritten"

say "Pinning the framework path"
# The Podfile resolves the framework relative to the tree, and the
# rebranded copy sits deeper than the original checkout.
FRAMEWORK_ABS="$(cd "$ROOT/.." && pwd)/WebBridgeKit-Framework"
if [[ -d "$FRAMEWORK_ABS" ]]; then
  FRAMEWORK_REL="$(python3 - "$OUT" "$FRAMEWORK_ABS" <<'PY'
import os, sys
out, target = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
print(os.path.relpath(target, out))
PY
)"
  python3 - "$OUT" "$FRAMEWORK_REL" <<'PY'
import pathlib, sys
out, rel = sys.argv[1], sys.argv[2]

podfile = pathlib.Path(out) / "Podfile"
text = podfile.read_text(encoding="utf-8")
text = text.replace(
    "ENV.fetch('WBK_FRAMEWORK_PATH', '../WebBridgeKit-Framework')",
    f"ENV.fetch('WBK_FRAMEWORK_PATH', '{rel}')",
)
podfile.write_text(text, encoding="utf-8")

# project.yml links one framework source file by a relative path, which has
# to move with the tree.
project = pathlib.Path(out) / "project.yml"
text = project.read_text(encoding="utf-8")
text = text.replace("../WebBridgeKit-Framework/", f"{rel}/")
project.write_text(text, encoding="utf-8")
print(f"framework path pinned to {rel}")
PY
  ok "Podfile now resolves the framework from $FRAMEWORK_REL"
else
  warn "The WebBridgeKit-Framework checkout was not found next to the repository."
  warn "Set WBK_FRAMEWORK_PATH before running pod install."
fi

say "Writing the matching relay environment"
cat > "$OUT/Server/native/drel.env" <<EOF
# Drel relay for a self-hosted build.
#
# The APNs topic MUST equal the bundle id of the app on the phone, because
# Apple routes a notification by topic. Fill in the key id and team id from
# the Apple developer portal, and point APNS_KEY_PATH at your .p8.

DREL_SELF_HOSTED_PUBLIC_BASE_URL=$GATEWAY
DREL_SELF_HOSTED_NAME=Drel Self-hosted
DREL_LISTEN_ADDR=127.0.0.1:8080
DREL_DATA_DIR=/var/lib/drel-selfhosted

# The gateway: app identity, offline packages, native actions.
GATEWAY_ID=$GATEWAY_ID
GATEWAY_NAME=Drel Gateway
GATEWAY_PUBLIC_BASE_URL=$GATEWAY
GATEWAY_KEY_ID=$GATEWAY_ID
GATEWAY_PRIVATE_KEY=TODO-paste-the-generated-seed

# Management authentication for POST/DELETE on /api/v1/html-apps.
ADMIN_API_KEY=TODO-generate-a-long-random-value

# APNs delivery, straight to Apple. No relay in between.
APNS_ENVIRONMENT=production
APNS_TOPIC=$BUNDLE_ID
APNS_KEY_ID=$KEY_ID
APNS_TEAM_ID=$TEAM_ID
APNS_KEY_PATH=/etc/drel/secrets/AuthKey_${KEY_ID}.p8
EOF
chmod 600 "$OUT/Server/native/drel.env"
ok "Wrote $OUT/Server/native/drel.env"

cat > "$OUT/BUILD-NOTES.md" <<EOF
# Self-hosted Drel build

| Setting | Value |
|---|---|
| Bundle id (also the APNs topic) | \`$BUNDLE_ID\` |
| App group | \`$APP_GROUP\` |
| Keychain service | \`$KEYCHAIN_SERVICE\` |
| URL scheme | \`$SCHEME\` |
| Default gateway | \`$GATEWAY\` |
| Apple team id | \`$TEAM_ID\` |
| APNs key id | \`$KEY_ID\` |

## What you must do in the Apple developer portal

1. Create an App ID with the bundle id \`$BUNDLE_ID\`.
2. Enable **Push Notifications** and create an APNs key.
3. Create an App Group \`$APP_GROUP\` and enable it for both the app and
   the Notification Service Extension.
4. Add your APNs key id and team id to the signing settings.

## Build steps

\`\`\`bash
cd $OUT
# The rebranded tree has its own project file, so regenerate it.
xcodegen generate
pod install
xcodebuild build -workspace Drel.xcworkspace -scheme Drel -sdk iphonesimulator \\
  -derivedDataPath /tmp/selfhosted-dd
\`\`\`

Then open the project, select your team, and run on your device.

## After the app is on the phone

1. Start the relay (the environment file is at \`Server/native/drel.env\`).
2. Fetch the gateway public key and paste it into
   \`SuperApp/Sources/Configuration/DrelGatewayConfiguration.swift\`:

   \`\`\`bash
   curl $GATEWAY/api/v1/gateway
   \`\`\`

3. Rebuild the app so the default gateway points at your server.
4. In the app: Settings → Self-hosted push → import \`$GATEWAY\`.
EOF
ok "Wrote $OUT/BUILD-NOTES.md"

say "Done"
cat <<EOF

  Rebranded tree: $OUT
  Relay env file: $OUT/Server/native/drel.env
  Build notes:    $OUT/BUILD-NOTES.md

  Next:
    1. Set up the Apple App ID, APNs key and App Group for $BUNDLE_ID.
    2. Fill in the TODOs in $OUT/Server/native/drel.env.
    3. Start the relay, then curl $GATEWAY/api/v1/gateway for the public key.
    4. Paste that key into DrelGatewayConfiguration.swift and rebuild.
EOF
