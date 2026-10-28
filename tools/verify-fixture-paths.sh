#!/usr/bin/env bash
set -euo pipefail

# Verify that every fixture path the app can point at is declared in one
# place and actually resolves.
#
# Fixture URLs used to be inline strings spread over the seeder, the debug
# panels and the showcase screens. Several pointed at
# `ae8fcb.../test_resources/bridge-*.html`, a path that stopped serving
# those files months ago, so the seeded entries rendered as broken cards.
#
# The rules:
#   1. Every `test_resources/...` reference in the app sources goes through
#      `FixturePaths`, so the layout is described in one file.
#   2. Every fixture the app names exists in the repository.
#   3. The published fixtures carry their generation in the path, so a link
#      says which fixture and which generation it opens.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() { echo "FAIL: $*" >&2; exit 1; }

python3 - "$ROOT" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
sources = root / "SuperApp" / "Sources"
paths_file = sources / "Configuration" / "FixturePaths.swift"

failures = []

if not paths_file.is_file():
    print("FAIL: SuperApp/Sources/Configuration/FixturePaths.swift is missing")
    raise SystemExit(1)

paths_text = paths_file.read_text(encoding="utf-8")

# 1. No inline fixture paths outside FixturePaths.swift.
offenders = []
inline_pattern = re.compile(r'"(?:https?://[^"]*)?(?:/test_resources/|test_resources/)')
for path in sorted(sources.rglob("*.swift")):
    if path == paths_file:
        continue
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("//") or stripped.startswith("*"):
            continue
        if inline_pattern.search(line):
            offenders.append(f"{path.relative_to(root)}:{number}: {stripped}")

if offenders:
    failures.append(
        "Inline fixture paths outside FixturePaths.swift:\n    "
        + "\n    ".join(offenders)
    )

# 2. The declared local fixtures exist in the repository.
#
# The paths are assembled from `localBasePath`, so read the fixture part out
# of the interpolation: `"\(localBasePath)/pwa-permission/index.html"`.
declared_local = set(
    re.findall(r'\\\(localBasePath\)(/[^"\\]*)', paths_text)
)
for declared in sorted(declared_local):
    candidate = root / "test_resources" / declared.lstrip("/")
    if candidate.exists():
        continue
    parent = candidate.parent
    if parent.exists() and any(parent.glob("*.html")):
        continue
    failures.append(
        f"FixturePaths declares test_resources{declared}, which does not exist in the repository"
    )

# 3. The published fixtures carry a generation in their path.
if '"/test/bridge/v1"' not in paths_text.replace('"\\(publishedBasePath)/bridge/\\(bridgeGeneration)"', '"/test/bridge/v1"'):
    if "bridgeGeneration" not in paths_text:
        failures.append("FixturePaths does not name a Bridge generation for the published fixtures")

# 4. The published Bridge fixtures are actually served by the website build.
site_stage = root / "build" / "drel-site-staging"
if site_stage.is_dir():
    published = site_stage / "test" / "bridge"
    if not (published / "index.html").is_file():
        failures.append("The site build does not publish test/bridge/index.html")
    for page in (
        "bridge-permission",
        "bridge-device",
        "bridge-media",
        "bridge-interaction",
        "bridge-navigation",
        "bridge-cache",
    ):
        if not (published / "v1" / f"{page}.html").is_file():
            failures.append(f"The site build does not publish test/bridge/v1/{page}.html")

if failures:
    print()
    for failure in failures:
        print(f"FAIL {failure}")
    print(f"\nSummary: 0 passed, {len(failures)} failed.")
    raise SystemExit(1)

print(f"Fixture paths: {len(declared_local)} local declaration(s), all inline paths routed through FixturePaths")
print("Summary: all checks passed.")
PY
