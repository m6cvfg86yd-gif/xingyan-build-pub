'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { PaymentLedger } = require('../payment-ledger');

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-payment-ledger-'));
const secureState = {};
let sequence = 0;

const ledger = new PaymentLedger({
  dataDir: dir,
  openSealed: (_name, value) => value,
  sealValue: (_name, value) => value,
  readState: (name, fallback) => secureState[name] || fallback,
  writeState: (name, value) => { secureState[name] = JSON.parse(JSON.stringify(value)); },
  hmac: (payload) => require('crypto').createHash('sha256').update(payload).digest('hex'),
  uid: (prefix) => prefix + '_' + (++sequence),
  now: () => new Date().toISOString()
});

ledger.apply({
  userId: 'u1',
  before: 0,
  after: 100,
  counterAccount: 'system:external-settlement'
}, 100, '充值', 'bank');

ledger.apply({
  userId: 'u1',
  before: 100,
  after: 70,
  counterAccount: 'system:shop-clearing'
}, -30, '小店下单', 'sku');

ledger.apply({
  userId: 'biz:u1',
  before: 0,
  after: 20,
  counterAccount: 'system:paycode-clearing'
}, 20, '收款（经营账户）', 'paycode');

assert.strictEqual(
  ledger.accountBalance('user:biz:u1'),
  20,
  'business income must retain its positive asset balance'
);

ledger.record({
  userId: 'u1',
  before: 70,
  after: 90,
  reason: '经营账户提现到零钱',
  ref: 'biz'
}, [
  { account: 'user:u1', delta: 20 },
  { account: 'user:biz:u1', delta: -20 }
]);

const reconciled = ledger.reconcile(
  [{ id: 'u1', username: 'tester', balance: 90 }],
  () => ({ enabled: true, balance: 0 })
);

assert.strictEqual(reconciled.ok, true,
  'wallet and business balances should reconcile: ' + JSON.stringify(reconciled));
assert.strictEqual(reconciled.integrity.ok, true, 'ledger integrity should pass');
assert.strictEqual(reconciled.ledgerTotalCents, 0, 'double-entry ledger must balance to zero');
assert.strictEqual(ledger.accountBalance('user:u1'), 90, 'wallet balance should match postings');
assert.strictEqual(
  ledger.accountBalance('user:biz:u1'),
  0,
  'business balance should be zero after moving all funds to wallet'
);
assert.strictEqual(ledger.entriesForUser('u1', 10).length, 3, 'user statement should include own entries');
const u1Statement = ledger.entriesForUser('u1', 10);
assert.ok(u1Statement.some((row) => row.delta === 20),
  'statement amounts must remain in currency units, not cents');
assert.ok(u1Statement.some((row) => row.delta === -30),
  'outgoing statement amount must remain in currency units');

ledger.apply({
  userId: 'payer',
  before: 0,
  after: 50,
  counterAccount: 'system:external-settlement'
}, 50, '充值', 'bank-payer');

ledger.apply({
  userId: 'payer',
  before: 50,
  after: 40,
  counterAccount: 'system:pending-transfer'
}, -10, '转账', 'transfer-1');

assert.strictEqual(ledger.accountBalance('user:payer'), 40);
assert.strictEqual(ledger.accountBalance('system:pending-transfer'), 10,
  'pending transfer funds must stay in the clearing account');

ledger.apply({
  userId: 'payee',
  before: 0,
  after: 10,
  counterAccount: 'system:pending-transfer'
}, 10, '收转账', 'transfer-1');

assert.strictEqual(ledger.accountBalance('user:payee'), 10);
assert.strictEqual(ledger.accountBalance('system:pending-transfer'), 0,
  'claiming a transfer must clear the pending account');

ledger.apply({
  userId: 'payee',
  before: 10,
  after: 0,
  counterAccount: 'system:wallet-transfer-clearing'
}, -10, '收款方退还', 'transfer-1');

ledger.apply({
  userId: 'payer',
  before: 40,
  after: 50,
  counterAccount: 'system:wallet-transfer-clearing'
}, 10, '收到退还', 'transfer-1');

assert.strictEqual(ledger.accountBalance('user:payee'), 0);
assert.strictEqual(ledger.accountBalance('user:payer'), 50);
assert.strictEqual(ledger.accountBalance('system:wallet-transfer-clearing'), 0);

const rebuilt = new PaymentLedger({
  dataDir: dir,
  openSealed: (_name, value) => value,
  sealValue: (_name, value) => value,
  readState: (name, fallback) => secureState[name] || fallback,
  writeState: (name, value) => { secureState[name] = JSON.parse(JSON.stringify(value)); },
  hmac: (payload) => require('crypto').createHash('sha256').update(payload).digest('hex'),
  uid: (prefix) => prefix + '_rebuild_' + (++sequence),
  now: () => new Date().toISOString()
});
rebuilt.rebuild();
assert.strictEqual(rebuilt.accountBalance('user:payer'), 50,
  'journal rebuild must preserve cent-based account balances');
assert.ok(rebuilt.entriesForUser('payer', 10).some((row) => row.delta === 10),
  'journal rebuild must preserve statement currency amounts');

assert.throws(() => {
  ledger.record({
    userId: 'payer',
    reason: '不平衡测试',
    ref: 'invalid'
  }, [
    { account: 'user:payer', delta: 1 },
    { account: 'system:unclassified', delta: -0.99 }
  ]);
}, /借贷不平/);

const journal = path.join(dir, 'money-journal.jsonl');
const rows = fs.readFileSync(journal, 'utf8').trim().split('\n').map(JSON.parse);
rows[0].reason = 'tampered';
fs.writeFileSync(journal, rows.map(JSON.stringify).join('\n') + '\n');

const tampered = ledger.verifyIntegrity();
assert.strictEqual(tampered.ok, false, 'HMAC chain must detect journal tampering');
assert.ok(tampered.failures.some((row) => row.code === 'bad-hmac'));

console.log('payment-ledger: passed');
