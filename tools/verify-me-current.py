#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ME = (ROOT / "Sources" / "MeView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("Me page verification failed: " + message)


require(
    "let g = meGroup(for: it)" in ME,
    "the Me page must use the current functional grouping",
)
require(
    '"favorites", "stickers", "works", "cards": return 2' in ME,
    "my content shortcuts must stay together",
)
require(
    'case "moments": return 3' in ME and 'case "settings": return 4' in ME,
    "moments and settings must have separate current groups",
)
require(
    "let priority: [String: Int]" in ME,
    "the current feature priority ordering must remain",
)
require(
    "private var nativeMeList" in ME and "currentMeRows" in ME,
    "the Me page must render through the native list row builder",
)
require(
    ".listStyle(.insetGrouped)" in ME,
    "the Me page must use the native inset-grouped list style",
)
require(
    "private func meSectionTitle" in ME,
    "native list sections need user-facing headings",
)
require(
    "nativeStat(value:" in ME and "nativeMeItemRow(item)" in ME,
    "profile stats and feature rows must stay in native list rows",
)
for removed in (
    "orbitMeTop",
    "lightMeRows",
    "darkMeRows",
    "MeCardRowBackground",
):
    require(
        removed not in ME,
        f"the old Me page implementation must be deleted, not hidden: {removed}",
    )

print("me-current: passed")
