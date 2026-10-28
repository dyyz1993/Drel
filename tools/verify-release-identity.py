#!/usr/bin/env python3
"""Verify the release identity of a build before it ships.

The version identity of a Drel build is a triple:

    marketing version + build number + git commit

``project.yml`` is the single source of truth for the first two. This gate
asserts that:

1. every store-facing configuration has a unique marketing/build pair;
2. the marketing version that is being shipped has a changelog section;
3. that changelog section has a release directory with the required documents;
4. the release notes do not claim a feature the build does not contain
   (checked against the declared action allowlist);
5. the working tree is clean enough to attribute the build to a commit.

Usage:
    python3 tools/verify-release-identity.py [--marketing 1.5.0] [--build 103]
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT_YML = ROOT / "project.yml"
CHANGELOG = ROOT / "CHANGELOG.md"
RELEASE_ROOT = ROOT / "docs" / "release"
APP_DELEGATE = ROOT / "SuperApp" / "Sources" / "AppDelegate.swift"

# Configurations that actually reach a store or a TestFlight group.
STORE_CONFIGS = ("Release", "Drel14Release", "Drel15Release")

# The actions the Drel 1.5 Store host policy allows. This is the fallback
# list, used only when the AppDelegate allowlist cannot be parsed. The
# authoritative source is the AppDelegate itself: see `store_allowlist()`.
#
# `clipboard` and `getLocation` are real, reviewable grant-based actions in
# the 1.5 build, so the copy has to describe them. The review notes must
# not claim less than the build actually does — an under-declared
# capability is the same Guideline 2.3.1 problem as an over-claimed one.
STORE_ACTION_ALLOWLIST = {
    "haptic",
    "vibrate",
    "share",
    "fullscreen",
    "clipboard",
    "getLocation",
    "addToHomeScreen",
}

# Actions that read user data. They need a persistent, user-revocable
# grant, and they need their own review notes row.
GRANT_BASED_ACTIONS = {"clipboard", "getLocation"}

# Actions that only produce a transient, in-session effect. A manifest
# declaration is an allowlist for them, never standing user consent.
DECLARATION_ONLY_ACTIONS = {
    "haptic",
    "vibrate",
    "share",
    "fullscreen",
    "addToHomeScreen",
}

# Capabilities the public copy must never claim. Each entry lists the
# English and the Chinese wording, because the release notes are bilingual
# and a copy check that only reads one language misses half the risk.
FORBIDDEN_CLAIMS = [
    ("camera scanning", "相机", "扫码"),
    ("photo library", "相册"),
    ("bluetooth", "蓝牙"),
    ("microphone", "麦克风"),
    ("javascript-to-native bridge", "原生 bridge", "原生桥"),
    ("contacts", "通讯录"),
]

BLOCK_RE = re.compile(
    r"^\s{2,}(?P<config>[A-Za-z0-9]+):\s*$"
    r"|^\s*MARKETING_VERSION:\s*\"(?P<marketing>[^\"]+)\""
    r"|^\s*CURRENT_PROJECT_VERSION:\s*\"(?P<build>[^\"]+)\"",
    re.M,
)


def parse_project_configs(text: str) -> dict[str, dict[str, str]]:
    """Return {config_name: {marketing, build}} for every configuration.

    A configuration block is a key at the ``configs:`` indentation level. Its
    marketing and build numbers may be declared inside the block or inherited
    from the target's base settings, so the base values are collected first and
    used as the fallback.
    """
    # Base (target level) values, inherited by configurations that omit them.
    base: dict[str, str] = {}
    base_marketing = re.search(r'^\s{8}MARKETING_VERSION:\s*"([^"]+)"', text, re.M)
    base_build = re.search(r'^\s{8}CURRENT_PROJECT_VERSION:\s*"([^"]+)"', text, re.M)
    if base_marketing:
        base["marketing"] = base_marketing.group(1)
    if base_build:
        base["build"] = base_build.group(1)

    configs: dict[str, dict[str, str]] = {}
    current: dict[str, str] | None = None
    in_configs = False
    config_indent = 0
    for line in text.splitlines():
        stripped = line.strip()
        if not in_configs:
            if re.match(r"^configs:\s*$", stripped):
                in_configs = True
                config_indent = len(line) - len(line.lstrip()) + 2
            continue
        indent = len(line) - len(line.lstrip())
        if indent < config_indent:
            # The block ended. A target-level block may be followed by another
            # target, so keep looking instead of stopping.
            in_configs = False
            current = None
            continue
        if indent == config_indent:
            config_match = re.match(r"^([A-Za-z0-9]+):\s*$", stripped)
            if config_match:
                current = configs.setdefault(config_match.group(1), dict(base))
            else:
                current = None
            continue
        if current is None:
            continue
        marketing = re.match(r'^MARKETING_VERSION:\s*"([^"]+)"', stripped)
        if marketing:
            current["marketing"] = marketing.group(1)
            continue
        build = re.match(r'^CURRENT_PROJECT_VERSION:\s*"([^"]+)"', stripped)
        if build:
            current["build"] = build.group(1)
    return configs


def run_git(args: list[str]) -> str:
    try:
        result = subprocess.run(
            ["git", *args], cwd=ROOT, capture_output=True, text=True, timeout=60
        )
        return result.stdout.strip()
    except (subprocess.SubprocessError, FileNotFoundError):
        return ""


def store_allowlist() -> tuple[set[str], str]:
    """Read the Drel 1.5 native action allowlist from the AppDelegate.

    The Store build's real capability surface is the
    `DREL_V2_MANAGED_ACTIONS_ONLY` branch of `AppDelegate.swift`. The
    release copy has to describe exactly this set: claiming more is a
    false claim, and claiming less hides a capability from review.

    Returns the action set and a human-readable source description.
    """
    if not APP_DELEGATE.is_file():
        return set(STORE_ACTION_ALLOWLIST), "fallback (AppDelegate.swift missing)"
    text = APP_DELEGATE.read_text(encoding="utf-8")
    match = re.search(
        r"#elseif DREL_V2_MANAGED_ACTIONS_ONLY.*?"
        r"nativeActionAllowlist\s*=\s*\[(.*?)\]",
        text,
        re.S,
    )
    if not match:
        return set(STORE_ACTION_ALLOWLIST), "fallback (allowlist not found)"
    actions = set(re.findall(r'"([A-Za-z][A-Za-z0-9]*)"', match.group(1)))
    if not actions:
        return set(STORE_ACTION_ALLOWLIST), "fallback (allowlist empty)"
    return actions, "SuperApp/Sources/AppDelegate.swift"


def mentioned_actions(text: str) -> set[str]:
    """Return the action names a release document actually discusses."""
    return {
        action
        for action in STORE_ACTION_ALLOWLIST
        if action in text
    }


# A line that mentions a forbidden capability but denies offering it is fine.
NEGATION_MARKERS = (
    "not ",
    "no ",
    "never",
    "without",
    "unavailable",
    "are not",
    "is not",
    "does not",
    "cannot",
    "still not",
    "未",
    "不",
    "没有",
    "仍",
)

# Headings that frame the following text as a limitation rather than a
# capability list.
LIMITATION_HEADINGS = (
    "restrained capability scope",
    "not enabled",
    "not available",
    "what drel does not do",
    "remain unavailable",
    "remains unavailable",
    "不开放",
    "未开放",
    "能力范围保持克制",
)

# Phrases that assert a capability is present.
ASSERTION_MARKERS = (
    "now supports",
    "supports ",
    "includes ",
    "enables ",
    "added ",
    "adds ",
    "can now",
    "新",
    "支持",
    "新增",
)


def claims_capability(line: str, term: str) -> bool:
    """Return True when a line asserts that a capability is offered.

    A line that merely lists a capability as unavailable, or that denies it,
    is not a claim. Only an affirmative sentence about offering it is.
    """
    lowered = line.lower()
    if term.lower() not in lowered:
        return False

    # A limitation heading turns the whole bullet into a denial.
    for heading in LIMITATION_HEADINGS:
        if heading in lowered:
            return False

    # Look for a negation between the start of the sentence and the term.
    index = lowered.find(term.lower())
    prefix = lowered[max(0, index - 140) : index]
    if any(marker in prefix for marker in NEGATION_MARKERS):
        # A negation in the same clause usually wins, but an affirmative
        # marker in the same clause means the sentence is about offering it.
        if not any(marker in prefix for marker in ASSERTION_MARKERS):
            return False

    if any(marker in lowered for marker in ASSERTION_MARKERS):
        return True

    # No marker at all: a bare mention inside a capability list is a claim.
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--marketing")
    parser.add_argument("--build")
    args = parser.parse_args()

    failures: list[str] = []

    if not PROJECT_YML.is_file():
        print("project.yml is missing.", file=sys.stderr)
        return 1

    configs = parse_project_configs(PROJECT_YML.read_text(encoding="utf-8"))

    print("Store-facing configurations:")
    for name in STORE_CONFIGS:
        config = configs.get(name)
        if not config:
            failures.append(f"[config] {name} configuration is missing from project.yml")
            continue
        marketing = config.get("marketing", "?")
        build = config.get("build", "?")
        print(f"  {name:<16} {marketing} ({build})")

    # A build number must be unique across configurations.
    build_numbers = {
        name: config.get("build")
        for name, config in configs.items()
        if config.get("build")
    }
    seen: dict[str, str] = {}
    for name, build in build_numbers.items():
        if build in seen:
            failures.append(
                f"[build] configurations {seen[build]} and {name} share build "
                f"number {build}. Build numbers must be unique per configuration."
            )
        else:
            seen[build] = name

    # The version being shipped must be documented.
    if args.marketing:
        marketing = args.marketing
        if marketing not in CHANGELOG.read_text(encoding="utf-8"):
            failures.append(
                f"[changelog] marketing version {marketing} has no CHANGELOG.md section."
            )
        release_dir = RELEASE_ROOT / marketing
        if not release_dir.is_dir():
            failures.append(
                f"[release] docs/release/{marketing}/ does not exist. A shipped "
                f"version needs its release notes and review notes."
            )
        else:
            for required in ("RELEASE-NOTES.md", "app-review-notes.md"):
                if not (release_dir / required).is_file():
                    failures.append(
                        f"[release] docs/release/{marketing}/{required} is missing."
                    )
            notes_path = release_dir / "RELEASE-NOTES.md"
            if notes_path.is_file():
                notes = notes_path.read_text(encoding="utf-8")
                # The public copy lives in a fenced block, one bullet per
                # capability. Judge each bullet as a whole: a negation may sit
                # on an earlier line of the same bullet.
                for bullet in re.findall(r"^[•\-*]\s*(.+?)(?=\n[•\-*]|\n```|\Z)",
                                         notes, re.M | re.S):
                    flattened = " ".join(bullet.split())
                    for entry in FORBIDDEN_CLAIMS:
                        label, *wording = entry
                        for term in wording:
                            if not claims_capability(flattened, term):
                                continue
                            failures.append(
                                f"[claims] RELEASE-NOTES.md claims \"{label}\", "
                                f"which the Store host policy does not offer: "
                                f"{flattened[:80]}"
                            )
                            break

            # The review notes must describe every action the Store build
            # actually allows. Under-declaring a capability is the same
            # Guideline 2.3.1 accuracy problem as over-claiming one: a
            # reviewer who finds an undisclosed action stops the review.
            review_path = release_dir / "app-review-notes.md"
            if review_path.is_file():
                review = review_path.read_text(encoding="utf-8")
                allowlist, source = store_allowlist()
                missing = sorted(allowlist - mentioned_actions(review))
                if missing:
                    failures.append(
                        f"[review] app-review-notes.md does not describe "
                        f"{', '.join(missing)}, which the Store build allows "
                        f"(source: {source}). Declare every allowed action so "
                        f"review sees the real capability surface."
                    )
                lowered = review.lower()
                for action in sorted(GRANT_BASED_ACTIONS & allowlist):
                    index = lowered.find(action.lower())
                    if index < 0:
                        continue
                    window = lowered[max(0, index - 200) :]
                    if not any(
                        marker in window
                        for marker in (
                            "grant",
                            "permission",
                            "revoke",
                            "consent",
                            "授权",
                            "许可",
                            "撤销",
                            "同意",
                        )
                    ):
                        failures.append(
                            f"[review] app-review-notes.md mentions {action} "
                            f"without explaining that it needs a persistent, "
                            f"user-revocable grant."
                        )

    # The build must be attributable to a commit.
    commit = run_git(["rev-parse", "--short", "HEAD"])
    dirty = run_git(["status", "--porcelain"])
    print(f"\nCommit: {commit or '(not a git repository)'}")
    if commit and dirty:
        uncommitted = len([l for l in dirty.splitlines() if l.strip()])
        print(f"Working tree: {uncommitted} uncommitted change(s)")
        if args.marketing:
            failures.append(
                f"[git] the working tree has {uncommitted} uncommitted change(s). "
                f"Commit before shipping so the build maps to a known commit."
            )

    if args.build:
        print(f"Requested build: {args.build}")
        matching = [
            name
            for name, config in configs.items()
            if config.get("build") == args.build
        ]
        if not matching:
            print(f"  (not yet present in project.yml — expected for a new build)")

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
