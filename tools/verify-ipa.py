from __future__ import annotations

import hashlib
import io
import plistlib
import sys
import zipfile
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
APP = "Payload/CHRISChat.app/"
REQUIRED = {
    APP + "CHRIS",
    APP + "Info.plist",
    APP + "AppIcon60x60@2x.png",
    APP + "AppIcon60x60@3x.png",
    APP + "PrivacyInfo.xcprivacy",
    APP + "default.metallib",
    APP + "emoji/star-orbit/pack.json",
    APP + "emoji/star-orbit/shou-dao.gif",
    APP + "emoji/star-orbit/xiang-ni.gif",
    APP + "Frameworks/WebRTC.framework/WebRTC",
    APP + "Frameworks/TXLiteAVSDK_TRTC.framework/TXLiteAVSDK_TRTC",
    APP + "Frameworks/TXFFmpeg.framework/TXFFmpeg",
    APP + "Frameworks/TXSoundTouch.framework/TXSoundTouch",
}


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: verify-ipa.py <ipa>")
    ipa = Path(sys.argv[1])
    with zipfile.ZipFile(ipa) as archive:
        bad = archive.testzip()
        if bad:
            raise SystemExit(f"corrupt ZIP entry: {bad}")
        names = set(archive.namelist())
        missing = sorted(REQUIRED - names)
        if missing:
            raise SystemExit("missing entries: " + ", ".join(missing))

        info = plistlib.loads(archive.read(APP + "Info.plist"))
        binary = archive.read(APP + "CHRIS")
        for value in (
            "Xiaoxing",
            "Notes",
            "Listen to Music",
            "Сяосин",
            "Заметки",
            "Слушать музыку",
        ):
            if value.encode("utf-8") not in binary:
                raise SystemExit(f"missing localized string in binary: {value}")

        for name, size in (("AppIcon60x60@2x.png", 120), ("AppIcon60x60@3x.png", 180)):
            image = Image.open(io.BytesIO(archive.read(APP + name)))
            if image.size != (size, size):
                raise SystemExit(f"{name}: unexpected size {image.size}")
            if image.mode != "RGB":
                raise SystemExit(f"{name}: unexpected mode {image.mode}")

    digest = hashlib.sha256(ipa.read_bytes()).hexdigest()
    print(f"IPA OK: {ipa}")
    print(f"Build: {info.get('CFBundleVersion')}")
    print(f"Version: {info.get('CFBundleShortVersionString')}")
    print(f"Files: {len(names)}")
    print(f"Size: {ipa.stat().st_size}")
    print(f"SHA256: {digest.upper()}")


if __name__ == "__main__":
    main()
