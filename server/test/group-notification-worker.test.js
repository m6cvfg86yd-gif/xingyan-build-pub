'use strict';

const assert = require('assert');
const { GroupNotificationWorker } = require('../lib/group-notification-worker');

const members = [
  { userId: 'user-0' },
  { userId: 'user-1' },
  { userId: 'user-2' },
  { userId: 'user-3' },
  { userId: 'user-4' }
];
const online = new Set(['user-1', 'user-3']);
const sent = [];
const worker = new GroupNotificationWorker({
  membership: {
    async activeMembers(groupId, seq, offset, limit) {
      assert.strictEqual(groupId, 'group-1');
      assert.strictEqual(seq, 20);
      return members.slice(offset, offset + limit);
    }
  },
  presence: {
    async isOnline(userId) { return online.has(userId); }
  },
  pushProvider: {
    async send(notification) {
      if (notification.userId === 'user-4') return { skipped: true };
      sent.push(notification);
      return { sent: true };
    }
  },
  batchSize: 2
});

async function main() {
  const results = await worker.processAll([
    { groupId: 'group-1', seq: 20, partition: 0, pageSize: 2, messageId: 'm20' },
    { groupId: 'group-1', seq: 20, partition: 1, pageSize: 2, messageId: 'm20' },
    { groupId: 'group-1', seq: 20, partition: 2, pageSize: 2, messageId: 'm20' }
  ]);
  assert.deepStrictEqual(results.map((row) => row.scanned), [2, 2, 1]);
  assert.deepStrictEqual(results.map((row) => row.skippedOnline), [1, 1, 0]);
  assert.deepStrictEqual(results.map((row) => row.sent), [1, 1, 0]);
  assert.deepStrictEqual(sent.map((row) => row.userId), ['user-0', 'user-2']);
  assert.deepStrictEqual(sent.map((row) => row.idempotencyKey), [
    'group-1:20:user-0',
    'group-1:20:user-2'
  ]);
  assert.strictEqual(results[2].skippedOfflineUnknown, 1);
  console.log('group-notification-worker: passed');
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
