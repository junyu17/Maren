#!/usr/bin/env python3
"""Read-only localization catalog audit.

This replaces the obsolete patch script that restored catalogs with
``git checkout`` and reintroduced removed iCloud copy. It never edits files.
Run from the repository root: ``python3 AppStore/patch_catalog.py``.
"""

from __future__ import annotations

import json
from pathlib import Path


CATALOGS = (
    Path("Resources/Localizable.xcstrings"),
    Path("Resources/InfoPlist.xcstrings"),
)
LANGUAGES = ("en", "zh-Hans")
INTENTIONALLY_UNLOCALIZED = {"", "Maren"}


def main() -> int:
    failures: list[str] = []
    for path in CATALOGS:
        catalog = json.loads(path.read_text(encoding="utf-8"))
        strings = catalog.get("strings", {})
        for key, entry in strings.items():
            if key in INTENTIONALLY_UNLOCALIZED:
                continue
            localizations = entry.get("localizations", {})
            for language in LANGUAGES:
                if language not in localizations:
                    failures.append(f"{path}: missing {language}: {key!r}")

    if failures:
        print("\n".join(failures))
        return 1

    print("Localization audit passed: en and zh-Hans are complete.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
