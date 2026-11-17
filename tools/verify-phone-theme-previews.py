#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PRIVACY = (ROOT / "Sources" / "PrivacyView.swift").read_text(encoding="utf-8")
THEMES = (ROOT / "Sources" / "ChatThemes.swift").read_text(encoding="utf-8")
WEATHER = (ROOT / "Sources" / "PlatformAcademy.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("phone preview verification failed: " + message)


require(
    ".frame(width: 128, height: 238)" in PRIVACY,
    "appearance choices must use a portrait phone preview",
)
require(
    ".frame(width: 214, height: 408)" in THEMES,
    "chat theme detail preview must use a phone-shaped canvas",
)
require(
    ".frame(width: 54, height: 86)" in THEMES,
    "each theme row must include a miniature phone preview",
)
require(
    "hourlyForecast" in WEATHER and "dailyForecast" in WEATHER,
    "the bundled weather system must include hourly and daily forecasts",
)

print("phone-theme-previews: passed")
