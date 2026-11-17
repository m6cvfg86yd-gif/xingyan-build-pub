#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VIEW = (ROOT / "Sources" / "NewUserOnboardingView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("LINE onboarding verification failed: " + message)


require("Color(hex: 0x06C755)" in VIEW, "onboarding must use the LINE brand green")
require("VStack(spacing: 10)" in VIEW, "feature guidance must use separate LINE-style cards")
require(
    "RoundedRectangle(cornerRadius: 14, style: .continuous).fill(LinearGradient(" in VIEW,
    "the primary onboarding action must use the LINE rounded button",
)
require("0x25D366" not in VIEW, "legacy WhatsApp green must be removed from onboarding")

print("line-onboarding: passed")
