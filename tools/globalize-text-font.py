from __future__ import annotations

import argparse
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "Sources"
PATTERN = re.compile(r"\.font\(\.system\(|Font\.system\(")
SEMANTIC = re.compile(
    r"\.font\(\.(largeTitle|title|title2|title3|headline|subheadline|body|callout|footnote|caption|caption2)"
    r"(?:\.(weight\(\.([A-Za-z]+)\)|bold\(\)))?\)"
)
STYLE_SIZE = {
    "largeTitle": 34,
    "title": 28,
    "title2": 22,
    "title3": 20,
    "headline": 17,
    "subheadline": 15,
    "body": 17,
    "callout": 16,
    "footnote": 13,
    "caption": 12,
    "caption2": 11,
}


def classify(lines: list[str], index: int, match: re.Match[str]) -> str:
    start = max(0, index - 10)
    context = "\n".join(lines[start:index] + [lines[index][:match.start()]])
    image_at = context.rfind("Image(systemName")
    text_at = max(context.rfind("Text("), context.rfind("Label("))
    if image_at >= 0 and image_at > text_at:
        return "icon"
    if text_at >= 0 and text_at > image_at:
        return "text"
    return "unknown"


def semantic_replacement(match: re.Match[str]) -> str:
    style = match.group(1)
    modifier = match.group(2) or ""
    weight = match.group(3)
    if modifier == "bold()":
        weight = "bold"
    elif style == "headline" and weight is None:
        weight = "semibold"
    size = STYLE_SIZE[style]
    if weight:
        return f".font(pfStyled(size: {size}, weight: .{weight}))"
    return f".font(pfStyled(size: {size}))"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    counts = {"text": 0, "icon": 0, "unknown": 0, "semantic_text": 0, "semantic_icon": 0}
    changed_lines = 0
    unknown_rows: list[str] = []
    changed_files: list[str] = []

    for path in sorted(SOURCES.glob("*.swift")):
        original = path.read_text(encoding="utf-8")
        lines = original.splitlines(keepends=True)
        file_changed = False
        for index, line in enumerate(lines):
            matches = list(PATTERN.finditer(line))
            semantic_matches = list(SEMANTIC.finditer(line))
            if not matches and not semantic_matches:
                continue
            for match in reversed(matches):
                kind = classify(lines, index, match)
                counts[kind] += 1
                if kind == "unknown":
                    rel = path.relative_to(ROOT)
                    unknown_rows.append(f"{rel}:{index + 1}: {line.strip()}")
                    continue
                if kind != "text":
                    continue
                tail = line[match.start():]
                if tail.startswith(".font(.system("):
                    tail = ".font(pfStyled(" + tail[len(".font(.system("):]
                else:
                    tail = "pfStyled(" + tail[len("Font.system("):]
                line = line[:match.start()] + tail
                file_changed = True
                changed_lines += 1
            for match in reversed(semantic_matches):
                kind = classify(lines, index, match)
                if kind == "icon":
                    counts["semantic_icon"] += 1
                    continue
                if kind == "unknown":
                    rel = path.relative_to(ROOT)
                    unknown_rows.append(f"{rel}:{index + 1}: {line.strip()}")
                    continue
                line = line[:match.start()] + semantic_replacement(match) + line[match.end():]
                counts["semantic_text"] += 1
                file_changed = True
                changed_lines += 1
            lines[index] = line
        if file_changed:
            changed_files.append(str(path.relative_to(ROOT)))
            if args.apply:
                path.write_text("".join(lines), encoding="utf-8", newline="\n")

    print("counts", counts)
    print("changed_lines", changed_lines)
    print("changed_files", len(changed_files))
    if unknown_rows:
        print("unknown samples:")
        print("\n".join(unknown_rows[:80]))
    if not args.apply:
        print("dry run only; pass --apply to rewrite")


if __name__ == "__main__":
    main()
