from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / "core.lock.json"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="+", help="Repository-relative paths to refresh")
    args = parser.parse_args()

    data = json.loads(LOCK.read_text(encoding="utf-8"))
    entries = {item["path"]: item for item in data["files"]}
    for relative in args.paths:
        if relative not in entries:
            raise SystemExit(f"not tracked in core lock: {relative}")
        content = (ROOT / relative).read_bytes()
        content = content.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
        entries[relative]["size"] = len(content)
        entries[relative]["sha256"] = hashlib.sha256(content).hexdigest()
    LOCK.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("updated: " + ", ".join(args.paths))


if __name__ == "__main__":
    main()
