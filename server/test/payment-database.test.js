'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { canonical } = require('../lib/shard-snapshot');
const { PaymentKeyRing } = require('../lib/payment-keyring');
const { PaymentDatabase } = require('../lib/payment-database');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-payment-database-'));
let sequence = 0;
const intentKey = crypto.randomBytes(32);

function hmac(payload) {
  return crypto.createHmac('sha256', 'payment-database-test')
    .update(payload).digest('hex');
}

function makeDatabase() {
  return new PaymentDatabase({
    databaseFile: path.join(root, 'payments.sqlite3'),
    hmac,
    keyring: new PaymentKeyRing({
      activeKeyId: 'intent-test-key',
      keys: [{
        id: 'intent-test-key',
        secret: intentKey,
        active: true
      }]
    }),
    uid: (prefix) => prefix + '_' + (++sequence),
    now: () => new Date().toISOString()
  });
}

try {
  const database = makeDatabase();
  database.seedOpeningBalances(
    [{ id: 'payer', username: 'payer', balance: 100 }],
    () => ({ enabled: false, balance: 0 })
  );
  assert.strictEqual(database.accountBalance('user:payer'), 100);

  const device = crypto.generateKeyPairSync('ed25519');
  const publicKey = device.publicKey.export({ format: 'pem', type: 'spki' })
    .toString().trim();
  database.registerDevice({
    tokenId: 'payment-token-database-test',
    userId: 'payer',
    deviceId: 'iphone-database-test',
    publicKey,
    last4: '4242'
  });

  const intent = database.createIntent({
    intentId: 'intent-database-test',
    commandId: 'create:intent-database-test',
    userId: 'payer',
    merchantId: 'peer:payee',
    deviceId: 'iphone-database-test',
    amountCents: 1000,
    currency: 'CNY',
    metadata: { kind: 'transfer', chatId: 'chat-database-test', toUserId: 'payee' }
  });
  assert.strictEqual(intent.status, 'created');

  const challenge = database.createIntentChallenge({
    intentId: intent.id,
    userId: 'payer',
    tokenId: 'payment-token-database-test'
  });
  const signature = crypto.sign(
    null,
    Buffer.from(canonical(challenge.payload)),
    device.privateKey
  ).toString('base64');
  const authorized = database.authorizeIntent({
    intentId: intent.id,
    userId: 'payer',
    commandId: 'authorize:intent-database-test',
    tokenId: challenge.tokenId,
    signature
  });
  assert.strictEqual(authorized.status, 'authorized');

  const captured = database.captureTransfer({
    intentId: intent.id,
    transferId: 'transfer-database-test',
    chatId: 'chat-database-test',
    toId: 'payee',
    note: 'database test',
    method: 'balance'
  });
  assert.strictEqual(captured.intent.status, 'captured');
  assert.strictEqual(captured.transfer.status, 'pending');
  assert.strictEqual(database.accountBalance('user:payer'), 90);
  assert.strictEqual(database.accountBalance('system:pending-transfer'), 10);

  const duplicateCapture = database.captureTransfer({
    intentId: intent.id,
    chatId: 'chat-database-test',
    toId: 'payee'
  });
  assert.strictEqual(duplicateCapture.duplicate, true);
  assert.strictEqual(database.accountBalance('user:payer'), 90,
    'duplicate capture must not debit twice');

  const claimed = database.claimTransfer(captured.transfer.id, 'payee', false);
  assert.strictEqual(claimed.transfer.status, 'received');
  assert.strictEqual(database.accountBalance('user:payee'), 10);
  assert.strictEqual(database.accountBalance('system:pending-transfer'), 0);
  assert.strictEqual(database.claimTransfer(captured.transfer.id, 'payee', false).duplicate, true);
  assert.strictEqual(database.accountBalance('user:payee'), 10,
    'duplicate claim must not credit twice');

  const refunded = database.refundTransfer(captured.transfer.id, 'payee', false);
  assert.strictEqual(refunded.transfer.status, 'refunded');
  assert.strictEqual(database.accountBalance('user:payee'), 0);
  assert.strictEqual(database.accountBalance('user:payer'), 100);

  const deposit = database.createFundingOrder({
    id: 'deposit-database-test',
    userId: 'payer',
    kind: 'deposit',
    amountCents: 500,
    provider: 'licensed-mock',
    idempotencyKey: 'deposit-request-database-test'
  });
  assert.strictEqual(deposit.status, 'pending');
  assert.strictEqual(database.accountBalance('user:payer'), 100,
    'deposit must not credit before provider confirmation');
  database.recordProviderEvent({
    provider: 'licensed-mock',
    providerEventId: 'deposit-event-database-test',
    type: 'payment.succeeded',
    payload: { orderId: deposit.id, status: 'succeeded' }
  });
  const settledDeposit = database.settleFundingOrder({
    orderId: deposit.id,
    providerEventId: 'deposit-event-database-test',
    success: true,
    providerRef: 'provider-deposit-1'
  });
  assert.strictEqual(settledDeposit.order.status, 'succeeded');
  assert.strictEqual(database.accountBalance('user:payer'), 105);
  assert.strictEqual(database.settleFundingOrder({
    orderId: deposit.id,
    providerEventId: 'deposit-event-database-test',
    success: true
  }).duplicate, true);
  assert.strictEqual(database.accountBalance('user:payer'), 105,
    'duplicate provider event must not credit twice');

  const payout = database.createFundingOrder({
    id: 'payout-database-test',
    userId: 'payer',
    kind: 'payout',
    amountCents: 700,
    feeCents: 10,
    provider: 'licensed-mock',
    idempotencyKey: 'payout-request-database-test',
    bankRef: 'bank-card:4242'
  });
  assert.strictEqual(payout.status, 'pending');
  assert.strictEqual(database.accountBalance('user:payer'), 97.9);
  assert.strictEqual(database.accountBalance('system:payout-pending'), 7);
  database.recordProviderEvent({
    provider: 'licensed-mock',
    providerEventId: 'payout-event-database-test',
    type: 'payout.succeeded',
    payload: { orderId: payout.id, status: 'succeeded' }
  });
  database.settleFundingOrder({
    orderId: payout.id,
    providerEventId: 'payout-event-database-test',
    success: true,
    providerRef: 'provider-payout-1'
  });
  assert.strictEqual(database.accountBalance('user:payer'), 97.9);
  assert.strictEqual(database.accountBalance('system:payout-pending'), 0);
  assert.strictEqual(database.accountBalance('system:fee-revenue'), 0.1);

  const settlementDate = new Date().toISOString().slice(0, 10);
  const settlement = database.reconcileProviderSettlement(
    'licensed-mock',
    settlementDate,
    [
      {
        providerRef: 'provider-deposit-1',
        orderId: deposit.id,
        kind: 'deposit',
        amountCents: 500,
        feeCents: 0,
        currency: 'CNY',
        status: 'succeeded'
      },
      {
        providerRef: 'provider-payout-1',
        orderId: payout.id,
        kind: 'payout',
        amountCents: 700,
        feeCents: 10,
        currency: 'CNY',
        status: 'succeeded'
      }
    ]
  );
  assert.strictEqual(settlement.ok, true, JSON.stringify(settlement));

  const mismatch = database.reconcileProviderSettlement(
    'licensed-mock',
    settlementDate,
    [{
      providerRef: 'provider-deposit-1',
      orderId: deposit.id,
      kind: 'deposit',
      amountCents: 501,
      feeCents: 0,
      currency: 'CNY',
      status: 'succeeded'
    }]
  );
  assert.strictEqual(mismatch.ok, false);
  assert.ok(mismatch.mismatches.some((row) => row.code === 'amount-or-fee-mismatch'));
  assert.ok(mismatch.mismatches.some((row) => row.code === 'missing-provider-line'));

  const pendingOutbox = database.outbox(100);
  assert.ok(pendingOutbox.length >= 4);
  database.completeOutbox(captured.outboxId, 'message-database-test');
  assert.strictEqual(database.transfer(captured.transfer.id).messageId, 'message-database-test');

  const reconciled = database.reconcile(
    [{ id: 'payer', username: 'payer', balance: 97.9 }],
    () => ({ enabled: false, balance: 0 })
  );
  assert.strictEqual(reconciled.ok, true, JSON.stringify(reconciled));
  assert.strictEqual(reconciled.integrity.ok, true);
  assert.strictEqual(reconciled.ledgerTotalCents, 0);
  assert.strictEqual(database.verifyIntentIntegrity().ok, true);
  assert.strictEqual(database.readiness().ok, true);
  const backup = database.backupTo(path.join(root, 'backup.sqlite3'));
  assert.ok(backup.size > 0);
  assert.strictEqual(fs.existsSync(backup.file), true);

  database.close();

  const reopened = makeDatabase();
  assert.strictEqual(reopened.accountBalance('user:payer'), 97.9);
  assert.strictEqual(reopened.intent(intent.id).status, 'captured');
  assert.strictEqual(reopened.transfer(captured.transfer.id).status, 'refunded');
  assert.strictEqual(reopened.verifyIntegrity().ok, true);
  assert.strictEqual(reopened.verifyIntentIntegrity().ok, true);
  reopened.close();

  console.log('payment-database: passed');
} finally {
  if (process.platform !== 'win32') {
    fs.rmSync(root, { recursive: true, force: true });
  }
}
