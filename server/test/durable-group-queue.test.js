'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { DurableGroupQueue } = require('../lib/durable-group-queue');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-durable-group-queue-'));
const databaseFile = path.join(root, 'queue.sqlite3');
let clock = 1000;
let queue = new DurableGroupQueue({
  databaseFile,
  now: () => clock,
  leaseMs: 1000
});

try {
  const first = queue.enqueuePartition({
    groupId: 'group-1',
    seq: 10,
    partition: 1,
    size: 20,
    pageSize: 10
  });
  assert.strictEqual(first.created, true);
  const duplicate = queue.enqueuePartition({
    groupId: 'group-1',
    seq: 10,
    partition: 1,
    size: 20,
    pageSize: 10
  });
  assert.strictEqual(duplicate.created, false);
  assert.strictEqual(duplicate.job.id, first.job.id);

  queue.enqueueUser('user-1', { type: 'group.updated', groupId: 'group-1', seq: 10 });
  queue.enqueueUser('user-1', { type: 'group.updated', groupId: 'group-1', seq: 10 });
  assert.strictEqual(queue.stats().pending, 2);

  const claimed = queue.claim('worker-a', 1);
  assert.strictEqual(claimed.length, 1);
  assert.strictEqual(claimed[0].attempts, 1);
  assert.strictEqual(queue.stats().inflight, 1);
  assert.strictEqual(queue.claim('worker-b', 10).length, 1);

  clock = 2501;
  assert.strictEqual(queue.recoverExpired(), 2);
  assert.strictEqual(queue.stats().pending, 2);
  const retried = queue.claim('worker-a', 10);
  assert.strictEqual(retried.length, 2);
  queue.retry(retried[0].id, 500, 'temporary');
  queue.acknowledge(retried[1].id);
  assert.strictEqual(queue.stats().done, 1);

  clock = 3200;
  const afterRetry = queue.claim('worker-c', 10);
  assert.strictEqual(afterRetry.length, 1);
  assert.strictEqual(afterRetry[0].lastError, 'temporary');
  queue.acknowledge(afterRetry[0].id);
  assert.strictEqual(queue.stats().done, 2);

  queue.close();
  queue = new DurableGroupQueue({
    databaseFile,
    now: () => clock,
    leaseMs: 1000
  });
  assert.strictEqual(queue.stats().done, 2);
  assert.strictEqual(queue.stats().total, 2);
  console.log('durable-group-queue: passed');
} finally {
  if (queue) queue.close();
  fs.rmSync(root, { recursive: true, force: true });
}
