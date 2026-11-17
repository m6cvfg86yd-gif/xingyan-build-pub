#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
API = (ROOT / "Sources" / "API.swift").read_text(encoding="utf-8")
MUSIC = (ROOT / "Sources" / "MusicShare.swift").read_text(encoding="utf-8")
GAMES = (ROOT / "Sources" / "GamesPageView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("catalog refresh verification failed: " + message)


require(
    "private enum APICatalogCache" in API,
    "music and mini-app catalogs need a last-known-good local cache",
)
require(
    'let cacheKey = "catalog.music." + cacheNamespace' in API,
    "the music cache must be isolated by server",
)
require(
    'let cacheKey = "catalog.miniapps." + cacheNamespace + "." + kind' in API,
    "the mini-app cache must be isolated by server and kind",
)
require(
    "struct MusicTrack: Codable" in MUSIC,
    "music tracks must be encodable for resilient catalog caching",
)
require(
    MUSIC.count("await API.shared.loadEndpointList()") >= 1
    and GAMES.count("await API.shared.loadEndpointList()") >= 1,
    "empty first responses must rotate/probe endpoints before showing an empty page",
)
require(
    "private func loadGames() async" in GAMES,
    "the games page needs an explicit retryable load path",
)

print("catalog-refresh-cache: passed")
