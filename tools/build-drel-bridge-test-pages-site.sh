#!/usr/bin/env bash
set -euo pipefail

# Publish the Drel 1.0 Bridge test fixtures.
#
# These six pages shipped inside the Drel 1.0 app (builds 44-65) as the
# manual test surface for the full native Bridge. They were never part of
# the website, so the `ae8fcb.../test_resources/bridge-*.html` URLs the
# development seeder points at have been 404 for months.
#
# The pages are kept exactly as they were — they exercise the v1 action
# set (camera, contacts, sensors, bluetooth, speech, ...), not the seven
# actions the 1.5 store build allows. Publishing them under an explicit
# version path keeps the historical contract inspectable without implying
# that the current store build can run them.
#
# The pages live under `docs/site/test/bridge/v1/`. They used to sit in
# `SuperApp/Resources/`, but nothing in the app ever loaded them from the
# bundle: the app reaches them through their published URL, and the release
# build strips every HTML file from the bundle anyway. Keeping the only copy
# with the website removed a dead duplicate and one more file for the app
# to carry.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/docs/site/test/bridge/v1"
STAGE="${1:-$ROOT/build/drel-site-staging}"

# The Drel version whose App bundle carried these fixtures.
FIXTURE_VERSION="1.0"
# The Bridge contract the fixtures exercise.
BRIDGE_GENERATION="v1"
PUBLIC_ROOT="https://drel.app/test/bridge/$BRIDGE_GENERATION"

case "$STAGE" in
  "$ROOT"/build/*) ;;
  *) echo "Refusing to replace a staging directory outside $ROOT/build" >&2; exit 2 ;;
esac

PAGES=(bridge-permission bridge-device bridge-media bridge-interaction bridge-navigation bridge-cache)

# The site layout follows the other demos: `test/bridge/` is the demo
# directory with a landing page and a web manifest, `test/bridge/v1/` holds
# the generation's pages.
OUT_DIR="$STAGE/test/bridge/$BRIDGE_GENERATION"
mkdir -p "$OUT_DIR"

# Start from an empty directory: the stylesheet is published under a
# hashed name, so a style change would otherwise leave the previous
# hash behind as an orphan.
/usr/bin/python3 -c 'import shutil,sys; shutil.rmtree(sys.argv[1], ignore_errors=True)' "$OUT_DIR"
mkdir -p "$OUT_DIR"

# The fixtures share one stylesheet. It is published under a name that
# carries its content hash, so the page can cache it for a year and a
# style change still reaches the browsers that cached the old one.
CSS_NAME="$(/usr/bin/python3 - "$SOURCE/bridge-fixtures.css" <<'PY'
import hashlib
import pathlib
import sys

data = pathlib.Path(sys.argv[1]).read_bytes()
print(f"bridge-fixtures-{hashlib.sha256(data).hexdigest()[:8]}.css")
PY
)"
cp "$SOURCE/bridge-fixtures.css" "$OUT_DIR/$CSS_NAME"

for page in "${PAGES[@]}"; do
  src="$SOURCE/$page.html"
  [[ -f "$src" ]] || { echo "Missing fixture source: $src" >&2; exit 1; }

  # Inject the version marker into the page title and a visible banner, so
  # the fixture states which Drel generation it belongs to.
  /usr/bin/python3 - "$src" "$OUT_DIR/$page.html" "$FIXTURE_VERSION" "$BRIDGE_GENERATION" "$CSS_NAME" <<'PY'
import re
import sys

src, dest, version, generation, css_name = sys.argv[1:6]
html = open(src, encoding="utf-8").read()

# Point the page at the hashed stylesheet.
html = html.replace('href="bridge-fixtures.css"', f'href="{css_name}"')

# These fixtures never carried a <title>. Build one from the page's own
# heading so every fixture gets a distinct, versioned browser title.
heading = re.search(r"<h1[^>]*>(.*?)</h1>", html, re.S)
heading_text = re.sub(r"<[^>]+>", "", heading.group(1)).strip() if heading else "Bridge fixtures"
page_title = f"{heading_text} · Drel {version} ({generation})"

if "<title>" in html:
    html = re.sub(r"<title>.*?</title>", f"<title>{page_title}</title>", html, count=1, flags=re.S)
else:
    html = html.replace(
        "<head>",
        f"<head>\n<title>{page_title}</title>",
        1,
    )

# A short notice above the existing heading. The fixtures stay otherwise
# untouched: they are a record of the v1 contract, not a live demo of the
# current store build. The styling comes from the shared stylesheet.
banner = (
    '<div class="fixture-note">'
    f"Drel {version} ({generation}) Bridge 测试夹具 · "
    "本页保留的是 1.0 时代的完整 Bridge 动作集，"
    "其中大部分动作不在当前商店版（1.5）的七个动作白名单内。"
    "</div>"
)
match = re.search(r"(<h1[^>]*>.*?</h1>)", html, re.S)
if match:
    html = html[: match.end()] + "\n" + banner + html[match.end():]
else:
    html = html.replace("<body>", f"<body>\n{banner}", 1)

open(dest, "w", encoding="utf-8").write(html)
PY
done

# The generation index: the six fixture pages of this Bridge generation.
cat > "$OUT_DIR/index.html" <<EOF
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Drel ${FIXTURE_VERSION} Bridge 测试夹具</title>
  <link rel="icon" href="/assets/drel-mark.svg" type="image/svg+xml">
  <link rel="stylesheet" href="/assets/site.css">
  <link rel="canonical" href="${PUBLIC_ROOT}/">
</head>
<body>
  <header class="shell nav">
    <a class="brand" href="/" aria-label="Drel home"><img src="/assets/drel-mark.svg" alt="">Drel</a>
    <nav class="nav-links" aria-label="Primary navigation">
      <a href="/">Home</a><a href="/docs/">Docs</a><a href="/test/">Try it</a><a class="nav-cta" href="/support/">Support</a>
    </nav>
  </header>
  <main class="shell section">
    <div class="section-head">
      <div><span class="eyebrow">Drel ${FIXTURE_VERSION} · Bridge ${BRIDGE_GENERATION}</span><h1>Bridge test<br>fixtures.</h1></div>
      <p class="section-copy">这些页面随 Drel ${FIXTURE_VERSION} 一起发布，测试当时的完整原生 Bridge 动作集。它们保留原样，作为那一代合同的记录；其中大部分动作不在当前商店版的白名单内。</p>
    </div>
    <div class="feature-grid demo-grid">
      <article class="feature"><div class="feature-icon">01</div><h3>权限管理</h3><p>查询与申请系统权限。</p><a class="button secondary" href="/test/bridge/${BRIDGE_GENERATION}/bridge-permission.html">Open →</a></article>
      <article class="feature"><div class="feature-icon">02</div><h3>设备功能</h3><p>屏幕信息、传感器、蓝牙、投屏。</p><a class="button secondary" href="/test/bridge/${BRIDGE_GENERATION}/bridge-device.html">Open →</a></article>
      <article class="feature"><div class="feature-icon">03</div><h3>媒体能力</h3><p>相机、相册、语音、文件、麦克风。</p><a class="button secondary" href="/test/bridge/${BRIDGE_GENERATION}/bridge-media.html">Open →</a></article>
      <article class="feature"><div class="feature-icon">04</div><h3>交互操作</h3><p>扫码、剪贴板、联系人、手势。</p><a class="button secondary" href="/test/bridge/${BRIDGE_GENERATION}/bridge-interaction.html">Open →</a></article>
      <article class="feature"><div class="feature-icon">05</div><h3>导航与状态</h3><p>历史记录、负载、模态与页面。</p><a class="button secondary" href="/test/bridge/${BRIDGE_GENERATION}/bridge-navigation.html">Open →</a></article>
      <article class="feature"><div class="feature-icon">06</div><h3>缓存调试</h3><p>缓存统计、规则与清除。</p><a class="button secondary" href="/test/bridge/${BRIDGE_GENERATION}/bridge-cache.html">Open →</a></article>
    </div>
  </main>
  <footer class="shell footer"><div class="footer-inner"><span>© 2026 Drel · Built with WebBridgeKit.</span><div class="footer-links"><a href="/test/">Live demos</a><a href="/docs/">Docs</a></div></div></footer>
</body>
</html>
EOF

# The demo landing page for /test/bridge/.
cat > "$STAGE/test/bridge/index.html" <<EOF
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Drel Bridge 测试夹具</title>
  <link rel="icon" href="/assets/drel-mark.svg" type="image/svg+xml">
  <link rel="stylesheet" href="/assets/site.css">
  <link rel="canonical" href="https://drel.app/test/bridge/">
</head>
<body>
  <header class="shell nav">
    <a class="brand" href="/" aria-label="Drel home"><img src="/assets/drel-mark.svg" alt="">Drel</a>
    <nav class="nav-links" aria-label="Primary navigation">
      <a href="/">Home</a><a href="/docs/">Docs</a><a href="/test/">Try it</a><a class="nav-cta" href="/support/">Support</a>
    </nav>
  </header>
  <main class="shell section">
    <div class="section-head">
      <div><span class="eyebrow">Historical fixtures</span><h1>Bridge test<br>fixtures.</h1></div>
      <p class="section-copy">这些页面随 Drel 1.0 一起发布，测试当时的完整原生 Bridge 动作集。它们按版本保留在原处，作为那一代合同的记录。</p>
    </div>
    <div class="actions">
      <a class="button primary" href="/test/bridge/${BRIDGE_GENERATION}/">打开 Drel ${FIXTURE_VERSION} 夹具</a>
      <a class="button secondary" href="/test/">返回全部示例</a>
    </div>
  </main>
  <footer class="shell footer"><div class="footer-inner"><span>© 2026 Drel · Built with WebBridgeKit.</span><div class="footer-links"><a href="/test/">Live demos</a><a href="/docs/">Docs</a></div></div></footer>
</body>
</html>
EOF

cat > "$STAGE/test/bridge/manifest.webmanifest" <<EOF
{
  "id": "https://drel.app/test/bridge/",
  "name": "Drel Bridge fixtures",
  "short_name": "Bridge fixtures",
  "start_url": "https://drel.app/test/bridge/${BRIDGE_GENERATION}/",
  "scope": "https://drel.app/test/bridge/",
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

echo "stage=$STAGE"
echo "entry=$PUBLIC_ROOT/index.html"
