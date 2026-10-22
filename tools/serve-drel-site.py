#!/usr/bin/env python3
"""Local preview server for the Drel website.

It mirrors the Cloudflare Pages behaviour that the site actually depends on:

- reads ``_headers`` and applies the per-path rules (MIME overrides, cache
  control, ``X-Robots-Tag``);
- serves ``index.html`` for directory requests, like Pages does;
- answers ``/health`` so the site link checker can probe the server itself.

Plain ``python3 -m http.server`` is not good enough: the strong-offline
fixtures depend on ``manifest.webmanifest`` being served as
``application/manifest+json`` and on immutable caching for versioned assets.

Usage:
    python3 tools/serve-drel-site.py [--port 8788] [--dir build/drel-site-staging]
"""

from __future__ import annotations

import argparse
import http.server
import mimetypes
import os
import posixpath
import re
import socketserver
import sys
import threading
import urllib.parse
from pathlib import Path

RULE_RE = re.compile(r"^\s*(\S+)\s*$")


def parse_headers(path: Path) -> list[tuple[str, dict[str, str]]]:
    """Parse a Cloudflare Pages ``_headers`` file.

    Returns a list of ``(path_pattern, headers)`` in file order. Later rules
    win, matching Pages' behaviour where the most specific match is applied
    last for a given path.
    """
    if not path.is_file():
        return []

    rules: list[tuple[str, dict[str, str]]] = []
    current: dict[str, str] | None = None
    current_pattern: str | None = None

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.rstrip()
        if not line.strip() or line.strip().startswith("#"):
            continue
        if not line.startswith((" ", "\t")):
            # A path line starts a new rule block.
            match = RULE_RE.match(line)
            if not match:
                current = None
                current_pattern = None
                continue
            current_pattern = match.group(1)
            current = {}
            rules.append((current_pattern, current))
            continue
        if current is None:
            continue
        if ":" not in line:
            continue
        name, _, value = line.partition(":")
        current[name.strip()] = value.strip()

    return rules


def pattern_to_regex(pattern: str) -> re.Pattern[str] | None:
    """Translate a Pages path pattern into a regex.

    Supports ``*`` (single segment) and ``**`` (any depth) wildcards. A pattern
    without a trailing slash also matches the directory itself.
    """
    normalized = pattern.strip()
    if not normalized:
        return None

    normalized = normalized.rstrip("/")
    trailing_slash = pattern.endswith("/")
    escaped = re.escape(normalized)
    escaped = escaped.replace(r"\*\*", "\x00").replace(r"\*", "\x01")
    escaped = escaped.replace("\x00", ".*").replace("\x01", "[^/]*")
    suffix = "/" if trailing_slash else "(?:/.*)?"
    return re.compile(f"^{escaped}{suffix}$")


def collect_headers(
    rules: list[tuple[str, dict[str, str]]], request_path: str
) -> dict[str, str]:
    matched: dict[str, str] = {}
    for pattern, headers in rules:
        regex = pattern_to_regex(pattern)
        if regex is None:
            continue
        if regex.match(request_path):
            matched.update(headers)
    return matched


class DrelSiteHandler(http.server.SimpleHTTPRequestHandler):
    """Static handler that applies the site's ``_headers`` rules."""

    server_version = "DrelSitePreview/1.0"

    def __init__(self, *args, directory: str, header_rules: list, **kwargs):
        self._header_rules = header_rules
        self._root = Path(directory).resolve()
        super().__init__(*args, directory=directory, **kwargs)

    # -- helpers ---------------------------------------------------------
    def _resolve(self, url_path: str) -> Path | None:
        """Map a request path to a file inside the site root."""
        path = urllib.parse.urlsplit(url_path).path
        path = urllib.parse.unquote(path)
        # Normalise away any `..` segments before touching the filesystem.
        normalized = posixpath.normpath(path)
        if normalized.startswith(".."):
            return None
        if normalized.endswith("/"):
            normalized += "index.html"
        candidate = (self._root / normalized.lstrip("/")).resolve()
        try:
            candidate.relative_to(self._root)
        except ValueError:
            return None
        if candidate.is_dir():
            candidate = candidate / "index.html"
        return candidate

    def _apply_headers(self, send_header, request_path: str) -> None:
        applied = collect_headers(self._header_rules, request_path)
        for name, value in applied.items():
            send_header(name, value)
        # A Content-Type in `_headers` replaces the sniffed default. Sending
        # both would produce a duplicate header, which some clients reject
        # under `nosniff`.
        return "Content-Type" in applied

    # -- verbs -----------------------------------------------------------
    def do_GET(self) -> None:  # noqa: N802 - http.server API
        if urllib.parse.urlsplit(self.path).path == "/health":
            body = b'{"status":"ok"}'
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self._serve(send_body=True)

    def do_HEAD(self) -> None:  # noqa: N802 - http.server API
        self._serve(send_body=False)

    def _serve(self, send_body: bool) -> None:
        request_path = urllib.parse.urlsplit(self.path).path
        target = self._resolve(request_path)
        if target is None or not target.is_file():
            self.send_error(404, "Not Found")
            return

        content_type, _ = mimetypes.guess_type(target.name)
        if target.name == "manifest.webmanifest":
            content_type = "application/manifest+json"
        elif target.suffix == ".webmanifest":
            content_type = "application/manifest+json"
        elif target.suffix == ".json":
            content_type = "application/json"
        elif target.suffix == ".zip":
            content_type = "application/zip"
        elif target.suffix == ".md":
            content_type = "text/markdown"
        content_type = content_type or "application/octet-stream"
        if content_type.startswith("text/") or content_type in {
            "application/json",
            "application/manifest+json",
            "application/javascript",
        }:
            content_type = f"{content_type}; charset=utf-8"

        data = target.read_bytes()
        self.send_response(200)
        if not self._apply_headers(self.send_header, request_path):
            # Only send a default Content-Type when `_headers` did not set one.
            self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        if send_body:
            self.wfile.write(data)

    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))


class ThreadedServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8788)
    parser.add_argument("--dir", default="build/drel-site-staging")
    parser.add_argument("--host", default="127.0.0.1")
    args = parser.parse_args()

    root = Path(args.dir).resolve()
    if not root.is_dir():
        print(f"Site directory not found: {root}", file=sys.stderr)
        print("Run `bash tools/build-drel-site.sh` first.", file=sys.stderr)
        return 1

    rules = parse_headers(root / "_headers")
    handler = lambda *a, **kw: DrelSiteHandler(  # noqa: E731
        *a, directory=str(root), header_rules=rules, **kw
    )

    with ThreadedServer((args.host, args.port), handler) as httpd:
        print(f"Drel site preview: http://{args.host}:{httpd.server_address[1]}")
        print(f"Serving: {root}")
        print(f"Loaded {len(rules)} _headers rule(s). Press Ctrl+C to stop.")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nStopped.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
