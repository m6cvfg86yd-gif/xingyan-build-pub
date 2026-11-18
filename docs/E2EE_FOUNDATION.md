# E2EE dormant foundation v1

Status: implementation foundation only. It is disabled by default and is not
connected to the normal chat composer, upload chain, shard routing, or user
interface.

## Implemented

- Per-device X25519 identity and agreement keys.
- Ed25519 device signing keys.
- Signed X25519 prekeys and one-time prekeys.
- Device-only Keychain storage using
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- Public prekey registration and one-time-prekey claiming.
- X3DH shared-secret derivation using HKDF-SHA256.
- ChaCha20-Poly1305 authenticated message envelopes.
- Opaque server-side envelope queue. The server validates and stores public
  prekeys and ciphertext only.
- A native Swift self-test covering successful session setup, matching chain
  keys, and ciphertext tamper rejection.

## Deliberately not enabled

- No normal message is sent through the E2EE envelope.
- No image, video, voice, or file content is encrypted by this foundation.
- No UI says a conversation is end-to-end encrypted.
- No prekey endpoint is exposed unless
  `E2EE_FOUNDATION_ENABLED=1` is explicitly set.
- The client gate `E2EEFoundationConfig.enabled` remains `false`.

## Required before activation

1. Add Double Ratchet message numbering, skipped-key handling, replay rejection,
   and session persistence.
2. Add device verification and safety-number/QR comparison.
3. Add linked-device approval, revocation, and prekey replenishment.
4. Move prekey lookup to the target user's authoritative owner shard. The
   dormant local store must not be enabled through the current caller-routed
   gateway as a production directory.
5. Add encrypted sender-key distribution for groups.
6. Add per-file content keys, authenticated encryption, and encrypted object
   upload/download.
7. Add encrypted local search and explicit user consent for server-side AI
   processing.
8. Add encrypted backup and recovery-key policy.
9. Run device-loss, reinstall, multi-device, offline delivery, replay, and
   rollback drills.

## API surface (disabled unless explicitly enabled)

- `GET /api/e2ee/status`
- `POST /api/e2ee/devices`
- `GET /api/e2ee/bundle?userId=...&deviceId=...`
- `POST /api/e2ee/prekeys/claim`
- `POST /api/e2ee/envelopes`
- `GET /api/e2ee/envelopes?deviceId=...&after=...`
- `POST /api/e2ee/envelopes/ack`

The server never accepts private key material. Private keys remain in the
client Keychain.
