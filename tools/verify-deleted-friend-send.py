#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("deleted-friend send verification failed: " + message)


start = SERVER.find("function directFriendMessageError")
end = SERVER.find("\nfunction deliverMessage", start)
require(start >= 0 and end > start, "direct friend send guard must exist")
guard = SERVER[start:end]
require(
    "friendSetCached(user.id).has(peerId)" not in guard,
    "a stale cache must never restore send permission after deletion",
)
require(
    "(relation && relation.status === 'accepted')" in guard,
    "normal direct sends must require an accepted friendship",
)
require(
    "friendPairWasRemoved(user.id, peerId)" in guard,
    "friend deletion tombstones must be evaluated before delivery",
)

print("deleted-friend-send: passed")
