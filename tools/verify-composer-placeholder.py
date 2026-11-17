#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("composer placeholder verification failed: " + message)


require(
    'Text(Tr("输入消息"))' in CHAT,
    "the empty chat composer must show a localized guide",
)
require(
    "if input.isEmpty && !voiceMode && !recorder.recording" in CHAT,
    "the guide must disappear as soon as text or voice input starts",
)
require(
    ".allowsHitTesting(false)" in CHAT,
    "the guide must never intercept typing or caret placement",
)

print("composer-placeholder: passed")
