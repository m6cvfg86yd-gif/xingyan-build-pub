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
  () => ({ enabled: true, balance: 20 })
);

assert.strictEqual(reconciled.ok, true,
  'wallet and business balances should reconcile: ' + JSON.stringify(reconciled));
assert.strictEqual(reconciled.integrity.ok, true, 'ledger integrity should pass');
assert.strictEqual(reconciled.ledgerTotalCents, 0, 'double-entry ledger must balance to zero');
assert.strictEqual(ledger.accountBalance('user:u1'), 90, 'wallet balance should match postings');
assert.strictEqual(ledger.entriesForUser('u1', 10).length, 3, 'user statement should include own entries');

const journal = path.join(dir, 'money-journal.jsonl');
const rows = fs.readFileSync(journal, 'utf8').trim().split('\n').map(JSON.parse);
rows[0].reason = 'tampered';
fs.writeFileSync(journal, rows.map(JSON.stringify).join('\n') + '\n');

const tampered = ledger.verifyIntegrity();
assert.strictEqual(tampered.ok, false, 'HMAC chain must detect journal tampering');
assert.ok(tampered.failures.some((row) => row.code === 'bad-hmac'));

console.log('payment-ledger: passed');
