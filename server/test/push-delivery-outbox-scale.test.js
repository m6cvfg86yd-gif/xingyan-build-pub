'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { PushDeliveryOutbox } = require('../lib/push-delivery-outbox');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-push-outbox-scale-'));
const databaseFile = path.join(root, 'push.sqlite3');
const outboxA = new PushDeliveryOutbox({ databaseFile });
const outboxB = new PushDeliveryOutbox({ databaseFile });

try {
  const count = 20000;
  const enqueueRows = Array.from({ length: count }, (_, index) => ({
    dedupeKey: 'message:m' + index + ':user-' + (index % 5000) + ':token',
    userId: 'user-' + (index % 5000),
    deviceToken: 'device-token-' + (index % 7000),
    env: 'prod',
    kind: 'message',
    payload: { aps: { alert: { title: 'T', body: 'B' } }, sequence: index }
  }));
  const started = process.hrtime.bigint();
  outboxA.enqueueMany(enqueueRows);
  const enqueueMs = Number(process.hrtime.bigint() - started) / 1e6;
  assert.strictEqual(outboxA.snapshot().counts.pending, count);

  const claimed = new Set();
  let batches = 0;
  while (claimed.size < count) {
    const jobs = (batches % 2 ? outboxA : outboxB).claim(500, 30000);
    assert.ok(jobs.length > 0);
    jobs.forEach((job) => {
      assert.ok(!claimed.has(job.dedupeKey));
      claimed.add(job.dedupeKey);
    });
    batches += 1;
  }
  assert.strictEqual(claimed.size, count);
  assert.deepStrictEqual(outboxA.snapshot().counts, { sending: count });
  console.log('push-delivery-outbox-scale: passed '
    + JSON.stringify({
      count,
      enqueueMs: Math.round(enqueueMs),
      batches,
      rssMB: Math.round(process.memoryUsage().rss / 1048576)
    }));
} finally {
  outboxA.close();
  outboxB.close();
  fs.rmSync(root, { recursive: true, force: true });
}
