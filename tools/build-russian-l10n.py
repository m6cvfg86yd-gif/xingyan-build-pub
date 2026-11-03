from __future__ import annotations

import json
import re
import time
import urllib.parse
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Sources" / "L10n.swift"
OUTPUT = ROOT / "Sources" / "L10nRussian.swift"
ENDPOINT = "https://translate.googleapis.com/translate_a/single"
ENTRY = re.compile(r'^\s*("(?:\\.|[^"\\])*")\s*:\s*("(?:\\.|[^"\\])*")\s*,?\s*$')
SEPARATOR = " ⟪ZXQ_RU_SEGMENT_7F3A⟫ "

OVERRIDES = {
    "Xingyan": "Синъянь",
    "Xingyan Select": "Выбор Синъянь",
    "Xiaoxing": "Сяосин",
    "Xiaoxing Pro": "Сяосин Pro",
    "Xiaoxing Assistant": "Помощник Сяосин",
    "World": "Мир",
    "Moments": "Моменты",
    "Life Circle": "Круг жизни",
    "Notes": "Заметки",
    "New note": "Новая заметка",
    "Edit note": "Изменить заметку",
    "Music": "Музыка",
    "Listen to Music": "Слушать музыку",
    "Language & Region": "Язык и регион",
    "English": "Английский",
    "Chinese": "Китайский",
    "Russian": "Русский",
    "Simplified Chinese": "Китайский (упрощённый)",
    "Xiaoxing settings": "Настройки Сяосин",
    "Xinglian World": "Мир Синлянь",
}


def decode_swift_string(token: str) -> str:
    return json.loads(token)


def encode_swift_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def load_entries() -> list[tuple[str, str]]:
    entries: list[tuple[str, str]] = []
    seen: set[str] = set()
    for line in SOURCE.read_text(encoding="utf-8").splitlines():
        match = ENTRY.match(line)
        if not match:
            continue
        source = decode_swift_string(match.group(1))
        english = decode_swift_string(match.group(2))
        if not english.strip() or source in seen:
            continue
        seen.add(source)
        entries.append((source, english))
    return entries


def translate(text: str) -> str:
    query = urllib.parse.urlencode(
        {
            "client": "gtx",
            "sl": "en",
            "tl": "ru",
            "dt": "t",
            "q": text,
        }
    )
    request = urllib.request.Request(
        ENDPOINT + "?" + query,
        headers={
            "User-Agent": (
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                "AppleWebKit/605.1.15 Version/18.0 Safari/605.1.15"
            )
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        payload = json.loads(response.read().decode("utf-8"))
    return "".join(piece[0] for piece in payload[0] if piece and piece[0])


def translate_chunk(chunk: list[tuple[str, str]]) -> list[str]:
    source = SEPARATOR.join(text for _, text in chunk)
    translated = translate(source)
    parts = re.split(r"\s*⟪\s*ZXQ[_\s-]*RU[_\s-]*SEGMENT[_\s-]*7F3A\s*⟫\s*", translated)
    if len(parts) != len(chunk):
        parts = []
        for _, text in chunk:
            parts.append(translate(text))
            time.sleep(0.08)
    if len(parts) != len(chunk):
        raise RuntimeError(f"translation count mismatch: {len(parts)} != {len(chunk)}")
    return [part.strip() for part in parts]


def main() -> None:
    entries = load_entries()
    translations: dict[str, str] = {}
    chunk: list[tuple[str, str]] = []
    chunk_chars = 0

    for entry in entries:
        _, english = entry
        if english in OVERRIDES:
            translations[entry[0]] = OVERRIDES[english]
            continue
        size = len(english) + len(SEPARATOR)
        if chunk and chunk_chars + size > 3200:
            for (source, _), result in zip(chunk, translate_chunk(chunk)):
                translations[source] = result
            chunk = []
            chunk_chars = 0
            time.sleep(0.12)
        chunk.append(entry)
        chunk_chars += size

    if chunk:
        for (source, _), result in zip(chunk, translate_chunk(chunk)):
            translations[source] = result

    lines = [
        "import Foundation",
        "",
        "enum L10nRussian {",
        "    static let dict: [String: String] = [",
    ]
    for source, english in entries:
        translated = translations.get(source, english)
        lines.append(f"        {encode_swift_string(source)}: {encode_swift_string(translated)},")
    lines.extend(["    ]", "}", ""])
    OUTPUT.write_text("\n".join(lines), encoding="utf-8")
    print(f"Wrote {len(entries)} Russian entries to {OUTPUT}")


if __name__ == "__main__":
    main()
