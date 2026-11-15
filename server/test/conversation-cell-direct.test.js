'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { GroupMessageCell } = require('../lib/group-message-cell');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-direct-cell-'));
const cell = new GroupMessageCell({
  cellId: 'direct-cell',
  dataDir: root,
  realtime: {
    async notifyUser() {},
    async publishGroupSignal() {}
  },
  pushQueue: {
    async enqueueUser() {},
    async enqueuePartition() {}
  },
  presence: null,
  schedule: (work) => setImmediate(work)
});

function message(seq) {
  return {
    id: 'direct-message-' + seq,
    seq,
    senderId: seq % 2 ? 'alice' : 'bob',
    clientId: 'direct-client-' + seq,
    kind: 'text',
    content: 'direct ' + seq,
    createdAt: '2026-11-15T00:00:00.000Z'
  };
}

async function main() {
  try {
    cell.join('direct-1', 'alice', 1);
    cell.join('direct-1', 'bob', 1);
    for (let seq = 1; seq <= 6; seq += 1) {
      const result = await cell.send('direct-1', message(seq).senderId, message(seq));
      assert.strictEqual(result.ok, true, JSON.stringify(result));
    }
    const alice = await cell.read({
      groupId: 'direct-1',
      userId: 'alice',
      afterSeq: 0,
      limit: 20
    });
    const bob = await cell.read({
      groupId: 'direct-1',
      userId: 'bob',
      afterSeq: 0,
      limit: 20
    });
    assert.strictEqual(alice.ok, true);
    assert.strictEqual(bob.ok, true);
    assert.deepStrictEqual(alice.messages.map((row) => row.seq), [1, 2, 3, 4, 5, 6]);
    assert.deepStrictEqual(bob.messages.map((row) => row.seq), [1, 2, 3, 4, 5, 6]);

    cell.leave('direct-1', 'bob', 7);
    const left = await cell.send('direct-1', 'bob', message(7));
    assert.strictEqual(left.ok, false);
    assert.strictEqual(left.denied, true);
    console.log('conversation-cell-direct: passed');
  } finally {
    cell.close();
    fs.rmSync(root, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
