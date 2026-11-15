'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { GroupMessageCell } = require('../lib/group-message-cell');

class Sink {
  constructor() {
    this.userEvents = [];
    this.groupSignals = [];
    this.userPushes = [];
    this.partitions = [];
  }

  async notifyUser(userId, event) {
    this.userEvents.push({ userId, event });
  }

  async publishGroupSignal(groupId, event) {
    this.groupSignals.push({ groupId, event });
  }

  async enqueueUser(userId, event) {
    this.userPushes.push({ userId, event });
  }

  async enqueuePartition(job) {
    this.partitions.push(job);
  }
}

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-group-cell-'));
let uid = 0;
let cellA = null;
let cellB = null;

function cellOptions(id, sink) {
  return {
    cellId: id,
    dataDir: path.join(root, id),
    realtime: sink,
    pushQueue: sink,
    presence: {
      async isOnline(userId) {
        return userId.endsWith('1') || userId.endsWith('2');
      }
    },
    largeGroupThreshold: 3,
    pushPartitionSize: 2,
    schedule: (work) => setImmediate(work),
    now: () => '2026-11-15T00:00:00.000Z',
    uid: (prefix) => id + '-' + prefix + '-' + (++uid)
  };
}

function message(id, text) {
  return {
    id,
    senderId: 'user-1',
    clientId: 'client-' + id,
    kind: 'text',
    content: text,
    createdAt: '2026-11-15T00:00:00.000Z'
  };
}

async function main() {
  try {
    const sinkA = new Sink();
    const sinkB = new Sink();
    cellA = new GroupMessageCell(cellOptions('cell-a', sinkA));
    cellB = new GroupMessageCell(cellOptions('cell-b', sinkB));

    cellA.join('group-a', 'user-1', 1);
    cellA.join('group-a', 'user-2', 1);
    cellA.join('group-a', 'user-3', 1);
    cellA.join('group-a', 'user-4', 1);
    cellA.join('group-a', 'user-5', 1);
    cellB.join('group-b', 'user-1', 1);
    cellB.join('group-b', 'user-2', 1);

    let result = await cellA.send('group-a', 'user-1', message('a-1', 'cell a'));
    assert.strictEqual(result.ok, true);
    await cellA.waitForFanout();
    assert.strictEqual(sinkA.groupSignals.length, 1);
    assert.strictEqual(sinkA.partitions.length, 3);
    assert.strictEqual(sinkB.groupSignals.length, 0);

    result = await cellB.send('group-b', 'user-1', message('b-1', 'cell b'));
    assert.strictEqual(result.ok, true);
    await cellB.waitForFanout();
    assert.strictEqual(sinkB.userEvents.length, 2);
    assert.strictEqual(sinkA.userEvents.length, 0);

    let page = await cellA.read({
      groupId: 'group-a',
      userId: 'user-2',
      afterSeq: 0,
      limit: 20
    });
    assert.deepStrictEqual(page.messages.map((row) => row.id), ['a-1']);
    page = await cellB.read({
      groupId: 'group-b',
      userId: 'user-2',
      afterSeq: 0,
      limit: 20
    });
    assert.deepStrictEqual(page.messages.map((row) => row.id), ['b-1']);

    cellA.close();
    cellA = new GroupMessageCell(cellOptions('cell-a', sinkA));
    result = await cellA.send('group-a', 'user-1', message('a-2', 'after restart'));
    assert.strictEqual(result.ok, true);
    assert.strictEqual(result.seq, 2);
    await cellA.waitForFanout();
    page = await cellA.read({
      groupId: 'group-a',
      userId: 'user-1',
      afterSeq: 0,
      limit: 20
    });
    assert.deepStrictEqual(page.messages.map((row) => row.seq), [1, 2]);

    console.log('group-message-cell: passed');
  } finally {
    if (cellA) cellA.close();
    if (cellB) cellB.close();
    fs.rmSync(root, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
