#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MISC = (ROOT / "Sources" / "MiscPages.swift").read_text(encoding="utf-8")
FEED = (ROOT / "Sources" / "FeedView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("works page verification failed: " + message)


require("var createdAt: String?" in FEED,
        "feed items must decode their creation time")
require("struct WorksView: View" in MISC,
        "works profile view must remain in place")
require("private let cols = Array(" in MISC
        and "count: 3" in MISC
        and ".aspectRatio(3.0 / 4.0" in MISC,
        "works must use a three-column portrait cover grid")
require("private var profileCover: String" in MISC
        and "private var coverBanner: some View" in MISC,
        "works profile must have the Douyin-style cover and overlapping avatar")
require("[Tr(\"作品\"), Tr(\"喜欢\"), Tr(\"私密\")]" in MISC
        and "pinnedViews: [.sectionHeaders]" in MISC,
        "works, likes and private tabs must pin above the cover grid")
require("isPrivate($0)" in MISC and "tag.contains(\"draft\")" in MISC,
        "private and draft works must not leak into the public works tab")
require("mineFromAll" in MISC and "$0.author?.id == myId" in MISC,
        "the works page must recover the signed-in user's posts from the feed")
require("errorState" in MISC and "loadError" in MISC,
        "failed works requests must show a retry state instead of a blank page")
print("works-douyin: passed")
