'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { PaymentAudit } = require('../payment-audit');

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-payment-audit-'));
let state = {};
let sequence = 0;
let alertCount = 0;
let includesDifference = true;

const ledger = {
  reconcile() {
    return {
      ok: !includesDifference,
      checkedAt: new Date().toISOString(),
      entries: 12,
      differences: includesDifference ? [{
        kind: 'wallet',
        userId: 'u1',
        username: 'user-1',
        balance: 99,
        ledger: 100,
        difference: -1
      }] : [],
      integrity: { ok: true, checked: 12, failures: [] },
      ledgerTotalCents: 0
    };
  }
};

const audit = new PaymentAudit({
  ledger,
  readState: (_name, fallback) => state && Object.keys(state).length ? state : fallback,
  writeState: (_name, next) => { state = JSON.parse(JSON.stringify(next)); },
  uid: (prefix) => prefix + '_' + (++sequence),
  now: () => new Date().toISOString(),
  onAlert: () => { alertCount += 1; }
});

let row = audit.run('scheduled', [{ id: 'u1' }], () => null);
assert.strictEqual(row.ok, false);
assert.strictEqual(row.differences, 1);
assert.strictEqual(row.newTickets, 1);
assert.strictEqual(audit.summary().openTickets.length, 1);
assert.strictEqual(alertCount, 1);

includesDifference = false;
row = audit.run('scheduled', [{ id: 'u1' }], () => null);
assert.strictEqual(row.ok, true);
assert.strictEqual(row.resolvedTickets, 1);
assert.strictEqual(audit.summary().openTickets.length, 0);

const restored = new PaymentAudit({
  ledger,
  readState: (_name, fallback) => state && Object.keys(state).length ? state : fallback,
  writeState: (_name, next) => { state = next; },
  uid: (prefix) => prefix + '_' + (++sequence),
  now: () => new Date().toISOString()
});
assert.strictEqual(restored.summary().runs.length, 2);
assert.strictEqual(restored.summary().lastRunAt, audit.summary().lastRunAt);

fs.rmSync(dir, { recursive: true, force: true });
console.log('payment-audit: passed');
