#!/usr/bin/env python3
"""Verify that internal Markdown links in the documentation resolve.

A broken documentation link is invisible in a diff but very visible to a
reader who just followed it. This gate catches the two most common cases:

- a link to a file that was renamed or moved;
- a link to a file that only ever existed in another repository.

Usage:
    python3 tools/verify-docs-links.py [--root docs] [--file CHANGELOG.md]
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

LINK_RE = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
SKIP_PREFIXES = ("http://", "https://", "#", "mailto:", "tel:", "javascript:", "data:")

# The website source is checked by tools/verify-drel-site.py against the
# built staging output, so it is not scanned here.
DEFAULT_SKIP_DIRS = {".git", "build", "Pods", "node_modules", ".build"}


def iter_markdown(root: Path, skip_dirs: set[str]):
    for path in sorted(root.rglob("*.md")):
        if any(part in skip_dirs for part in path.parts):
            continue
        yield path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".")
    parser.add_argument("--file", action="append", default=[])
    args = parser.parse_args()

    repo_root = Path(args.root).resolve()
    skip_dirs = DEFAULT_SKIP_DIRS

    if args.file:
        targets = [Path(f).resolve() for f in args.file]
    else:
        targets = list(iter_markdown(repo_root, skip_dirs))

    failures: list[str] = []
    checked = 0

    for path in targets:
        if not path.is_file():
            failures.append(f"[missing] {path} does not exist")
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        for match in LINK_RE.finditer(text):
            target = match.group(1).strip()
            if target.startswith(SKIP_PREFIXES):
                continue
            # A link may carry a title after the path: "path" "title".
            if " " in target:
                target = target.split(" ", 1)[0]
            if not target:
                continue
            # Only relative links are in scope; absolute paths are repo-root
            # references that are checked separately.
            if target.startswith("/"):
                candidate = repo_root / target.lstrip("/")
            else:
                candidate = (path.parent / target.split("#", 1)[0]).resolve()
            checked += 1
            if not candidate.exists():
                try:
                    shown = candidate.relative_to(repo_root)
                except ValueError:
                    shown = candidate
                failures.append(f"[link] {path.relative_to(repo_root)} -> {target} (missing {shown})")

    print(f"Markdown files scanned: {len(targets)}")
    print(f"Internal links checked: {checked}")
    if failures:
        print()
        for failure in failures:
            print(f"FAIL {failure}")
        print(f"\nSummary: 0 passed, {len(failures)} failed.")
        return 1
    print("\nSummary: all checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
