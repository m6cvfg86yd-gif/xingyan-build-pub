#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VIEW = (ROOT / "Sources" / "ContactsView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("contacts WhatsApp verification failed: " + message)


require("        49\n" in VIEW, "contact avatars must use WhatsApp's 49pt size")
require(
    "nativeQuickIcon(item, size: 40)" in VIEW,
    "contact utility rows must use the shared WhatsApp-style icon system",
)
require(
    ".background(contactsSectionFill)" in VIEW,
    "alphabet headers must stay neutral instead of becoming a green block",
)
require(
    "RoundedRectangle(cornerRadius: 16, style: .continuous)" in VIEW,
    "utility contacts must be grouped in a rounded WhatsApp-style card",
)

print("contacts-whatsapp: passed")
