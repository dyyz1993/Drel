#!/usr/bin/env python3
"""Verify the built Drel site: no broken internal links, no missing demo pages.

This is the guard that keeps the website from shipping "resources present but
landing page 404" — the failure that hid the action and template demos.

Checks:

1. Every internal link (``href``/``src``) in every HTML file resolves to a
   file that the site will actually serve.
2. Every directory that is meant to be a landing page has an ``index.html``.
3. Every demo directory ships the full artifact set (app page, manifest,
   resource manifest, gateway manifest).
4. ``sitemap.xml`` only lists pages that exist.
5. ``_headers`` covers the manifest/package MIME rules of every demo.

Usage:
    python3 tools/verify-drel-site.py [--dir build/drel-site-staging]
"""

from __future__ import annotations

import argparse
import json
import posixpath
import re
import sys
import urllib.parse
from pathlib import Path

LINK_RE = re.compile(r'(?:href|src)\s*=\s*"([^"]+)"', re.IGNORECASE)

# A demo directory must provide a landing page and a Web App Manifest.
# The resource manifest and the signed parent manifest only apply to demos
# that publish a strong-offline package.
DEMO_REQUIRED = [
    "index.html",
    "manifest.webmanifest",
]
DEMO_OFFLINE_REQUIRED = [
    "package.json",
    "gateway-manifest.json",
]
DEMO_APP_PAGE_HINT = "v1/index.html"

# Directories under /test/ that are demos rather than plain landing pages.
DEMO_ROOT = "test"

# The production gateway signs the action demo and App Review uses it to
# exercise the exact Store allowlist. Keep the action names on the wire.
ACTION_DEMO_ACTIONS = [
    "addToHomeScreen",
    "clipboard",
    "fullscreen",
    "getLocation",
    "haptic",
    "share",
    "vibrate",
]


class Site:
    def __init__(self, root: Path):
        self.root = root

    def site_path(self, url_path: str) -> str:
        """Normalise a URL path into a site-relative path (no leading slash)."""
        path = urllib.parse.urlsplit(url_path).path
        path = urllib.parse.unquote(path)
        normalized = posixpath.normpath(path)
        if normalized in (".", "/"):
            return "index.html"
        normalized = normalized.lstrip("/")
        if normalized.endswith("/"):
            normalized += "index.html"
        return normalized

    def resolve_link(self, source_rel: str, target: str) -> str:
        """Resolve a link found in ``source_rel`` into a site-relative path.

        Relative links are resolved against the directory of the file that
        contains them, exactly like a browser would.
        """
        if target.startswith("/"):
            return self.site_path(target)
        base = posixpath.dirname(source_rel)
        joined = posixpath.normpath(posixpath.join(base, target))
        if joined in (".", ""):
            return "index.html"
        return joined.lstrip("./") if joined.startswith("./") else joined

    def exists(self, site_rel: str) -> bool:
        candidate = self.root / site_rel
        if candidate.is_file():
            return True
        # Pages may be referenced with or without a trailing slash; the
        # preview server and Cloudflare Pages both serve index.html.
        if site_rel.endswith("index.html"):
            alt = self.root / site_rel[: -len("index.html")]
            if alt.is_dir() and (alt / "index.html").is_file():
                return True
            return False
        # A directory reference without a trailing slash still serves its
        # index.html, exactly like Cloudflare Pages.
        if candidate.is_dir() and (candidate / "index.html").is_file():
            return True
        return False


def iter_html(root: Path):
    for path in sorted(root.rglob("*.html")):
        yield path


def relative_to_root(path: Path, root: Path) -> str:
    return path.relative_to(root).as_posix()


def check_links(site: Site, failures: list[str], notes: list[str]) -> int:
    checked = 0
    for html_path in iter_html(site.root):
        source = relative_to_root(html_path, site.root)
        text = html_path.read_text(encoding="utf-8", errors="replace")
        for raw in LINK_RE.findall(text):
            target = raw.strip()
            if not target or target.startswith(("#", "mailto:", "tel:", "javascript:")):
                continue
            if target.startswith(("http://", "https://", "//")):
                # External link; only same-host absolute URLs are in scope.
                parsed = urllib.parse.urlsplit(target)
                if parsed.netloc not in ("drel.app", "www.drel.app", "localhost", "127.0.0.1"):
                    continue
                site_rel = site.site_path(parsed.path)
            else:
                site_rel = site.resolve_link(source, target)
            checked += 1
            if not site.exists(site_rel):
                failures.append(
                    f"[link] {source} -> {raw} (resolved to {site_rel}) is missing"
                )
    return checked


def check_demo_landings(site: Site, failures: list[str]) -> int:
    """Every demo directory needs a landing page and the full artifact set."""
    checked = 0
    test_root = site.root / DEMO_ROOT
    if not test_root.is_dir():
        return 0
    for demo_dir in sorted(p for p in test_root.iterdir() if p.is_dir()):
        checked += 1
        rel = relative_to_root(demo_dir, site.root)
        if not (demo_dir / "index.html").is_file():
            failures.append(f"[demo] {rel}/ has no landing index.html")
        for required in DEMO_REQUIRED:
            if not (demo_dir / required).is_file():
                failures.append(f"[demo] {rel}/ is missing {required}")
        if not (demo_dir / DEMO_APP_PAGE_HINT).is_file():
            failures.append(f"[demo] {rel}/ is missing the app page {DEMO_APP_PAGE_HINT}")
        # Offline artifacts are only required when the demo publishes them.
        if (demo_dir / "package.json").is_file():
            for required in DEMO_OFFLINE_REQUIRED:
                if not (demo_dir / required).is_file():
                    failures.append(f"[demo] {rel}/ is missing {required}")
    return checked


def check_sitemap(site: Site, failures: list[str], notes: list[str]) -> int:
    sitemap = site.root / "sitemap.xml"
    if not sitemap.is_file():
        failures.append("[sitemap] sitemap.xml is missing")
        return 0
    text = sitemap.read_text(encoding="utf-8")
    count = 0
    for loc in re.findall(r"<loc>([^<]+)</loc>", text):
        count += 1
        site_rel = site.site_path(loc)
        if not site.exists(site_rel):
            failures.append(f"[sitemap] {loc} is listed but does not exist")
    return count


def check_headers_rules(site: Site, failures: list[str], notes: list[str]) -> int:
    """Every demo manifest/package needs its MIME rule in ``_headers``."""
    headers_file = site.root / "_headers"
    if not headers_file.is_file():
        failures.append("[headers] _headers is missing")
        return 0
    headers_text = headers_file.read_text(encoding="utf-8")
    test_root = site.root / DEMO_ROOT
    if not test_root.is_dir():
        return 0
    count = 0
    for demo_dir in sorted(p for p in test_root.iterdir() if p.is_dir()):
        rel = relative_to_root(demo_dir, site.root)
        for filename, expected_type in (
            ("manifest.webmanifest", "application/manifest+json"),
            ("package.json", "application/json"),
        ):
            if not (demo_dir / filename).is_file():
                continue
            count += 1
            pattern = f"/{rel}/{filename}"
            if pattern not in headers_text:
                failures.append(
                    f"[headers] {pattern} has no Content-Type rule in _headers"
                )
                continue
            block = headers_text.split(pattern, 1)[1]
            block = block.split("\n\n", 1)[0]
            if expected_type not in block:
                failures.append(
                    f"[headers] {pattern} should set Content-Type: {expected_type}"
                )
    return count


def find_app_root(site: Site, demo_dir: Path, package: dict) -> Path | None:
    """Locate the directory the resource manifest paths are relative to.

    The resource manifest is published next to the app (for example
    ``/test/template/package.json``) while its ``path`` entries are relative
    to the app root (``/test/template/v1``). The Web App Manifest's
    ``start_url`` names that app root authoritatively, so it wins over
    guessing from the entrypoint alone.
    """
    demo_rel = demo_dir.relative_to(site.root)
    demo_parts = tuple(demo_rel.parts)

    start_url = ""
    manifest_path = demo_dir / "manifest.webmanifest"
    if manifest_path.is_file():
        try:
            start_url = json.loads(manifest_path.read_text(encoding="utf-8")).get(
                "start_url", ""
            )
        except json.JSONDecodeError:
            start_url = ""

    candidates: list[Path] = []
    if start_url:
        parsed = urllib.parse.urlsplit(start_url)
        start_path = urllib.parse.unquote(parsed.path)
        parts = tuple(p for p in start_path.split("/") if p)
        # Map the published URL back onto the site root by removing the
        # demo's own site path prefix.
        if parts[: len(demo_parts)] == demo_parts:
            parts = parts[len(demo_parts) :]
        if parts:
            candidates.append(demo_dir.joinpath(*parts).parent)

    entrypoint = package.get("entrypoint")
    if entrypoint:
        candidates.append(demo_dir / "v1")
        candidates.extend(sorted(p for p in demo_dir.iterdir() if p.is_dir()))

    for candidate in candidates:
        if entrypoint and (candidate / entrypoint).is_file():
            return candidate
    for candidate in candidates:
        if candidate.is_dir():
            return candidate
    return None


def check_package_integrity(site: Site, failures: list[str], notes: list[str]) -> int:
    """The resource manifest digest must match the served bytes."""
    import hashlib

    test_root = site.root / DEMO_ROOT
    if not test_root.is_dir():
        return 0
    count = 0
    for package_path in sorted(test_root.rglob("package.json")):
        rel = relative_to_root(package_path, site.root)
        try:
            package = json.loads(package_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as error:
            failures.append(f"[package] {rel} is not valid JSON: {error}")
            continue
        files = package.get("files") or []
        if not files:
            failures.append(f"[package] {rel} lists no files")
            continue
        app_root = find_app_root(site, package_path.parent, package)
        if app_root is None:
            failures.append(
                f"[package] {rel} cannot locate the app root for entrypoint "
                f"{package.get('entrypoint')!r}"
            )
            continue
        for entry in files:
            rel_path = entry.get("path")
            if not rel_path:
                continue
            target = app_root / rel_path
            count += 1
            if not target.is_file():
                failures.append(f"[package] {rel} references missing file {rel_path}")
                continue
            digest = hashlib.sha256(target.read_bytes()).hexdigest()
            if entry.get("sha256") and entry["sha256"] != digest:
                failures.append(
                    f"[package] {rel}: sha256 mismatch for {rel_path}"
                )
    return count


def check_diagrams(site: Site, failures: list[str], notes: list[str]) -> int:
    """Every generated diagram must be referenced by a page, and every
    referenced diagram must exist."""
    diagram_root = site.root / "assets" / "diagrams"
    if not diagram_root.is_dir():
        return 0

    available = {p.name for p in diagram_root.glob("*.svg")}
    referenced: set[str] = set()
    checked = 0

    for html_path in iter_html(site.root):
        source = relative_to_root(html_path, site.root)
        text = html_path.read_text(encoding="utf-8", errors="replace")
        for match in re.finditer(r'src="([^"]*diagrams/[^"]+)"', text):
            target = match.group(1)
            name = posixpath.basename(target)
            referenced.add(name)
            checked += 1
            if not (site.root / "assets" / "diagrams" / name).is_file():
                failures.append(
                    f"[diagram] {source} references {target} but the file is missing"
                )

    for name in sorted(available - referenced):
        failures.append(
            f"[diagram] assets/diagrams/{name} is never referenced by any page"
        )

    return checked


def check_action_demo_contract(site: Site, failures: list[str]) -> int:
    """The action demo must declare exactly the Store's seven wire actions."""
    manifest_path = site.root / "test" / "actions" / "gateway-manifest.json"
    if not manifest_path.is_file():
        failures.append("[actions] test/actions/gateway-manifest.json is missing")
        return 0
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        failures.append(f"[actions] gateway-manifest.json is not valid JSON: {error}")
        return 0

    declared = sorted(
        item.get("action")
        for item in manifest.get("capabilities_v2", [])
        if isinstance(item, dict) and isinstance(item.get("action"), str)
    )
    expected = sorted(ACTION_DEMO_ACTIONS)
    if declared != expected:
        missing = sorted(set(expected) - set(declared))
        unexpected = sorted(set(declared) - set(expected))
        failures.append(
            "[actions] gateway-manifest.json capabilities_v2 must match the "
            f"Store action wire names; missing={missing}, unexpected={unexpected}"
        )

    if manifest.get("cache", {}).get("version") != "4":
        failures.append(
            "[actions] gateway-manifest.json cache.version must be 4 for the "
            "route-matrix demo update"
        )
    return len(declared)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dir", default="build/drel-site-staging")
    args = parser.parse_args()

    root = Path(args.dir).resolve()
    if not root.is_dir():
        print(f"Site directory not found: {root}", file=sys.stderr)
        print("Run `bash tools/build-drel-site.sh` first.", file=sys.stderr)
        return 1

    site = Site(root)
    failures: list[str] = []
    notes: list[str] = []

    links = check_links(site, failures, notes)
    demos = check_demo_landings(site, failures)
    sitemap = check_sitemap(site, failures, notes)
    header_rules = check_headers_rules(site, failures, notes)
    package_files = check_package_integrity(site, failures, notes)
    diagrams = check_diagrams(site, failures, notes)
    action_contract = check_action_demo_contract(site, failures)

    print(f"Site root: {root}")
    print(f"Links checked:       {links}")
    print(f"Demo directories:    {demos}")
    print(f"Sitemap entries:     {sitemap}")
    print(f"Header rules checked:{header_rules:>4}")
    print(f"Package files hashed:{package_files:>4}")
    print(f"Diagram references:  {diagrams:>4}")
    print(f"Action declarations: {action_contract:>4}")

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
