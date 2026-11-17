#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "Sources" / "App.swift").read_text(encoding="utf-8")
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
INFO = (ROOT / "Sources" / "GroupInfoView.swift").read_text(encoding="utf-8")
CONTACTS = (ROOT / "Sources" / "ContactsView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("delete-friend navigation verification failed: " + message)


require(
    "func returnToChatsList()" in APP
    and "openChat = nil" in APP
    and "wantChatsTab = true" in APP,
    "the app must expose one deterministic return-to-chats action",
)
require(
    "app.returnToChatsList()" in CHAT,
    "chat exit must use the shared navigation action",
)
require(
    "app.returnToChatsList()" in INFO,
    "deleting a friend from chat info must return to the chats list",
)
require(
    "app.returnToChatsList()" in CONTACTS,
    "deleting a friend from contacts must return to the chats list",
)

print("delete-friend-navigation: passed")
