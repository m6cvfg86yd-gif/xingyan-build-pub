'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { PushDeliveryOutbox } = require('../lib/push-delivery-outbox');
const { PushOutboxWorker } = require('../lib/push-outbox-worker');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-push-worker-'));
let clock = 1000;
const outbox = new PushDeliveryOutbox({
  databaseFile: path.join(root, 'push.sqlite3'),
  now: () => new Date(clock).toISOString(),
  nowMs: () => clock,
  maxAttempts: 3
});
const rows = Array.from({ length: 100 }, (_, index) => ({
  dedupeKey: 'message:m' + index,
  userId: 'user-' + index,
  deviceToken: index < 10 ? 'bad-' + index : 'good-' + index,
  env: 'prod',
  payload: { aps: { alert: { title: 'T', body: 'B' } } }
}));
outbox.enqueueMany(rows);
const badTokens = [];
let logs = 0;
let active = 0;
let peak = 0;
const worker = new PushOutboxWorker({
  outbox,
  batchSize: 100,
  async send(token) {
    active += 1;
    peak = Math.max(peak, active);
    await new Promise((resolve) => setTimeout(resolve, 1));
    active -= 1;
    if (token.startsWith('bad-')) {
      return { ok: false, status: 400, reason: 'BadDeviceToken' };
    }
    const index = Number(token.split('-')[1]);
    if (index >= 10 && index < 30) {
      return { ok: false, status: 503, reason: 'temporary' };
    }
    return { ok: true, status: 200, reason: '' };
  },
  onBadToken(userId, token) {
    badTokens.push({ userId, token });
  },
  logMany(values) {
    logs += values.length;
  }
});

async function main() {
  try {
    const result = await worker.runOnce();
    assert.strictEqual(result.claimed, 100);
    assert.strictEqual(result.completed, 80);
    assert.strictEqual(result.retried, 20);
    assert.strictEqual(result.badTokens, 10);
    assert.strictEqual(badTokens.length, 10);
    assert.strictEqual(logs, 100);
    assert.ok(peak >= 90);
    assert.deepStrictEqual(outbox.snapshot().counts, { sent: 80, pending: 20 });
    const idle = await worker.runOnce();
    assert.strictEqual(idle.claimed, 0);
    console.log('push-outbox-worker: passed ' + JSON.stringify({
      peak,
      result
    }));
  } finally {
    outbox.close();
    fs.rmSync(root, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
