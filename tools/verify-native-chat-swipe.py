#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LIST = (ROOT / "Sources" / "NativeChatList.swift").read_text(encoding="utf-8")
ROW = (ROOT / "Sources" / "NativeChatRowCell.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("native chat swipe verification failed: " + message)


require(
    "UISwipeActionsConfiguration" not in LIST,
    "the unreliable system collection swipe callback must not remain",
)
require(
    "trailingSwipeActionsConfigurationForItemAt" not in LIST,
    "left swipe must not depend on the system callback that fails in the custom cell",
)
require(
    "UIGestureRecognizerDelegate" in ROW,
    "the row must arbitrate horizontal swipe against vertical scrolling in UIKit",
)
require(
    "foreground.addGestureRecognizer(pan)" in ROW,
    "the foreground must install a cell-level UIKit swipe recognizer",
)
require(
    "gestureRecognizerShouldBegin" in ROW,
    "vertical scrolling must remain with the collection view",
)
require(
    "freezeEnclosingScroll()" in ROW and "restoreEnclosingScroll()" in ROW,
    "horizontal swipes must temporarily own the gesture and restore scrolling",
)
require(
    "contextMenuConfigurationForItemAt" not in LIST,
    "chat rows must not keep the old long-press context menu",
)
require(
    "didSelectItemAt indexPath: IndexPath" in LIST,
    "opening a conversation must use UICollectionView native selection",
)
require(
    "shouldSelectItemAt indexPath: IndexPath" in LIST
    and "dismissOpenSwipeActions()" in LIST,
    "tapping an open row must close actions before opening the chat",
)
require(
    "collection.isDirectionalLockEnabled" not in LIST,
    "directional lock must not compete with the system horizontal swipe recognizer",
)
require(
    "foreground.addGestureRecognizer(tap)" not in ROW,
    "the whole row must not install a child tap recognizer over native swipe handling",
)
require(
    "avatarView.addGestureRecognizer(tap)" in ROW,
    "only the avatar may retain a separate tap recognizer",
)

print("native-chat-swipe: passed")
