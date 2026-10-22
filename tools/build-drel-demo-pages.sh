#!/usr/bin/env bash
# Publish the Drel demo landing pages and the /test/ index.
#
# The demo applications themselves are built by their own scripts. This one
# owns the pages that make them reachable: without a landing page a demo
# directory resolves its resources but returns 404 for the directory URL,
# which is exactly how the action and template demos stayed invisible.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="${1:-$ROOT/build/drel-site-staging}"

case "$STAGE" in
  "$ROOT"/build/*) ;;
  *) echo "Refusing to replace a staging directory outside $ROOT/build" >&2; exit 2 ;;
esac

# The /test/ index page.
if [[ -f "$ROOT/docs/site/test/index.html" ]]; then
  mkdir -p "$STAGE/test"
  cp "$ROOT/docs/site/test/index.html" "$STAGE/test/index.html"
fi

# Each demo landing page.
for demo in actions template; do
  source_page="$ROOT/docs/site/test/$demo/index.html"
  if [[ -f "$source_page" ]]; then
    mkdir -p "$STAGE/test/$demo"
    cp "$source_page" "$STAGE/test/$demo/index.html"
  fi
done

echo "stage=$STAGE"
