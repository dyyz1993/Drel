#!/usr/bin/env bash
# Render the Mermaid diagram sources into the website's SVG assets.
#
# The `.mmd` files under docs/diagrams/ are the source of truth. They are
# plain text, so a diagram change shows up in a diff as a readable edit
# instead of a binary blob.
#
# Rendering uses the mermaid CLI through npx. The tool is not vendored: it is
# resolved on demand, so the repository stays free of a large dependency
# tree. When it is unavailable the script fails loudly rather than silently
# publishing a stale diagram.
#
# Usage:
#   bash tools/build-drel-diagrams.sh
#   bash tools/build-drel-diagrams.sh --check   # fail if any output is stale
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SOURCE_DIR="$ROOT/docs/diagrams"
OUTPUT_DIR="$ROOT/docs/site/assets/diagrams"
CONFIG="$ROOT/docs/diagrams/mermaid-config.json"
CHECK_ONLY=0

[[ "${1:-}" == "--check" ]] && CHECK_ONLY=1

say() { printf '\033[0;34m== %s ==\033[0m\n' "$*"; }
ok()  { printf '\033[0;32m[OK]\033[0m %s\n' "$*"; }
bad() { printf '\033[0;31m[FAIL]\033[0m %s\n' "$*"; exit 1; }

[[ -d "$SOURCE_DIR" ]] || bad "Diagram sources not found: $SOURCE_DIR"
mkdir -p "$OUTPUT_DIR"

shopt -s nullglob
SOURCES=("$SOURCE_DIR"/*.mmd)
shopt -u nullglob
[[ ${#SOURCES[@]} -gt 0 ]] || bad "No .mmd sources in $SOURCE_DIR"

say "Rendering ${#SOURCES[@]} diagram(s)"

STALE=0
for source in "${SOURCES[@]}"; do
  name="$(basename "$source" .mmd)"
  target="$OUTPUT_DIR/$name.svg"

  if [[ "$CHECK_ONLY" == "1" ]]; then
    # Compare against a fresh render in a temporary directory.
    temp="$(mktemp -d)"
    npx --yes @mermaid-js/mermaid-cli -i "$source" -o "$temp/$name.svg" -c "$CONFIG" \
      >/dev/null 2>&1 || { rm -rf "$temp"; bad "Failed to render $name"; }
    if [[ ! -f "$target" ]]; then
      echo "MISSING  $name.svg"
      STALE=1
    elif ! cmp -s "$temp/$name.svg" "$target"; then
      echo "STALE    $name.svg"
      STALE=1
    else
      echo "current  $name.svg"
    fi
    rm -rf "$temp"
    continue
  fi

  npx --yes @mermaid-js/mermaid-cli -i "$source" -o "$target" -c "$CONFIG" \
    >/dev/null 2>&1 || bad "Failed to render $name"
  size="$(wc -c <"$target" | tr -d ' ')"
  printf '  %-28s %6s bytes\n' "$name.svg" "$size"
done

if [[ "$CHECK_ONLY" == "1" ]]; then
  [[ "$STALE" == "0" ]] || bad "Some diagrams are stale. Run: bash tools/build-drel-diagrams.sh"
  ok "All diagrams are current"
  exit 0
fi

ok "Diagrams rendered into ${OUTPUT_DIR#$ROOT/}"
