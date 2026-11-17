#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "Sources" / "App.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("registration phone-only verification failed: " + message)


require(
    "@State private var mode: Mode = .phone" in APP,
    "registration must open on the server-supported phone flow",
)
require(
    'registrationTab(Tr("自选星言号")' not in APP,
    "the obsolete account-registration tab must not be shown",
)
require(
    'registrationTab(Tr("手机号注册"), selected: true)' in APP,
    "phone registration must be the only visible registration path",
)

print("registration-phone-only: passed")
