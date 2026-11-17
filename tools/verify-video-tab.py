#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MAIN = (ROOT / "Sources" / "MainTab.swift").read_text(encoding="utf-8")
BAR = (ROOT / "Sources" / "NativeTabBar.swift").read_text(encoding="utf-8")
VIDEO = (ROOT / "Sources" / "VideoTabView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("video tab verification failed: " + message)


require("VideoTabView()" in MAIN, "the video page must be mounted as a main tab")
require("(0..<5).contains(next)" in MAIN, "all five tab indexes must route")
require('UIImage(systemName: "play.rectangle")' in BAR,
        "the video tab must use the Apple play-rectangle icon")
require("items.count == 5" in BAR, "the tab bar must expose five items")
require('Text(Tr("正在开发中"))' in VIDEO, "the video page must show the requested placeholder")

print("video-tab: passed")
