'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { PushDeliveryOutbox } = require('../lib/push-delivery-outbox');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-push-outbox-'));
let clock = 1000;
let outbox = new PushDeliveryOutbox({
  databaseFile: path.join(root, 'push.sqlite3'),
  maxAttempts: 2,
  now: () => new Date(clock).toISOString(),
  nowMs: () => clock
});

try {
  let result = outbox.enqueue({
    dedupeKey: 'message:m1:user-1:token-a',
    userId: 'user-1',
    deviceToken: 'token-a',
    env: 'prod',
    kind: 'message',
    payload: { aps: { alert: { title: 'A', body: 'B' } } }
  });
  assert.strictEqual(result.inserted, true);
  result = outbox.enqueue({
    dedupeKey: 'message:m1:user-1:token-a',
    userId: 'user-1',
    deviceToken: 'token-a',
    env: 'prod',
    kind: 'message',
    payload: { aps: { alert: { title: 'A', body: 'B' } } }
  });
  assert.strictEqual(result.duplicate, true);

  let jobs = outbox.claim(10, 5000);
  assert.strictEqual(jobs.length, 1);
  assert.strictEqual(jobs[0].payload.aps.alert.title, 'A');
  assert.strictEqual(outbox.claim(10, 5000).length, 0);

  clock += 6000;
  jobs = outbox.claim(10, 5000);
  assert.strictEqual(jobs.length, 1);
  outbox.complete(jobs[0].id);
  assert.deepStrictEqual(outbox.snapshot().counts, { sent: 1 });

  outbox.enqueue({
    dedupeKey: 'message:m2:user-1:token-a',
    userId: 'user-1',
    deviceToken: 'token-a',
    env: 'prod',
    kind: 'message',
    payload: { aps: { alert: { title: 'C', body: 'D' } } }
  });
  jobs = outbox.claim(10, 5000);
  outbox.retry(jobs[0].id, 'temporary', 1000);
  assert.strictEqual(outbox.snapshot().counts.pending, 1);
  clock += 2000;
  jobs = outbox.claim(10, 5000);
  outbox.retry(jobs[0].id, 'still failing', 1000);
  assert.strictEqual(outbox.snapshot().counts.failed, 1);
  outbox.close();

  outbox = new PushDeliveryOutbox({
    databaseFile: path.join(root, 'push.sqlite3'),
    now: () => new Date(clock).toISOString(),
    nowMs: () => clock
  });
  assert.strictEqual(outbox.snapshot().counts.sent, 1);
  assert.strictEqual(outbox.snapshot().counts.failed, 1);
  console.log('push-delivery-outbox: passed');
} finally {
  try { outbox.close(); } catch (_) { }
  fs.rmSync(root, { recursive: true, force: true });
}
