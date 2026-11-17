#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("known device verification failed: " + message)


start = SERVER.find("function knownDevice")
end = SERVER.find("\n/* 登录要不要弹滑动验证", start)
require(start >= 0 and end > start, "known-device login guard must exist")
guard = SERVER[start:end]
require(
    "d.ip === info.ip && d.device === info.device" in guard,
    "reinstalled devices must match prior IP and device description",
)
require(
    "d.id === info.deviceId" in guard,
    "stable device identifiers must remain the primary match",
)

print("known-device-login: passed")
