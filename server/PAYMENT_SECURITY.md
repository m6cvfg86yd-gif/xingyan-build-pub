# Payment security core

This module follows Apple Pay-style separation of duties. It is not Apple
certification and it does not make the current wallet a card-network product.

## Hard boundaries

- Real card numbers and CVV values must never enter the application server.
- Only an opaque network-token reference and the last four digits may be stored.
- Apple merchant validation requires an Apple merchant identifier, registered
  domain, merchant certificate and private key.
- Authorization, capture, refund and void require a connected licensed payment
  service provider. Without one, the API must fail closed.
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

- A network token is bound to one user and one device public key.
- The device signs the exact intent ID, amount, currency, merchant, device,
  nonce and expiry.
- The nonce is single-use and the authorization lifetime is at most five
  minutes.
- Raw PAN, CVV, expiry and cardholder data are explicitly rejected by the Apple
  Pay token validator.

## Production gates

All of the following are still external requirements:

1. Apple Merchant ID, registered domain and merchant-validation certificate.
2. Licensed PSP or acquirer integration and network tokenization.
3. HSM/KMS key management, rotation, dual control and disaster recovery.
4. PCI DSS scope assessment and independent security review.
5. Settlement, refund, chargeback, dispute and reconciliation operations.
6. Real-device Apple Pay sandbox and production certification.

Until all gates pass, payment endpoints must remain disconnected from real
funds even if the local tests pass.
