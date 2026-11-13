'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const {
  reconcileLegacyLedger,
  openSecureValue
} = require('../lib/payment-opening-balance');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-payment-opening-'));
try {
  const secret = 'payment-opening-test-secret';
  fs.writeFileSync(path.join(root, 'secret.key'), secret);
  fs.writeFileSync(path.join(root, 'users.json'), JSON.stringify({
    users: [
      { id: 'u1', username: 'alice', balance: 100 },
      { id: 'u2', username: 'bob', balance: 25.5 },
      { id: 'u3', username: 'zero', balance: 0 }
    ]
  }));

  const dryRun = reconcileLegacyLedger({
    dataDir: root,
    secret,
    apply: false,
    at: '2026-11-13T00:00:00.000Z'
  });
  assert.strictEqual(dryRun.ok, true);
  assert.strictEqual(dryRun.differences, 2);
  assert.strictEqual(dryRun.walletDifferences, 2);
  assert.strictEqual(dryRun.businessDifferences, 0);

  const applied = reconcileLegacyLedger({
    dataDir: root,
    secret,
    apply: true,
    at: '2026-11-13T00:00:00.000Z',
    backupDir: path.join(root, 'backup')
  });
  assert.strictEqual(applied.ok, true, JSON.stringify(applied.after));
  assert.strictEqual(applied.recorded, 2);
  assert.strictEqual(applied.after.differences.length, 0);
  assert.strictEqual(applied.after.ledgerTotalCents, 0);
  assert.strictEqual(applied.after.integrity.ok, true);
  assert.ok(fs.existsSync(path.join(root, 'money-journal.jsonl')));
  assert.ok(fs.existsSync(path.join(root, 'payment-ledger-state.json')));
  assert.ok(fs.existsSync(path.join(root, 'money-state.json')));
  assert.ok(fs.existsSync(path.join(root, 'backup')));

  const moneyState = openSecureValue(
    secret,
    'money-state.json',
    JSON.parse(fs.readFileSync(path.join(root, 'money-state.json'), 'utf8'))
  );
  assert.strictEqual(moneyState.users.u1.balance, 100);
  assert.strictEqual(moneyState.users.u2.balance, 25.5);
  assert.strictEqual(moneyState.users.u3.balance, 0);

  const second = reconcileLegacyLedger({
    dataDir: root,
    secret,
    apply: true,
    at: '2026-11-13T01:00:00.000Z'
  });
  assert.strictEqual(second.ok, true);
  assert.strictEqual(second.differences, 0);
  assert.strictEqual(second.recorded, 0);

  console.log('payment-opening-balance: passed');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
