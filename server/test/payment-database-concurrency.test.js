'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');
const { SqlitePaymentLedger } = require('../lib/sqlite-payment-ledger');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-payment-concurrency-'));
const databaseFile = path.join(root, 'payments.sqlite3');
const key = crypto.randomBytes(32);
const keyBase64 = key.toString('base64');

function openLedger() {
  return new SqlitePaymentLedger({
    databaseFile,
    hmac: (payload) => crypto.createHmac('sha256', key).update(payload).digest('hex'),
    uid: (prefix) => prefix + '_' + crypto.randomUUID(),
    now: () => new Date().toISOString()
  });
}

function runWorker(index) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [
      path.join(__dirname, 'helpers', 'payment-debit-worker.js'),
      databaseFile,
      keyBase64,
      String(index),
      '10'
    ], {
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true
    });
    const stdout = [];
    const stderr = [];
    child.stdout.on('data', (chunk) => stdout.push(chunk));
    child.stderr.on('data', (chunk) => stderr.push(chunk));
    child.on('error', reject);
    child.on('exit', (code) => {
      if (code !== 0) {
        reject(new Error('worker ' + index + ' failed: ' + Buffer.concat(stderr).toString('utf8')));
      } else {
        resolve(Buffer.concat(stdout).toString('utf8'));
      }
    });
  });
}

async function main() {
  const setup = openLedger();
  setup.seedOpeningBalances(
    [{ id: 'concurrent-user', balance: 100 }],
    () => ({ enabled: false, balance: 0 })
  );
  setup.close();

  const results = await Promise.all(Array.from({ length: 10 }, (_, index) => runWorker(index)));
  assert.strictEqual(results.length, 10);

  const reopened = openLedger();
  assert.strictEqual(reopened.accountBalance('user:concurrent-user'), 0,
    'ten cross-process debits must each apply exactly once');
  assert.strictEqual(reopened.accountBalance('system:concurrency-test'), 100);
  assert.strictEqual(reopened.verifyIntegrity().ok, true);
  assert.strictEqual(reopened.reconcile(
    [{ id: 'concurrent-user', balance: 0 }],
    () => ({ enabled: false, balance: 0 })
  ).ok, true);
  reopened.close();
  console.log('payment-database-concurrency: passed');
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
}).finally(() => {
  if (process.platform !== 'win32') {
    fs.rmSync(root, { recursive: true, force: true });
  }
});
