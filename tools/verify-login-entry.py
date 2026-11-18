#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "Sources" / "App.swift").read_text(encoding="utf-8")
SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("login entry verification failed: " + message)


require(
    'Text(Tr("账号密码登录"))' in APP,
    "the main login page must expose account/password login directly",
)
require(
    "Button { openWay(.password) }" in APP,
    "the direct login button must open the existing account/password sheet",
)
require(
    "sliderLogin: raw.sliderLogin === 1 ? 1 : 0" in SERVER,
    "slider login must be opt-in instead of breaking normal existing accounts",
)
start = SERVER.find("function loginNeedsSlider")
end = SERVER.find("\n/* 违规告警", start)
guard = SERVER[start:end]
require(
    start >= 0 and end > start,
    "the slider risk gate must exist",
)
require(
    "knownDevice(user, req)" not in guard,
    "a reinstall must not force the slider for a correct username/password login",
)
require(
    "await lookupCredentialUserByUsername(rawName)" in SERVER,
    "username login must fetch the authoritative user record from its owner shard",
)
require(
    "async function lookupCredentialUserByUsername" in SERVER
    and "const local = db.users.find((row) =>" in SERVER,
    "credential lookup must not return the stripped public user cache",
)

print("login-entry: passed")
