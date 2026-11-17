#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ME = (ROOT / "Sources" / "MeView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("Me page baseline verification failed: " + message)


require(
    "let g = it.group ?? 1" in ME,
    "Me groups must retain the B2611161617 server ordering",
)
require(
    "out.append(cardsItem(group: item.group))" in ME,
    "the cards shortcut must stay beside the original shop row group",
)
require(
    "private func meGroup(for item: DiscoverItem)" not in ME,
    "the later synthetic regrouping must not replace the 11/16 layout",
)
require(
    "let priority: [String: Int]" not in ME,
    "the later forced feature ordering must not return",
)

print("me-b2611161617: passed")
