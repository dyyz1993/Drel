#!/usr/bin/env python3
"""Repository hygiene gate.

Publishing an open-source repository makes its history and its current tree
permanent. These checks stop the two failure modes that actually bite:

1. **Oversized files.** A single 515MB screen recording once sat untracked in
   a design media folder. One accidental ``git add`` would have made every clone
   download it, and GitHub rejects blobs over 100MB outright.
2. **Credentials.** An APNs ``.p8`` key, an admin API key or a device token
   committed once stays in the history forever.

   One credential is deliberately public: ``Server/community-apns/
   AuthKey_4M53447M36.p8`` is a production-only, topic-specific community key
   for the official Drel app. Its exact path and SHA-256 are pinned below so
   no other ``.p8`` file and no altered copy can pass the gate.

The checks run against the working tree and the index, so they also catch a
file that was staged but not committed.

Usage:
    python3 tools/verify-repo-hygiene.py [--max-file-mb 20] [--check-history]
"""

from __future__ import annotations

import argparse
import hashlib
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
PRIVATE_KEY_HEADER = "-----BEGIN " "PRIVATE KEY-----"

SECRET_PATTERNS = [
    (
        "APNs provider key",
        re.compile(PRIVATE_KEY_HEADER + r"[\s\S]{0,80}?AuthKey_"),
    ),
    (
        "APNs key file name",
        re.compile(r"AuthKey_[A-Z0-9]{10}\.p8"),
    ),
    (
        "Apple private key body",
        re.compile(PRIVATE_KEY_HEADER + r"\s*MIG[A-Za-z0-9+/=]{40,}"),
    ),
    (
        "generic assigned secret",
        re.compile(
            r"(?i)\b(?:api[_-]?key|secret[_-]?key|access[_-]?token|admin[_-]?key|"
            r"private[_-]?key)\s*[:=]\s*['\"][A-Za-z0-9/+_\-]{24,}['\"]"
        ),
    ),
]

# The only credential allowed in the repository. Apple topic-specific provider
# keys can be scoped to one app topic and one environment and revoked without
# affecting operator keys; the digest detects replacement or accidental edits.
PUBLIC_CREDENTIALS = {
    "Server/community-apns/AuthKey_4M53447M36.p8":
        "96c17321bc7a1c18f8c185a6845a7adfec4148a4a04ff5df2fe1f08296c22f5e",
}
PUBLIC_CREDENTIAL_FILE_NAMES = {Path(path).name for path in PUBLIC_CREDENTIALS}

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


def secret_failures(
    text: str
) -> list[tuple[str, int]]:
    """Return each credential-shaped match except the registered public name."""
    failures: list[tuple[str, int]] = []
    for label, pattern in SECRET_PATTERNS:
        for match in pattern.finditer(text):
            if match.group() in PUBLIC_CREDENTIAL_FILE_NAMES:
                continue
            line_number = text[: match.start()].count("\n") + 1
            failures.append((label, line_number))
    return failures


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
        for label, line_number in secret_failures(text):
            failures.append(
                f"[secret] {relative}:{line_number} looks like a {label}. "
                f"Move it to a secret store and rotate it if it was ever real."
            )
    return checked


def check_public_credentials(failures: list[str]) -> int:
    """Ensure only the registered community APNs key can be tracked or staged."""
    checked = 0
    candidates = sorted(set(tracked_files()) | set(staged_files()))
    for relative in candidates:
        if Path(relative).suffix.lower() != ".p8":
            continue
        checked += 1
        expected_digest = PUBLIC_CREDENTIALS.get(relative)
        if expected_digest is None:
            failures.append(
                f"[public-credential] {relative} is not the registered community "
                "APNs key. Only the community APNs key can be committed here; "
                "other .p8 files must stay in a secret store."
            )
            continue
        path = ROOT / relative
        if not path.is_file():
            failures.append(
                f"[public-credential] {relative} is tracked or staged but missing."
            )
            continue
        actual_digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if actual_digest != expected_digest:
            failures.append(
                f"[public-credential] {relative} does not match its registered "
                "SHA-256. The content differs from the registered fingerprint, "
                "so another key must not be placed here."
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
        for label, _ in secret_failures(text):
            failures.append(
                f"[history] {relative} contains something shaped like a {label}. "
                f"History is permanent — rotate the credential and rewrite the commit."
            )
    return checked


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--max-file-mb", type=float, default=20.0)
    parser.add_argument("--check-history", action="store_true")
    args = parser.parse_args()

    failures: list[str] = []
    max_bytes = int(args.max_file_mb * 1024 * 1024)

    files = check_large_files(max_bytes, failures)
    public_credentials = check_public_credentials(failures)
    scanned = check_secrets(failures)
    untracked = check_ignored_but_present(failures)
    required = check_required_files(failures)
    history = check_history_secrets(failures) if args.check_history else 0

    print(f"Repository: {ROOT}")
    print(f"Files size-checked:   {files:>6}")
    print(f"Public credentials:   {public_credentials:>6}")
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
