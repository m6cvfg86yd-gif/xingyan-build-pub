'use strict';

const crypto = require('crypto');
const { SqlitePaymentLedger } = require('../../lib/sqlite-payment-ledger');

const databaseFile = process.argv[2];
const keyBase64 = process.argv[3];
const worker = process.argv[4];
const amount = Number(process.argv[5]);

const ledger = new SqlitePaymentLedger({
  databaseFile,
  hmac: (payload) => crypto.createHmac('sha256', Buffer.from(keyBase64, 'base64'))
    .update(payload).digest('hex'),
  uid: (prefix) => prefix + '_' + worker + '_' + crypto.randomUUID(),
  now: () => new Date().toISOString()
});

try {
  const result = ledger.applyDelta({
    userId: 'concurrent-user',
    delta: -amount,
    reason: 'concurrency test ' + worker,
    ref: 'concurrent-debit-' + worker,
    counterAccount: 'system:concurrency-test',
    idempotent: true
  });
  process.stdout.write(JSON.stringify({ ok: true, balance: result.balance }));
} catch (error) {
  process.stderr.write(String(error && error.stack || error));
  process.exitCode = 1;
} finally {
  ledger.close();
}
