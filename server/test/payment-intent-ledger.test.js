'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { canonical } = require('../lib/shard-snapshot');
const { PaymentLedger } = require('../payment-ledger');
const { PaymentKeyRing } = require('../lib/payment-keyring');
const { PaymentTokenVault } = require('../lib/payment-token-vault');
const { PaymentIntentEngine } = require('../lib/payment-intent-engine');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-payment-intent-ledger-'));

try {
  const now = '2026-11-13T02:00:00.000Z';
  const secureState = {};
  let sequence = 0;
  const ledger = new PaymentLedger({
    dataDir: root,
    openSealed: (_name, value) => value,
    sealValue: (_name, value) => value,
    readState: (name, fallback) => secureState[name] || fallback,
    writeState: (name, value) => { secureState[name] = JSON.parse(JSON.stringify(value)); },
    hmac: (payload) => crypto.createHash('sha256').update(payload).digest('hex'),
    uid: (prefix) => prefix + '_' + (++sequence),
    now: () => now
  });
  ledger.record({
    userId: 'buyer',
    before: 0,
    after: 100,
    reason: '充值',
    ref: 'funding-1'
  }, [
    { account: 'user:buyer', delta: 100 },
    { account: 'system:external-settlement', delta: -100 }
  ]);
  assert.strictEqual(ledger.accountBalance('user:buyer'), 100);

  const keyring = new PaymentKeyRing({
    activeKeyId: 'key-1',
    keys: [{ id: 'key-1', secret: crypto.randomBytes(32), active: true }]
  });
  const device = crypto.generateKeyPairSync('ed25519');
  const publicKey = device.publicKey.export({ format: 'pem', type: 'spki' }).toString();
  const vault = new PaymentTokenVault({
    file: path.join(root, 'tokens.json'),
    now: () => now
  });
  vault.enroll({
    tokenId: 'network-token-ledger-1',
    userId: 'buyer',
    deviceId: 'phone-1',
    network: 'mastercard',
    last4: '4444',
    publicKey
  });
  const engine = new PaymentIntentEngine({
    file: path.join(root, 'intents.jsonl'),
    keyring,
    tokens: vault,
    now: () => now
  });
  engine.create({
    intentId: 'intent-ledger-1',
    commandId: 'create-ledger-1',
    userId: 'buyer',
    merchantId: 'merchant-1',
    deviceId: 'phone-1',
    amountCents: 2500,
    currency: 'CNY'
  });
  const authorization = {
    intentId: 'intent-ledger-1',
    userId: 'buyer',
    merchantId: 'merchant-1',
    deviceId: 'phone-1',
    amountCents: 2500,
    currency: 'CNY',
    nonce: 'nonce-ledger-abcdefghijkl',
    expiresAt: '2026-11-13T02:04:00.000Z'
  };
  const signature = crypto.sign(
    null,
    Buffer.from(canonical(authorization)),
    device.privateKey
  ).toString('base64');
  engine.authorize({
    intentId: authorization.intentId,
    commandId: 'authorize-ledger-1',
    tokenId: 'network-token-ledger-1',
    nonce: authorization.nonce,
    expiresAt: authorization.expiresAt,
    signature
  });

  let settleCalls = 0;
  const settle = (request) => {
    settleCalls += 1;
    const result = ledger.recordOnce({
      userId: request.userId,
      before: ledger.accountBalance('user:' + request.userId),
      after: ledger.accountBalance('user:' + request.userId) - request.amountCents / 100,
      reason: 'Apple Pay 风格支付',
      ref: request.ledgerRef
    }, [
      { account: 'user:' + request.userId, delta: -request.amountCents / 100 },
      { account: 'merchant:' + request.merchantId, delta: request.amountCents / 100 }
    ]);
    return { ok: true, reference: result.record.id };
  };
  const captured = engine.capture({
    intentId: 'intent-ledger-1',
    commandId: 'capture-ledger-1',
    settle
  });
  assert.strictEqual(captured.status, 'captured');
  assert.strictEqual(settleCalls, 1);
  const duplicate = engine.capture({
    intentId: 'intent-ledger-1',
    commandId: 'capture-ledger-1',
    settle
  });
  assert.strictEqual(duplicate.idempotent, true);
  assert.strictEqual(settleCalls, 1);
  assert.strictEqual(ledger.accountBalance('user:buyer'), 75);
  assert.strictEqual(ledger.accountBalance('merchant:merchant-1'), 25);

  const refund = engine.refund({
    intentId: 'intent-ledger-1',
    commandId: 'refund-ledger-1',
    amountCents: 1000,
    settle: (request) => {
      const result = ledger.recordOnce({
        userId: request.userId,
        before: ledger.accountBalance('user:' + request.userId),
        after: ledger.accountBalance('user:' + request.userId) + request.amountCents / 100,
        reason: 'Apple Pay 风格退款',
        ref: request.ledgerRef
      }, [
        { account: 'user:' + request.userId, delta: request.amountCents / 100 },
        { account: 'merchant:' + request.merchantId, delta: -request.amountCents / 100 }
      ]);
      return { ok: true, reference: result.record.id };
    }
  });
  assert.strictEqual(refund.status, 'partially_refunded');
  assert.strictEqual(ledger.accountBalance('user:buyer'), 85);
  assert.strictEqual(ledger.accountBalance('merchant:merchant-1'), 15);
  assert.strictEqual(ledger.reconcile(
    [{ id: 'buyer', balance: 85 }],
    () => ({ enabled: false, balance: 0 })
  ).ok, true);

  console.log('payment-intent-ledger: passed');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
