#!/usr/bin/env python3
"""Verify the Drel release notes and changelog.

The release train ships a public changelog plus one directory per release
under ``docs/release/``. This gate keeps them consistent:

1. ``CHANGELOG.md`` exists and every version section has a release date.
2. Every version in the changelog has a matching ``docs/release/<version>/``
   directory, and every such directory has a changelog entry.
3. Each release directory has the required documents.
4. Every changelog entry declares a scope, a verification level and an
   evidence link.
5. Security entries and Bridge entries must point at a real evidence file.
6. The marketing versions in ``project.yml`` are all listed in the changelog.

Usage:
    python3 tools/verify-release-notes.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CHANGELOG = ROOT / "CHANGELOG.md"
RELEASE_ROOT = ROOT / "docs" / "release"
PROJECT_YML = ROOT / "project.yml"

REQUIRED_RELEASE_DOCS = [
    "RELEASE-NOTES.md",
    "app-review-notes.md",
]

# Security and Bridge entries carry the strongest claims, so they must be
# backed by a file that actually exists.
STRICT_SCOPES = {"Security", "Bridge"}
VERIFICATION_LEVELS = {
    "physical-device",
    "simulator",
    "server-test",
    "manual",
    "none",
}

VERSION_RE = re.compile(r"^## \[(\d+\.\d+\.\d+)\] — (\d{4}-\d{2}-\d{2})\s*$", re.M)


def fail(failures: list[str], message: str) -> None:
    failures.append(message)


def parse_changelog(text: str) -> dict[str, dict]:
    """Return {version: {"date": str, "body": str}} for each release section."""
    matches = list(VERSION_RE.finditer(text))
    sections: dict[str, dict] = {}
    for index, match in enumerate(matches):
        start = match.end()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        body = text[start:end]
        # Stop the body at the link definitions at the bottom.
        body = body.split("\n[", 1)[0]
        sections[match.group(1)] = {"date": match.group(2), "body": body}
    return sections


def current_section(sections: dict[str, dict], version: str) -> str:
    return sections.get(version, {}).get("body", "")


def parse_entries(body: str) -> list[str]:
    """Split a release section into entries.

    An entry starts with a ``- `` bullet and continues until the next bullet
    or the end of the section, so a wrapped bullet is parsed as one entry.
    """
    entries: list[str] = []
    current: list[str] = []

    for line in body.splitlines():
        stripped = line.strip()
        if stripped.startswith("- "):
            if current:
                entries.append(" ".join(current))
            current = [stripped[2:].strip()]
        elif current and stripped:
            current.append(stripped)
        elif current and not stripped:
            # A blank line ends the current entry.
            entries.append(" ".join(current))
            current = []

    if current:
        entries.append(" ".join(current))
    return entries


def check_entry_metadata(
    version: str, entry: str, failures: list[str]
) -> tuple[bool, str]:
    """Return (is_strict, scope) after validating one bullet."""
    if "Scope:" not in entry:
        fail(failures, f"[{version}] entry has no 'Scope:' marker: {entry[:70]}")
        return False, ""
    if "Verified:" not in entry:
        fail(failures, f"[{version}] entry has no 'Verified:' marker: {entry[:70]}")
        return False, ""
    if "Evidence:" not in entry:
        fail(failures, f"[{version}] entry has no 'Evidence:' marker: {entry[:70]}")
        return False, ""

    scope_match = re.search(r"Scope:\s*`?([A-Za-z, ]+?)`?\s*—", entry)
    scope = scope_match.group(1).strip() if scope_match else ""
    verified_match = re.search(r"Verified:\s*`?([a-z-]+)`?", entry)
    verified = verified_match.group(1) if verified_match else ""
    if verified not in VERIFICATION_LEVELS:
        fail(
            failures,
            f"[{version}] entry has an unknown verification level {verified!r} "
            f"(allowed: {', '.join(sorted(VERIFICATION_LEVELS))}): {entry[:70]}",
        )
        return False, scope

    scopes = {s.strip() for s in scope.split(",") if s.strip()}
    is_strict = bool(scopes & STRICT_SCOPES)
    return is_strict, scope


def check_evidence_links(version: str, body: str, failures: list[str]) -> None:
    """Every evidence path in the section must resolve to a real file."""
    for match in re.finditer(r"\]\(([^)]+)\)", body):
        target = match.group(1)
        if target.startswith(("http://", "https://", "#")):
            continue
        candidate = (ROOT / target).resolve()
        if not candidate.exists():
            fail(failures, f"[{version}] evidence link does not exist: {target}")


def main() -> int:
    failures: list[str] = []

    if not CHANGELOG.is_file():
        print("CHANGELOG.md is missing at the repository root.", file=sys.stderr)
        return 1

    text = CHANGELOG.read_text(encoding="utf-8")
    sections = parse_changelog(text)
    if not sections:
        fail(failures, "CHANGELOG.md has no parsable '## [x.y.z] — YYYY-MM-DD' section")

    print(f"Changelog: {CHANGELOG.relative_to(ROOT)}")
    print(f"Versions found: {', '.join(sorted(sections, key=lambda v: [int(p) for p in v.split('.')], reverse=True))}")

    for version, info in sections.items():
        body = info["body"]
        # Known issues are not change entries: they record outstanding work
        # and are exempt from the scope/verified/evidence contract.
        known_issues = ""
        if "### Known issues" in body:
            body, known_issues = body.split("### Known issues", 1)

        entries = parse_entries(body)
        if not entries:
            fail(failures, f"[{version}] section has no entries")

        for entry in entries:
            is_strict, scope = check_entry_metadata(version, entry, failures)
            if is_strict:
                evidence = re.search(r"Evidence:\s*\[([^\]]+)\]", entry)
                if not evidence:
                    fail(
                        failures,
                        f"[{version}] strict entry ({scope}) must link an evidence "
                        f"file: {entry[:70]}",
                    )
                else:
                    candidate = (ROOT / evidence.group(1)).resolve()
                    if not candidate.exists():
                        fail(
                            failures,
                            f"[{version}] evidence file does not exist: "
                            f"{evidence.group(1)}",
                        )

        check_evidence_links(version, body, failures)

    # Release directories and changelog entries must agree.
    if RELEASE_ROOT.is_dir():
        for release_dir in sorted(p for p in RELEASE_ROOT.iterdir() if p.is_dir()):
            if not re.match(r"^\d+\.\d+\.\d+$", release_dir.name):
                continue
            if release_dir.name not in sections:
                fail(
                    failures,
                    f"docs/release/{release_dir.name}/ has no CHANGELOG.md entry",
                )
            for required in REQUIRED_RELEASE_DOCS:
                if not (release_dir / required).is_file():
                    fail(
                        failures,
                        f"docs/release/{release_dir.name}/ is missing {required}",
                    )
    else:
        fail(failures, "docs/release/ does not exist")

    for version in sections:
        if not (RELEASE_ROOT / version).is_dir():
            fail(failures, f"CHANGELOG.md lists {version} but docs/release/{version}/ is missing")

    # Every marketing version in project.yml must appear in the changelog.
    if PROJECT_YML.is_file():
        project_text = PROJECT_YML.read_text(encoding="utf-8")
        for match in re.finditer(r'MARKETING_VERSION:\s*"([0-9.]+)"', project_text):
            marketing = match.group(1)
            if marketing not in sections:
                fail(
                    failures,
                    f"project.yml ships marketing version {marketing} but the "
                    f"changelog has no entry for it",
                )

    if failures:
        print()
        for failure in failures:
            print(f"FAIL {failure}")
        print(f"\nSummary: 0 passed, {len(failures)} failed.")
        return 1

    print(f"Release directories checked: {len(sections)}")
    print("\nSummary: all checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
