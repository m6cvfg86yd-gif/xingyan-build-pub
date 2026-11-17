#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LIST = (ROOT / "Sources" / "NativeChatList.swift").read_text(encoding="utf-8")
ROW = (ROOT / "Sources" / "NativeChatRowCell.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("native chat swipe verification failed: " + message)


require(
    "leadingSwipeActionsConfigurationForItemAt" in LIST,
    "right swipe must use UICollectionView native leading actions",
)
require(
    "trailingSwipeActionsConfigurationForItemAt" in LIST,
    "left swipe must use UICollectionView native trailing actions",
)
require(
    LIST.count("UIContextualAction(") >= 4,
    "pin, unread, hide and delete must be native contextual actions",
)
require(
    LIST.count("performsFirstActionWithFullSwipe = false") == 2,
    "native full-swipe must not mutate or delete rows accidentally",
)
require(
    "foreground.addGestureRecognizer(pan)" not in ROW,
    "custom row pan recognizer must not compete with the collection view",
)
require(
    "gestureRecognizerShouldBegin" not in ROW,
    "native rows must not veto UICollectionView's system swipe gesture",
)
require(
    "contextMenuConfigurationForItemAt" not in LIST,
    "chat rows must not keep the old long-press context menu",
)
require(
    "collection.allowsSelection = true" in LIST,
    "native row selection must remain enabled for taps without a child tap gesture",
)
require(
    "didSelectItemAt indexPath: IndexPath" in LIST,
    "opening a conversation must use UICollectionView native selection",
)
require(
    "canEditItemAt indexPath: IndexPath" in LIST,
    "native rows must explicitly allow system edit and swipe actions",
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
