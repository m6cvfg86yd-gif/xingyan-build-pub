#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "Sources" / "App.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("LINE registration verification failed: " + message)


require("Color(hex: 0x06C755)" in APP, "registration must use the LINE brand green")
require("registrationModeTabs\n" not in APP,
        "the obsolete single-option tab strip must not render")
require(
    ".frame(width: 72, height: 72)" in APP,
    "the registration header must use the centered LINE-style brand lockup",
)
require(
    "RoundedRectangle(cornerRadius: 14, style: .continuous)" in APP,
    "LINE-style registration fields must use soft rounded cards",
)

print("line-registration: passed")
