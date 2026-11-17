#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PANELS = (ROOT / "Sources" / "Panels.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("plus panel verification failed: " + message)


start = PANELS.find("struct PlusPanel")
end = PANELS.find("\nprivate struct PlusTileStyle", start)
require(start >= 0 and end > start, "plus panel implementation must exist")
panel = PANELS[start:end]
require(
    ".fill(.ultraThinMaterial)" in panel,
    "plus tiles must use a native translucent surface",
)
require(
    "radius: 8, y: 3" in panel,
    "plus tiles must use restrained depth instead of heavy colored shadows",
)
require(
    "size: L.v(20.5, 6.2, 23)" in panel,
    "plus tile symbols must use the refined visual weight",
)

print("plus-panel: passed")
