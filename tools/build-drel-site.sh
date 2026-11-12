#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$ROOT/build/drel-site-staging"
SKILL_STAGE="$ROOT/build/drel-skill-staging"

# The legacy builders reset their staging directory. Build the skill separately
# so composing a website release preserves every deployed demo path.
bash "$ROOT/tools/build-drel-data-template-site.sh" "$STAGE"
bash "$ROOT/tools/build-drel-app-development-skill-site.sh" "$SKILL_STAGE"
cp -R "$SKILL_STAGE/skills/." "$STAGE/skills/"
bash "$ROOT/tools/build-drel-action-demo-site.sh" "$STAGE"
# The Drel 1.0 Bridge test fixtures, published under an explicit version
# path so the historical contract stays inspectable.
bash "$ROOT/tools/build-drel-bridge-test-pages-site.sh" "$STAGE"
# Landing pages and the /test/ index. Must run last so it also covers the
# directories the demo builders create.
bash "$ROOT/tools/build-drel-demo-pages.sh" "$STAGE"
# Sound demos share one adapter and remain scoped to their own path.
mkdir -p "$STAGE/sound/voice-jump" "$STAGE/sound/voice-dandelion" "$STAGE/sound/voice-games"
cp "$ROOT/test_resources/voice-jump/index.html" "$STAGE/sound/voice-jump/index.html"
cp "$ROOT/test_resources/voice-dandelion/index.html" "$STAGE/sound/voice-dandelion/index.html"
cp "$ROOT/test_resources/voice-games/audio-level.js" "$STAGE/sound/voice-games/audio-level.js"
# Diagrams are rendered from the Mermaid sources under docs/diagrams/.
if [[ "${DREL_SKIP_DIAGRAMS:-0}" != "1" ]]; then
  bash "$ROOT/tools/build-drel-diagrams.sh"
fi
echo "Complete website: $STAGE"
