#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
API = (ROOT / "Sources" / "API.swift").read_text(encoding="utf-8")
CARD = (ROOT / "Sources" / "MomentFeedCard.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("moment editorial verification failed: " + message)


require(
    "struct MomentPromotion: Codable, Hashable" in API,
    "moments must expose optional sponsored-content metadata",
)
require(
    "var promotion: MomentPromotion? = nil" in API,
    "existing moments must keep decoding without ad metadata",
)
require(
    "private func promotionBanner" in CARD,
    "ads must share the regular card skeleton instead of creating a second feed layout",
)
require(
    "RoundedRectangle(cornerRadius: 22, style: .continuous)" in CARD,
    "the editorial feed must use the refined card surface",
)
require(
    "cornerRadius: 18, style: .continuous" in CARD,
    "single photos and video must use the premium media treatment",
)
require(
    "systemTextFont(16.5, .regular, relativeTo: .body)" in CARD,
    "moment copy must use the refined editorial type scale",
)
require(
    "availableWidth - (cardInset + contentInset) * 2" in CARD,
    "media width must follow the new card insets",
)

print("moment-editorial: passed")
