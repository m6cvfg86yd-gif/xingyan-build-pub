'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { canonical } = require('../lib/shard-snapshot');
const { PaymentKeyRing } = require('../lib/payment-keyring');
const { PaymentTokenVault } = require('../lib/payment-token-vault');
const { PaymentIntentEngine } = require('../lib/payment-intent-engine');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-payment-intent-'));

try {
  const now = '2026-11-13T01:00:00.000Z';
  const keyring = new PaymentKeyRing({
    activeKeyId: 'pay-key-1',
    keys: [{
      id: 'pay-key-1',
      secret: crypto.randomBytes(32),
      active: true
    }]
  });
  const device = crypto.generateKeyPairSync('ed25519');
  const publicKey = device.publicKey.export({ format: 'pem', type: 'spki' }).toString();
  const vault = new PaymentTokenVault({
    file: path.join(root, 'tokens.json'),
    now: () => now
  });
  vault.enroll({
    tokenId: 'xingyan-token-001',
    userId: 'user-1',
    deviceId: 'iphone-1',
    network: 'xingyan-internal',
    last4: '4242',
    publicKey
  });
  const engine = new PaymentIntentEngine({
    file: path.join(root, 'intents.jsonl'),
    keyring,
    tokens: vault,
    now: () => now
  });
  const intentId = 'intent-payment-001';
  engine.create({
    intentId,
    commandId: 'create-001',
    userId: 'user-1',
    merchantId: 'merchant-1',
    deviceId: 'iphone-1',
    amountCents: 1000,
    currency: 'CNY'
  });
  assert.strictEqual(engine.cloneIntent(intentId).status, 'created');

  const authorization = {
    intentId,
    userId: 'user-1',
    merchantId: 'merchant-1',
    deviceId: 'iphone-1',
    amountCents: 1000,
    currency: 'CNY',
    nonce: 'nonce-abcdefghijklmnop',
    expiresAt: '2026-11-13T01:04:00.000Z'
  };
  const signature = crypto.sign(null, Buffer.from(canonical(authorization)), device.privateKey)
    .toString('base64');
  let authorized = engine.authorize({
    intentId,
    commandId: 'authorize-001',
    tokenId: 'xingyan-token-001',
    nonce: authorization.nonce,
    expiresAt: authorization.expiresAt,
    signature
  });
  assert.strictEqual(authorized.status, 'authorized');
  assert.strictEqual(authorized.last4, '4242');

  assert.throws(() => engine.authorize({
    intentId,
    commandId: 'authorize-replay',
    tokenId: 'xingyan-token-001',
    nonce: authorization.nonce,
    expiresAt: authorization.expiresAt,
    signature
  }), /already used|not authorizable/);

  let settlements = 0;
  const settle = (request) => {
    settlements += 1;
    return { ok: true, reference: 'ledger:' + request.ledgerRef };
  };
  let captured = engine.capture({
    intentId,
    commandId: 'capture-001',
    settle
  });
  assert.strictEqual(captured.status, 'captured');
  assert.strictEqual(settlements, 1);
  captured = engine.capture({
    intentId,
    commandId: 'capture-001',
    settle
  });
  assert.strictEqual(captured.idempotent, true);
  assert.strictEqual(settlements, 1);

  let refunded = engine.refund({
    intentId,
    commandId: 'refund-001',
    amountCents: 300,
    settle
  });
  assert.strictEqual(refunded.status, 'partially_refunded');
  assert.strictEqual(refunded.refundedCents, 300);
  assert.throws(() => engine.refund({
    intentId,
    commandId: 'refund-too-much',
    amountCents: 800,
    settle
  }), /invalid refund amount/);
  refunded = engine.refund({
    intentId,
    commandId: 'refund-002',
    amountCents: 700,
    settle
  });
  assert.strictEqual(refunded.status, 'refunded');
  assert.strictEqual(refunded.refundedCents, 1000);
  assert.strictEqual(settlements, 3);

  engine.create({
    intentId: 'intent-payment-002',
    commandId: 'create-002',
    userId: 'user-1',
    merchantId: 'merchant-2',
    deviceId: 'iphone-1',
    amountCents: 500,
    currency: 'CNY'
  });
  const voidAuthorization = {
    intentId: 'intent-payment-002',
    userId: 'user-1',
    merchantId: 'merchant-2',
    deviceId: 'iphone-1',
    amountCents: 500,
    currency: 'CNY',
    nonce: 'nonce-void-abcdefghijkl',
    expiresAt: '2026-11-13T01:04:00.000Z'
  };
  const voidSignature = crypto.sign(
    null,
    Buffer.from(canonical(voidAuthorization)),
    device.privateKey
  ).toString('base64');
  engine.authorize({
    intentId: 'intent-payment-002',
    commandId: 'authorize-002',
    tokenId: 'xingyan-token-001',
    nonce: voidAuthorization.nonce,
    expiresAt: voidAuthorization.expiresAt,
    signature: voidSignature
  });
  assert.strictEqual(engine.void({
    intentId: 'intent-payment-002',
    commandId: 'void-001'
  }).status, 'voided');

  engine.create({
    intentId: 'intent-payment-003',
    commandId: 'create-003',
    userId: 'user-1',
    merchantId: 'merchant-3',
    deviceId: 'iphone-1',
    amountCents: 200,
    currency: 'CNY'
  });
  const retryAuthorization = {
    intentId: 'intent-payment-003',
    userId: 'user-1',
    merchantId: 'merchant-3',
    deviceId: 'iphone-1',
    amountCents: 200,
    currency: 'CNY',
    nonce: 'nonce-retry-abcdefghij',
    expiresAt: '2026-11-13T01:04:00.000Z'
  };
  const retrySignature = crypto.sign(
    null,
    Buffer.from(canonical(retryAuthorization)),
    device.privateKey
  ).toString('base64');
  engine.authorize({
    intentId: retryAuthorization.intentId,
    commandId: 'authorize-003',
    tokenId: 'xingyan-token-001',
    nonce: retryAuthorization.nonce,
    expiresAt: retryAuthorization.expiresAt,
    signature: retrySignature
  });
  assert.throws(() => engine.capture({
    intentId: 'intent-payment-003',
    commandId: 'capture-003',
    settle: () => { throw new Error('simulated crash'); }
  }), /ledger settlement failed/);
  assert.strictEqual(engine.cloneIntent('intent-payment-003').status, 'capture_pending');
  const retryCaptured = engine.capture({
    intentId: 'intent-payment-003',
    commandId: 'capture-003',
    settle: () => ({ ok: true, reference: 'ledger:retry-capture' })
  });
  assert.strictEqual(retryCaptured.status, 'captured');

  assert.throws(() => engine.create({
    intentId: 'bad-intent',
    commandId: 'bad-create',
    userId: 'user-1',
    merchantId: 'merchant-1',
    deviceId: 'iphone-1',
    amountCents: 1.5,
    currency: 'CNY'
  }), /positive integer/);

  keyring.rotate('pay-key-2', crypto.randomBytes(32));
  const reloaded = new PaymentIntentEngine({
    file: path.join(root, 'intents.jsonl'),
    keyring,
    tokens: vault,
    now: () => now
  });
  assert.strictEqual(reloaded.cloneIntent(intentId).status, 'refunded');
  assert.strictEqual(reloaded.entries, engine.entries);
  const journal = fs.readFileSync(path.join(root, 'intents.jsonl'), 'utf8');
  assert.strictEqual(journal.includes('4242424242424242'), false);

  const rows = journal.trim().split('\n');
  const tampered = JSON.parse(rows[0]);
  tampered.amountCents = 1;
  rows[0] = JSON.stringify(tampered);
  fs.writeFileSync(path.join(root, 'intents.jsonl'), rows.join('\n') + '\n');
  assert.throws(() => new PaymentIntentEngine({
    file: path.join(root, 'intents.jsonl'),
    keyring,
    tokens: vault,
    now: () => now
  }), /integrity failure/);

  console.log('payment-intent: passed');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
