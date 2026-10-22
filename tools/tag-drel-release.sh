#!/usr/bin/env bash
# Tag a Drel release and publish its GitHub Release notes.
#
# The tag name carries the build number so the mapping between a marketing
# version and the exact uploaded build is never ambiguous:
#
#     v1.5.0+98
#
# The tag message is the matching CHANGELOG section, so the GitHub Release
# page is a mirror of the repository's own record rather than a second,
# drifting source of truth.
#
# Usage:
#   bash tools/tag-drel-release.sh 1.5.0 98
#   bash tools/tag-drel-release.sh 1.5.0 98 --dry-run
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MARKETING="${1:-}"
BUILD="${2:-}"
DRY_RUN="${3:-}"

if [[ -z "$MARKETING" || -z "$BUILD" ]]; then
  echo "用法: bash tools/tag-drel-release.sh <marketing-version> <build-number> [--dry-run]" >&2
  exit 2
fi

[[ "$MARKETING" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "marketing version 必须是 x.y.z 形式: $MARKETING" >&2
  exit 2
}
[[ "$BUILD" =~ ^[0-9]+$ ]] || {
  echo "build 必须是数字: $BUILD" >&2
  exit 2
}

TAG="v${MARKETING}+${BUILD}"
RELEASE_DIR="docs/release/${MARKETING}"
NOTES="$RELEASE_DIR/RELEASE-NOTES.md"

say() { printf '\n\033[0;34m== %s ==\033[0m\n' "$*"; }
ok()  { printf '\033[0;32m[OK]\033[0m %s\n' "$*"; }
bad() { printf '\033[0;31m[FAIL]\033[0m %s\n' "$*"; exit 1; }

say "校验发布前置条件"
python3 tools/verify-release-identity.py --marketing "$MARKETING" --build "$BUILD" \
  || bad "发布身份校验失败"
[[ -f "$NOTES" ]] || bad "缺少 $NOTES"
ok "身份与发布材料就绪"

if git rev-parse "$TAG" >/dev/null 2>&1; then
  bad "tag $TAG 已存在。请确认是否为重复发布。"
fi

# Extract the matching CHANGELOG section for the tag message.
CHANGELOG_SECTION=$(python3 - "$MARKETING" <<'PY'
import re
import sys

version = sys.argv[1]
text = open("CHANGELOG.md", encoding="utf-8").read()
pattern = re.compile(
    r"^## \[(?P<v>" + re.escape(version) + r")\] — (?P<date>\d{4}-\d{2}-\d{2})\s*$",
    re.M,
)
matches = list(pattern.finditer(text))
if not matches:
    sys.exit(1)
start = matches[0].end()
end = len(text)
for candidate in re.finditer(r"^## \[", text[start:], re.M):
    end = start + candidate.start()
    break
section = text[start:end].strip()
section = re.split(r"^\[", section, maxsplit=1, flags=re.M)[0].strip()
print(section)
PY
) || bad "CHANGELOG.md 中找不到 $MARKETING 的条目"

if [[ -n "$DRY_RUN" ]]; then
  say "dry-run：将创建 tag $TAG"
  printf '%s\n\n%s\n' "$MARKETING ($BUILD) — $(date -u +%Y-%m-%d)" "$CHANGELOG_SECTION"
  exit 0
fi

say "创建 tag $TAG"
git tag -a "$TAG" -m "$MARKETING ($BUILD) — $(date -u +%Y-%m-%d)

$CHANGELOG_SECTION"
ok "tag 已创建（尚未推送）"

if [[ -n "${GITHUB_TOKEN:-}" ]] && command -v gh >/dev/null 2>&1; then
  say "创建 GitHub Release"
  gh release create "$TAG" \
    --title "$MARKETING ($BUILD)" \
    --notes "$CHANGELOG_SECTION" \
    || bad "GitHub Release 创建失败"
  ok "GitHub Release 已创建"
else
  say "跳过 GitHub Release"
  echo "未设置 GITHUB_TOKEN 或未安装 gh。推送 tag 后可手动创建："
  echo "  git push origin $TAG"
  echo "  gh release create $TAG --title \"$MARKETING ($BUILD)\" --notes-file <notes>"
fi

say "完成"
echo "下一步：git push origin $TAG"
