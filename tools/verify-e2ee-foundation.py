#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROTOCOL = (ROOT / "Sources" / "E2EEProtocol.swift").read_text(encoding="utf-8")
KEYSTORE = (ROOT / "Sources" / "E2EEKeyStore.swift").read_text(encoding="utf-8")
KEYCHAIN = (ROOT / "Sources" / "Keychain.swift").read_text(encoding="utf-8")
SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")
STORE = (ROOT / "server" / "lib" / "e2ee-foundation.js").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("E2EE foundation verification failed: " + message)


require(
    "static let enabled = false" in PROTOCOL,
    "client E2EE gate must default to disabled",
)
require(
    "Curve25519.KeyAgreement" in PROTOCOL
    and "Curve25519.Signing" in PROTOCOL
    and "HKDF<SHA256>" in PROTOCOL
    and "ChaChaPoly.seal" in PROTOCOL
    and "ChaChaPoly.open" in PROTOCOL,
    "X3DH and authenticated encryption primitives are required",
)
require(
    "kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly" in KEYCHAIN
    and "getDeviceOnlyData" in KEYSTORE,
    "private keys must remain device-only in Keychain",
)
require(
    "process.env.E2EE_FOUNDATION_ENABLED === '1'" in SERVER,
    "server foundation must remain explicitly opt-in",
)
require(
    "privateKey" not in STORE.split("function publicDevice", 1)[1].split(
        "function registerDevice", 1
    )[0],
    "public device bundles must not expose private key material",
)

print("e2ee-foundation: passed")
