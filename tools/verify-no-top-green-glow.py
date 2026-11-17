#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MAIN = (ROOT / "Sources" / "MainTab.swift").read_text(encoding="utf-8")
PRIVACY = (ROOT / "Sources" / "PrivacyView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("top green glow verification failed: " + message)


require(
    "xingyan.topGreenGlow" not in MAIN
    and "xingyan.topGreenGlow" not in PRIVACY,
    "the obsolete green glow preference must be removed",
)
require(
    "StarStatusRail(tab: tab)" not in MAIN,
    "the top green glow renderer must not remain in the app shell",
)
require(
    'Tr("顶部绿色氛围光")' not in PRIVACY,
    "appearance settings must not expose the green glow switch",
)

print("no-top-green-glow: passed")
