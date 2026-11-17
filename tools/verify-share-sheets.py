#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SHARE = (ROOT / "Sources" / "ShareSheet.swift").read_text(encoding="utf-8")
VIDEO = (ROOT / "Sources" / "VideoShareSheet.swift").read_text(encoding="utf-8")
MALL = (ROOT / "Sources" / "MallDeep.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("share sheet verification failed: " + message)


require(
    "struct ShareSheet: UIViewControllerRepresentable" not in SHARE,
    "the default iOS activity controller must not remain the public share UI",
)
require(
    "struct ShareSheet: View" in SHARE,
    "the shared outbound sheet must be a custom SwiftUI page",
)
for token in ("分享到", "SharePreviewCard", "ShareActionTile", "系统分享", "取消"):
    require(token in SHARE, f"shared Xiaohongshu-style hierarchy is missing {token}")
require(
    "UIActivityViewController(activityItems: items" in SHARE,
    "system apps must remain available through the custom More action",
)
require(
    "SharePreviewCard" in VIDEO and "ShareActionTile" in VIDEO,
    "video sharing must use the shared preview and action hierarchy",
)
require(
    "SharePreviewCard" in MALL and "ShareActionTile" in MALL,
    "mall product sharing must use the shared preview and action hierarchy",
)
require(
    ".ddLight()" not in MALL[MALL.index("struct DDShareSheet"):MALL.index("struct DDOrderDetailView")],
    "the mall share sheet must support the app's dark appearance",
)

print("share-sheets: passed")
