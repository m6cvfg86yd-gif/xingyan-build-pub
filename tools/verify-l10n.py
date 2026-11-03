from __future__ import annotations

import json
import re
import sys
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ENTRY = re.compile(r'^\s*("(?:\\.|[^"\\])*")\s*:\s*("(?:\\.|[^"\\])*")\s*,?\s*$')


def parse(path: Path) -> list[tuple[str, str]]:
    rows: list[tuple[str, str]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        match = ENTRY.match(line)
        if match:
            rows.append((json.loads(match.group(1)), json.loads(match.group(2))))
    duplicates = [key for key, count in Counter(key for key, _ in rows).items() if count > 1]
    if duplicates:
        raise SystemExit(f"{path}: duplicate keys: {duplicates[:20]}")
    return rows


def main() -> None:
    english = parse(ROOT / "Sources" / "L10n.swift")
    russian = parse(ROOT / "Sources" / "L10nRussian.swift")
    english_map = dict(english)
    expected = {
        "备忘录": "Notes",
        "新建备忘录": "New note",
        "编辑备忘录": "Edit note",
        "小星": "Xiaoxing",
        "小星智能助手": "Xiaoxing Assistant",
        "听音乐": "Listen to Music",
    }
    mismatched = {
        key: english_map.get(key)
        for key, value in expected.items()
        if english_map.get(key) != value
    }
    if mismatched:
        print(f"Unexpected English labels: {mismatched}")
        sys.exit(1)
    russian_keys = {key for key, _ in russian}
    missing = [key for key, value in english if value and key not in russian_keys]
    empty = [key for key, value in russian if not value.strip()]
    if missing:
        print(f"Missing Russian entries ({len(missing)}): {missing[:20]}")
        sys.exit(1)
    if empty:
        print(f"Empty Russian entries ({len(empty)}): {empty[:20]}")
        sys.exit(1)
    print(f"L10n OK: English={len(english)}, Russian={len(russian)}")


if __name__ == "__main__":
    main()
