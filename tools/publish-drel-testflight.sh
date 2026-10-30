#!/usr/bin/env bash
# Drel 1.5 TestFlight 发布脚本（2026-10-22 沉淀，build 101/102 同链路验证）
#
# 归档 → 二进制/契约校验 → 导出 IPA → altool 上传 → 轮询 Apple 处理至 VALID。
# Set WBK_MARKETING_VERSION for non-1.5 releases; the default preserves the
# historical 1.5 flow.
# 与 AGENTS.md 的规则对齐：
#   * 归档用 Drel15Store scheme，MARKETING_VERSION=1.5.0，CURRENT_PROJECT_VERSION=<build>
#   * 本地「WebBridgeKit App Store」描述文件曾缺 Communication Notifications，
#     因此归档走自动开发签名（同 build 99/100/101/102 验证过的链路），
#     导出时再换 App Store 分发签名。
#   * 上传前后各跑一次 tools/verify-drel-v2-store-archive.sh。
#
# 用法：
#   bash tools/publish-drel-testflight.sh 103            # 指定 build 号
#   bash tools/publish-drel-testflight.sh                # 默认递增（读取 ASC 最新 build+1）
#   WBK_SKIP_UPLOAD=1 bash tools/publish-drel-testflight.sh 103   # 只归档+导出+校验
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p "$ROOT/build"

APP_ID="${WBK_APP_ID:-6802806992}"
# ASC 凭据一律来自环境/CI Secrets（开源仓库不保留标识符兜底）。
KEY_ID="${WBK_ASC_KEY_ID:?需要设置 WBK_ASC_KEY_ID（App Store Connect API Key ID）}"
KEY_ISSUER="${WBK_ASC_ISSUER_ID:?需要设置 WBK_ASC_ISSUER_ID（App Store Connect Issuer ID）}"
KEY_PATH="${WBK_ASC_KEY_PATH:?需要设置 WBK_ASC_KEY_PATH（AuthKey_<ID>.p8 私钥路径）}"
MARKETING_VERSION="${WBK_MARKETING_VERSION:-1.5.0}"
# Prefer the repository's self-contained helper so the script also runs in CI,
# where the author's ~/Project/study-mac-app checkout does not exist.
# asc-api.sh takes ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH from the env.
if [[ -x "$ROOT/tools/asc-api.sh" ]]; then
  export ASC_KEY_ID="$KEY_ID" ASC_ISSUER_ID="$KEY_ISSUER" ASC_APP_ID="$APP_ID" ASC_KEY_PATH="$KEY_PATH"
  ASC_API="$ROOT/tools/asc-api.sh"
else
  ASC_API="/usr/bin/python3 $HOME/Project/study-mac-app/quite-note/tools/asc-api.py"
fi
EXPORT_OPTS="${WBK_EXPORT_OPTS:-/tmp/drel-export-options.plist}"
DD="${WBK_RELEASE_DD:-/tmp/wbk-dd-publish}"
SKIP_UPLOAD="${WBK_SKIP_UPLOAD:-0}"
ARCHIVE_SIGNING="${WBK_ARCHIVE_SIGNING:-development}"
SIGNING_KEYCHAIN="${WBK_SIGNING_KEYCHAIN:-}"
SIGNING_KEYCHAIN_PASSWORD_SERVICE="${WBK_SIGNING_KEYCHAIN_PASSWORD_SERVICE:-drel-release-keychain}"
SIGNING_KEYCHAIN_PASSWORD_ACCOUNT="${WBK_SIGNING_KEYCHAIN_PASSWORD_ACCOUNT:-codex-drel-release}"
ORIGINAL_KEYCHAINS=()

# shellcheck disable=SC2329  # invoked indirectly by the EXIT trap
restore_keychains() {
  if (( ${#ORIGINAL_KEYCHAINS[@]} > 0 )); then
    security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}" >/dev/null
  fi
}
trap restore_keychains EXIT

say() { printf '\n\033[0;34m== %s ==\033[0m\n' "$*"; }
ok()  { printf '\033[0;32m[OK]\033[0m %s\n' "$*"; }
bad() { printf '\033[0;31m[FAIL]\033[0m %s\n' "$*"; exit 1; }

# ── build 号 ─────────────────────────────────────────────────────────────────
BUILD="$1"
if [[ -z "$BUILD" ]]; then
  BUILD=$($ASC_API get "/v1/builds?filter[app]=$APP_ID&limit=1&sort=-uploadedDate" 2>/dev/null \
    | grep -oE '"version": *"[0-9]+"' | grep -oE '[0-9]+' | head -1)
  [[ -n "$BUILD" ]] || bad "无法读取当前最新 build 号，请显式传入"
  BUILD=$((BUILD + 1))
  echo "未指定 build 号，自动取最新+1 = $BUILD"
fi
[[ "$BUILD" =~ ^[0-9]+$ ]] || bad "build 号必须是数字: $BUILD"

STAMP=$(date +%m-%d-%H%M)
ARCHIVE="/tmp/drel-1-5-0-build-${BUILD}-${STAMP}.xcarchive"
EXPORT_DIR="/tmp/drel-${BUILD}-export-${STAMP}"
mkdir -p "$(dirname "$ARCHIVE")"

cat > "$EXPORT_OPTS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>destination</key><string>export</string>
<key>signingStyle</key><string>automatic</string>
<key>manageAppVersionAndBuildNumber</key><false/>
<key>teamID</key><string>B45VZCNYU3</string>
<key>uploadSymbols</key><true/>
</dict></plist>
PLIST

say "发布前规范门禁（版本身份 / 发布材料 / 仓库卫生）"
python3 tools/verify-release-identity.py --marketing "$MARKETING_VERSION" --build "$BUILD" \
  || bad "发布身份校验失败：请先修好版本号、发布材料或提交状态"
python3 tools/verify-release-notes.py || bad "CHANGELOG 与发布材料不一致"
python3 tools/verify-repo-hygiene.py || bad "仓库卫生校验失败"
ok "规范门禁通过"

say "归档 Drel $MARKETING_VERSION ($BUILD)"
ARCHIVE_SIGN_ARGS=()
if [[ "$ARCHIVE_SIGNING" == "project" ]]; then
  # Distribution-profile builds use the per-target identities and profiles in
  # project.yml. This path is required when the development identity has no
  # local private key but a versioned App Store profile is available.
  :
elif [[ "$ARCHIVE_SIGNING" == "development" ]]; then
  ARCHIVE_SIGN_ARGS+=(
    'CODE_SIGN_STYLE=Automatic'
    'CODE_SIGN_IDENTITY=Apple Development'
    'PROVISIONING_PROFILE_SPECIFIER='
  )
else
  bad "WBK_ARCHIVE_SIGNING must be 'development' or 'project'"
fi
if [[ -n "$SIGNING_KEYCHAIN" ]]; then
  [[ -f "$SIGNING_KEYCHAIN" ]] || bad "signing keychain not found: $SIGNING_KEYCHAIN"
  if [[ -n "${WBK_SIGNING_KEYCHAIN_PASSWORD:-}" ]]; then
    KEYCHAIN_PASSWORD="$WBK_SIGNING_KEYCHAIN_PASSWORD"
  else
    KEYCHAIN_PASSWORD=$(security find-generic-password \
      -a "$SIGNING_KEYCHAIN_PASSWORD_ACCOUNT" \
      -s "$SIGNING_KEYCHAIN_PASSWORD_SERVICE" -w 2>/dev/null) \
      || bad "signing keychain password is not available from Keychain"
  fi
  security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$SIGNING_KEYCHAIN" >/dev/null \
    || bad "could not unlock the signing keychain"
  unset KEYCHAIN_PASSWORD
  while IFS= read -r keychain; do
    ORIGINAL_KEYCHAINS+=("$keychain")
  done < <(security list-keychains -d user | sed -E 's/^[[:space:]]*"//; s/"$//')
  security list-keychains -d user -s "$SIGNING_KEYCHAIN" "${ORIGINAL_KEYCHAINS[@]}" >/dev/null
  ARCHIVE_SIGN_ARGS+=("OTHER_CODE_SIGN_FLAGS=--keychain $SIGNING_KEYCHAIN")
fi
if ! xcodebuild archive -workspace Drel.xcworkspace -scheme Drel15Store \
  -archivePath "$ARCHIVE" -derivedDataPath "$DD" -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates "${ARCHIVE_SIGN_ARGS[@]}" \
  MARKETING_VERSION="$MARKETING_VERSION" CURRENT_PROJECT_VERSION="$BUILD" >"$ROOT/build/archive-$BUILD.log" 2>&1; then
  echo "---- archive-$BUILD.log (tail) ----" >&2
  tail -n 160 "$ROOT/build/archive-$BUILD.log" >&2 || true
  echo "---- end archive-$BUILD.log ----" >&2
  bad "归档失败，详见 build/archive-$BUILD.log"
fi
ok "归档完成：$ARCHIVE"

say "归档校验（签名契约）"
ARCHIVE_SIGNING_MODE=development
if [[ "$ARCHIVE_SIGNING" == "project" ]]; then
  ARCHIVE_SIGNING_MODE=distribution
fi
DREL_V2_EXPECTED_BUILD="$BUILD" DREL_V2_ARCHIVE_SIGNING="$ARCHIVE_SIGNING_MODE" \
  bash tools/verify-drel-v2-store-archive.sh "$ARCHIVE" >/dev/null 2>&1 \
  || bad "归档契约校验失败"
ok "版本号/签名/隐私文案/定位文案/推送权限 全部符合"

say "导出 App Store Connect IPA"
rm -rf "$EXPORT_DIR"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$EXPORT_OPTS" \
  -exportPath "$EXPORT_DIR" -allowProvisioningUpdates >"$ROOT/build/export-$BUILD.log" 2>&1 \
  || bad "导出失败，详见 build/export-$BUILD.log"
IPA="$EXPORT_DIR/Drel.ipa"
[[ -f "$IPA" ]] || bad "IPA 不存在：$IPA"
ok "IPA 就绪：$IPA"

say "分发契约校验"
rm -rf "$EXPORT_DIR/Payload-check" && mkdir -p "$EXPORT_DIR/Payload-check"
unzip -q "$IPA" -d "$EXPORT_DIR/Payload-check"
DREL_V2_EXPECTED_BUILD="$BUILD" DREL_V2_ARCHIVE_SIGNING=distribution \
  DREL_V2_EXPORTED_APP_PATH="$EXPORT_DIR/Payload-check/Payload/Drel.app" \
  bash tools/verify-drel-v2-store-archive.sh "$ARCHIVE" >/dev/null 2>&1 \
  || bad "分发契约校验失败（生产 APNs / Distribution 签名 / 隐私文案）"
ok "分发签名与生产推送权限符合"

if [[ "$SKIP_UPLOAD" == "1" ]]; then
  ok "WBK_SKIP_UPLOAD=1：跳过上传"
  echo "IPA: $IPA"
  exit 0
fi

say "上传 TestFlight（altool）"
# set -u 下这里曾报 "UPLOAD_JSON: unbound variable"（103/104 两次实测），
# 即便上传本身已成功。用字面量路径 + ${VAR:-default} 兜底，杜绝未绑定变量。
UPLOAD_TMP="/tmp/drel-upload-$BUILD-$$.json"
set +eu
xcrun altool --upload-app --type ios --file "$IPA" \
  --apiKey "${KEY_ID:-}" --apiIssuer "${KEY_ISSUER:-}" \
  --output-format json >"$UPLOAD_TMP" 2>&1
UPLOAD_RC=$?
set -eu
if [[ $UPLOAD_RC -eq 0 ]] && grep -q "UPLOAD SUCCEEDED" "$UPLOAD_TMP"; then
  cp "$UPLOAD_TMP" "$ROOT/build/upload-$BUILD.json"
  ok "上传成功（详见 build/upload-$BUILD.json）"
elif grep -q "already been used" "$UPLOAD_TMP" || grep -q "must be higher than the previously uploaded" "$UPLOAD_TMP"; then
  # 同一 build 号已上传过（脚本中断后重跑等场景）：Apple 侧已有该版本，
  # 直接进入轮询，不要当成失败。
  cp "$UPLOAD_TMP" "$ROOT/build/upload-$BUILD.json"
  ok "该 build 号已上传过，继续轮询处理状态"
else
  cat "$UPLOAD_TMP"
  bad "上传失败"
fi

say "轮询 Apple 处理状态"
for i in $(seq 1 30); do
  sleep 20
  # 注意：先取引号内完整值再清理，直接 grep -oE '[A-Z_]+' 会只拿到首字母
  STATE=$($ASC_API get "/v1/builds?filter[app]=$APP_ID&filter[version]=$BUILD&fields[builds]=version,processingState" 2>/dev/null \
    | { grep -oE '"processingState" *: *"[^"]+"' || true; } | head -1 | sed -E 's/.*: *"([^"]+)".*/\1/')
  echo "  [$((i*20))s] processingState=$STATE"
  if [[ "$STATE" == "VALID" ]]; then
    BUILD_ID=$($ASC_API get "/v1/builds?filter[app]=$APP_ID&filter[version]=$BUILD" 2>/dev/null \
      | { grep -oE '"id" *: *"[a-f0-9-]{36}"' || true; } | head -1 | grep -oE '[a-f0-9-]{36}')
    $ASC_API get "/v1/builds/$BUILD_ID/buildBetaDetail" 2>/dev/null | grep -E "internalBuildState"
    ok "Drel 1.5.0 ($BUILD) 处理完成，TestFlight 可安装"
    echo
    echo "接下来：在 TestFlight 上做真机验收（三档面板 / 允许一次重复弹窗 / 权限中心 / 主屏幕引导）"
    exit 0
  fi
  if [[ "$STATE" == "FAILED" || "$STATE" == "INVALID" ]]; then
    bad "Apple 处理失败：$STATE"
  fi
done
bad "轮询超时（10 分钟未完成）；Apple 仍在后台处理，可稍后用 ASC API 复查"
