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
# Landing pages and the /test/ index. Must run last so it also covers the
# directories the demo builders create.
bash "$ROOT/tools/build-drel-demo-pages.sh" "$STAGE"
echo "Complete website: $STAGE"
