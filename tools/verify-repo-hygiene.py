#!/usr/bin/env python3
"""Repository hygiene gate.

Publishing an open-source repository makes its history and its current tree
permanent. These checks stop the two failure modes that actually bite:

1. **Oversized files.** A single 515MB screen recording once sat untracked in
   a design media folder. One accidental ``git add`` would have made every clone
   download it, and GitHub rejects blobs over 100MB outright.
2. **Credentials.** An APNs ``.p8`` key, an admin API key or a device token
   committed once stays in the history forever.

The checks run against the working tree and the index, so they also catch a
file that was staged but not committed.

Usage:
    python3 tools/verify-repo-hygiene.py [--max-file-mb 20] [--check-history]
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

SKIP_DIRS = {
    ".git",
    "build",
    "Pods",
    "node_modules",
    ".build",
    "DerivedData",
    ".services",
    "coverage",
}

# Patterns that indicate a real credential. Kept deliberately narrow: a broad
# entropy matcher produces far too many false positives on hashed asset
# names, base64 icon payloads and test fixtures.
SECRET_PATTERNS = [
    (
        "APNs provider key",
        re.compile(r"-----BEGIN PRIVATE KEY-----[\s\S]{0,80}?AuthKey_"),
    ),
    (
        "APNs key file name",
        re.compile(r"AuthKey_[A-Z0-9]{10}\.p8"),
    ),
    (
        "Apple private key body",
        re.compile(r"-----BEGIN PRIVATE KEY-----\s*MIG[A-Za-z0-9+/=]{40,}"),
    ),
    (
        "generic assigned secret",
        re.compile(
            r"(?i)\b(?:api[_-]?key|secret[_-]?key|access[_-]?token|admin[_-]?key|"
            r"private[_-]?key)\s*[:=]\s*['\"][A-Za-z0-9/+_\-]{24,}['\"]"
        ),
    ),
]

# Allow-listed text that legitimately looks like a secret.
ALLOWLIST = [
    re.compile(r"example\.com"),
    re.compile(r"YOUR_KEY"),
    re.compile(r"changeme-admin-api-key"),
    re.compile(r"\.p8['\"]?\s*$"),
    re.compile(r"APNS_KEY_PATH"),
    re.compile(r"APNS_KEY_DIRECTORY"),
    re.compile(r"keychainService"),
    re.compile(r"push-crypto"),
    re.compile(r"com\.webbridgekit\.superapp"),
]

TEXT_SUFFIXES = {
    ".md", ".swift", ".sh", ".py", ".json", ".yml", ".yaml", ".txt", ".plist",
    ".html", ".css", ".js", ".ts", ".xml", ".yml", ".env", ".example", ".conf",
    ".template", ".pbxproj", ".m", ".h", ".c", ".cpp",
}

# The documented example key id from the deployment guide.
DOCUMENTED_KEY_ID = "your-key-id"


def run_git(args: list[str]) -> str:
    try:
        result = subprocess.run(
            ["git", *args], cwd=ROOT, capture_output=True, text=True, timeout=120
        )
        return result.stdout
    except (subprocess.SubprocessError, FileNotFoundError):
        return ""


def tracked_files() -> list[str]:
    output = run_git(["ls-files", "-z"])
    return [p for p in output.split("\0") if p]


def staged_files() -> list[str]:
    output = run_git(["diff", "--cached", "--name-only", "-z", "--diff-filter=ACMR"])
    return [p for p in output.split("\0") if p]


def is_allowlisted(text: str) -> bool:
    return any(pattern.search(text) for pattern in ALLOWLIST)


def check_large_files(max_bytes: int, failures: list[str]) -> int:
    """Flag any tracked or staged file above the size limit."""
    checked = 0
    candidates = sorted(set(tracked_files()) | set(staged_files()))
    for relative in candidates:
        path = ROOT / relative
        if not path.is_file():
            continue
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        checked += 1
        size = path.stat().st_size
        if size > max_bytes:
            failures.append(
                f"[size] {relative} is {size / 1048576:.1f} MB (limit "
                f"{max_bytes / 1048576:.0f} MB). Do not commit build outputs, "
                f"recordings or packaged archives."
            )
    return checked


def check_secrets(failures: list[str]) -> int:
    """Scan tracked text files for credential-shaped content."""
    checked = 0
    for relative in sorted(set(tracked_files()) | set(staged_files())):
        path = ROOT / relative
        if not path.is_file():
            continue
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        if path.suffix.lower() not in TEXT_SUFFIXES:
            continue
        # Binary or oversized content is not worth scanning as text.
        if path.stat().st_size > 2 * 1024 * 1024:
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        checked += 1
        if is_allowlisted(text):
            continue
        for label, pattern in SECRET_PATTERNS:
            match = pattern.search(text)
            if not match:
                continue
            line_number = text[: match.start()].count("\n") + 1
            failures.append(
                f"[secret] {relative}:{line_number} looks like a {label}. "
                f"Move it to a secret store and rotate it if it was ever real."
            )
    return checked


def check_ignored_but_present(failures: list[str]) -> int:
    """A large file that is only untracked by luck is still a landmine."""
    checked = 0
    output = run_git(["status", "--porcelain", "--untracked-files=all"])
    for line in output.splitlines():
        if not line.startswith("??"):
            continue
        relative = line[3:].strip()
        if not relative:
            continue
        path = ROOT / relative
        if not path.is_file():
            continue
        checked += 1
        size = path.stat().st_size
        if size > 50 * 1024 * 1024:
            failures.append(
                f"[untracked] {relative} is {size / 1048576:.1f} MB and untracked. "
                f"Add it to .gitignore before it is committed by accident."
            )
    return checked


def check_required_files(failures: list[str]) -> int:
    """The public repository must carry its license and change log."""
    required = ["LICENSE", "CHANGELOG.md", "README.md", "CONTRIBUTING.md"]
    checked = 0
    for name in required:
        checked += 1
        if not (ROOT / name).is_file():
            failures.append(f"[required] {name} is missing from the repository root.")
    return checked


def check_history_secrets(failures: list[str]) -> int:
    """Scan the commit history for credential material."""
    output = run_git(["log", "--all", "--diff-filter=AM", "--name-only",
                      "--pretty=format:"])
    checked = 0
    seen: set[str] = set()
    for relative in output.splitlines():
        relative = relative.strip()
        if not relative or relative in seen:
            continue
        if any(part in SKIP_DIRS for part in relative.split("/")):
            continue
        if Path(relative).suffix.lower() not in TEXT_SUFFIXES:
            continue
        seen.add(relative)
        path = ROOT / relative
        if not path.is_file():
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        checked += 1
        if is_allowlisted(text):
            continue
        for label, pattern in SECRET_PATTERNS:
            if pattern.search(text):
                failures.append(
                    f"[history] {relative} contains something shaped like a {label}. "
                    f"History is permanent — rotate the credential and rewrite the commit."
                )
                break
    return checked


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--max-file-mb", type=float, default=20.0)
    parser.add_argument("--check-history", action="store_true")
    args = parser.parse_args()

    failures: list[str] = []
    max_bytes = int(args.max_file_mb * 1024 * 1024)

    files = check_large_files(max_bytes, failures)
    scanned = check_secrets(failures)
    untracked = check_ignored_but_present(failures)
    required = check_required_files(failures)
    history = check_history_secrets(failures) if args.check_history else 0

    print(f"Repository: {ROOT}")
    print(f"Files size-checked:   {files:>6}")
    print(f"Files secret-scanned: {scanned:>6}")
    print(f"Untracked files:      {untracked:>6}")
    print(f"Required files:       {required:>6}")
    if args.check_history:
        print(f"History files scanned:{history:>6}")

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
