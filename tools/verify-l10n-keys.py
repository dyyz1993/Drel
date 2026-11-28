#!/usr/bin/env python3

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "SuperApp" / "Sources"
RESOURCE_ROOT = ROOT / "SuperApp" / "Resources"
STRING_FILES = [
    RESOURCE_ROOT / "en.lproj" / "Localizable.strings",
    RESOURCE_ROOT / "zh-Hans.lproj" / "Localizable.strings",
]


def referenced_keys() -> set[str]:
    source = "\n".join(path.read_text(encoding="utf-8") for path in SOURCE_ROOT.rglob("*.swift"))
    return set(re.findall(r'L10n\.tr\(\s*"([^"]+)"', source))


def defined_keys(path: Path) -> set[str]:
    return set(re.findall(r'^\s*"((?:[^"\\]|\\.)+)"\s*=', path.read_text(encoding="utf-8"), re.MULTILINE))


def main() -> int:
    references = referenced_keys()
    failures: list[str] = []
    for path in STRING_FILES:
        definitions = defined_keys(path)
        missing = sorted(references - definitions)
        if missing:
            failures.append(f"{path.relative_to(ROOT)} missing {len(missing)} keys:")
            failures.extend(f"  {key}" for key in missing)

    if failures:
        print("\n".join(failures))
        return 1

    print(f"L10n keys verified: {len(references)} referenced, {len(STRING_FILES)} locales complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
