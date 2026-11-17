#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VIEW = (ROOT / "Sources" / "ChatsView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat menu icon verification failed: " + message)


require(
    'Image(systemName: "line.3.horizontal.decrease.circle")' in VIEW,
    "the chats top-right action must match the three-line menu shown above Favorites",
)
require(
    'Image(systemName: "square.and.pencil")' not in VIEW,
    "the old compose icon must not remain in the chats top bar",
)

print("chat-menu-icon: passed")
