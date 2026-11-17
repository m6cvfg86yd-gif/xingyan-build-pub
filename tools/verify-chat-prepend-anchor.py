#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LIST = (ROOT / "Sources" / "NativeStaticList.swift").read_text(encoding="utf-8")
SCROLL = (ROOT / "Sources" / "ScrollProbe.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat prepend anchor verification failed: " + message)


require(
    "attributes.frame.minY - collection.contentOffset.y" in LIST,
    "prepending must capture the visible row's exact viewport anchor",
)
require(
    "attributes.frame.minY - anchor.delta" in LIST,
    "prepending must restore the same row to the same pixel position",
)
require(
    "ChatScrollHandle.shared.clearPendingPrepend()" in LIST,
    "exact native anchoring must clear the height-delta fallback",
)
require(
    "func clearPendingPrepend()" in SCROLL,
    "the scroll handle must support clearing a pending prepend",
)

print("chat-prepend-anchor: passed")
