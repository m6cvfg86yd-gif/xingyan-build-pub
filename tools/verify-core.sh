#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/core.lock.json"

python3 - "$ROOT" "$MANIFEST" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
with open(sys.argv[2], encoding="utf-8") as f:
    data = json.load(f)

def verified_content(relative_path, content):
    return content

failed = []
for item in data["files"]:
    path = root / item["path"]
    if not path.is_file():
        failed.append(f'{item["path"]}: missing')
        continue
    content = path.read_bytes().replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    content = verified_content(item["path"], content)
    digest = hashlib.sha256(content).hexdigest()
    if len(content) != item["size"] or digest != item["sha256"]:
        failed.append(f'{item["path"]}: changed')

if failed:
    print("Core verification failed:")
    for row in failed:
        print(" ", row)
    raise SystemExit(1)

print("Core verification passed.")
PY

python3 - "$ROOT" "$ROOT/protected.lock.json" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
with open(sys.argv[2], encoding="utf-8") as f:
    data = json.load(f)

def verified_content(relative_path, content):
    return content

failed = []
for item in data["files"]:
    path = root / item["path"]
    if not path.is_file():
        failed.append(f'{item["path"]}: missing')
        continue
    content = path.read_bytes().replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    content = verified_content(item["path"], content)
    digest = hashlib.sha256(content).hexdigest()
    if len(content) != item["size"] or digest != item["sha256"]:
        failed.append(f'{item["path"]}: protected chat baseline changed')

if failed:
    print("Protected chat verification failed:")
    for row in failed:
        print(" ", row)
    raise SystemExit(1)

print("Protected chat verification passed.")
PY

python3 "$ROOT/tools/verify-l10n.py"
