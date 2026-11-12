# Internal payment security core

The target is an internal Xingyan wallet with Apple Pay-class consistency,
security and interaction quality. This is not an Apple Pay or card-network
integration.

## Hard boundaries

- Real card numbers and CVV values must never enter the application server.
- Only an opaque Xingyan payment-token reference and the last four digits may be
  stored.
- The device creates and protects its own signing key. The server stores only
  the public key and verifies every authorization.
- The application key ring is an interface for an HSM/KMS-backed signer. The
  built-in HMAC implementation is for local tests and does not replace an HSM.
- AML is currently disabled by product decision and is not a dependency of the
  payment intent engine.

## Payment intent states

`created -> authorized -> capture_pending -> captured`

`authorized -> voided`

`captured -> partially_refunded -> refunded`

`captured/refunded -> disputed`

Every command has a stable command ID. The append-only intent journal is
HMAC-chained, rejects broken hashes, rejects duplicate commands and detects
sequence errors. Capture and refund call an idempotent ledger settlement before
the intent can enter its final state. A crash after ledger settlement is
recovered by retrying the same ledger reference.

## Device authorization

- An internal payment token is bound to one user and one device public key.
- The device signs the exact intent ID, amount, currency, merchant, device,
  nonce and expiry.
- The nonce is single-use and the authorization lifetime is at most five
  minutes.
- Raw PAN, CVV, expiry and cardholder data are outside the internal wallet
  protocol.

## Internal production gates

1. Device key enrollment, revocation and lost-device recovery.
2. HSM/KMS key management, rotation, dual control and disaster recovery.
3. Wallet and business-account reconciliation with no unclassified balances.
4. Refund, transfer recall, dispute and customer-support operations.
5. Payment-sheet password, face/device confirmation and timeout behavior.
6. Crash, duplicate request, network timeout and topology-switch drills.

Until all gates pass, the new payment engine remains a tested internal
foundation even if the local tests pass.
