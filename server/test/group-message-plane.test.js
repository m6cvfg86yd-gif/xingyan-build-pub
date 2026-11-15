'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { MessageReliabilityStore } = require('../lib/message-reliability');
const { MessageWritePipeline } = require('../lib/message-write-pipeline');
const { GroupMessagePlane } = require('../lib/group-message-plane');

class MemoryThreadStore {
  constructor() {
    this.threads = new Map();
  }

  async append(chatId, message) {
    const rows = this.threads.get(chatId) || [];
    if (!rows.some((row) => row.id === message.id)) rows.push(message);
    this.threads.set(chatId, rows);
  }

  async hasMessage(chatId, messageId) {
    return (this.threads.get(chatId) || []).some((row) => row.id === messageId);
  }
}

class MemoryMembership {
  constructor() {
    this.groups = new Map();
  }

  set(groupId, userId, joinedSeq, leftSeq) {
    const rows = this.groups.get(groupId) || new Map();
    rows.set(userId, { groupId, userId, joinedSeq, leftSeq: leftSeq || 0 });
    this.groups.set(groupId, rows);
  }

  async get(groupId, userId) {
    return (this.groups.get(groupId) || new Map()).get(userId) || null;
  }

  getSync(groupId, userId) {
    return (this.groups.get(groupId) || new Map()).get(userId) || null;
  }

  active(groupId, seq) {
    return Array.from((this.groups.get(groupId) || new Map()).values())
      .filter((row) => row.joinedSeq <= seq && (!row.leftSeq || row.leftSeq > seq));
  }

  async countActive(groupId, seq) {
    return this.active(groupId, seq).length;
  }

  async activeMembers(groupId, seq, offset, limit) {
    return this.active(groupId, seq).slice(offset, offset + limit);
  }
}

class RealtimeSink {
  constructor() {
    this.userEvents = [];
    this.groupSignals = [];
  }

  async notifyUser(userId, event) {
    this.userEvents.push({ userId, event });
  }

  async publishGroupSignal(groupId, event) {
    this.groupSignals.push({ groupId, event });
  }
}

class PushQueue {
  constructor() {
    this.userJobs = [];
    this.partitionJobs = [];
  }

  async enqueueUser(userId, event) {
    this.userJobs.push({ userId, event });
  }

  async enqueuePartition(job) {
    this.partitionJobs.push(job);
  }
}

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-group-plane-'));
const databaseFile = path.join(root, 'message-reliability.sqlite3');
let uid = 0;
const reliability = new MessageReliabilityStore({
  databaseFile,
  now: () => '2026-11-15T00:00:00.000Z',
  uid: (prefix) => prefix + '-' + (++uid)
});
const writePipeline = new MessageWritePipeline({
  reliability,
  threadStore: new MemoryThreadStore()
});
const membership = new MemoryMembership();
const realtime = new RealtimeSink();
const pushes = new PushQueue();
const online = new Set();
const plane = new GroupMessagePlane({
  writePipeline,
  membership,
  realtime,
  pushQueue: pushes,
  presence: {
    async isOnline(userId) { return online.has(userId); }
  },
  largeGroupThreshold: 3,
  pushPartitionSize: 2,
  schedule: (work) => setImmediate(work)
});

function message(id, text) {
  return {
    id,
    senderId: 'member-0',
    clientId: 'client-' + id,
    kind: 'text',
    content: text,
    createdAt: '2026-11-15T00:00:00.000Z'
  };
}

async function main() {
  try {
    for (let index = 0; index < 3; index += 1) {
      membership.set('small-group', 'member-' + index, 1, 0);
    }
    online.add('member-0');
    online.add('member-1');
    let result = await plane.deliver(
      'small-group',
      'member-0',
      message('small-1', 'hello')
    );
    assert.strictEqual(result.ok, true);
    assert.strictEqual(result.fanout, 'scheduled');
    await plane.waitForIdle();
    assert.strictEqual(realtime.userEvents.length, 2);
    assert.deepStrictEqual(realtime.userEvents.map((row) => row.userId).sort(),
      ['member-0', 'member-1']);
    assert.deepStrictEqual(pushes.userJobs.map((row) => row.userId), ['member-2']);
    assert.strictEqual(realtime.groupSignals.length, 0);

    membership.set('large-group', 'member-0', 1, 0);
    membership.set('large-group', 'member-1', 1, 0);
    membership.set('large-group', 'member-2', 1, 0);
    membership.set('large-group', 'member-3', 1, 0);
    membership.set('large-group', 'member-4', 1, 0);
    result = await plane.deliver(
      'large-group',
      'member-0',
      message('large-1', 'large group')
    );
    assert.strictEqual(result.ok, true);
    await plane.waitForIdle();
    assert.strictEqual(realtime.groupSignals.length, 1);
    assert.strictEqual(realtime.userEvents.length, 2);
    assert.strictEqual(pushes.partitionJobs.length, 3);
    assert.deepStrictEqual(pushes.partitionJobs.map((row) => row.partition), [0, 1, 2]);

    membership.set('membership-group', 'old', 1, 0);
    membership.set('membership-group', 'joined-later', 6, 0);
    membership.set('membership-group', 'left', 1, 5);
    assert.strictEqual(plane.canRead('membership-group', 'old', 4), true);
    assert.strictEqual(plane.canRead('membership-group', 'joined-later', 4), false);
    assert.strictEqual(plane.canRead('membership-group', 'joined-later', 6), true);
    assert.strictEqual(plane.canRead('membership-group', 'left', 4), true);
    assert.strictEqual(plane.canRead('membership-group', 'left', 5), false);
    assert.strictEqual(plane.unreadCount(120, 80, 70), 40);
    assert.strictEqual(plane.unreadCount(120, 80, 90), 30);
    assert.strictEqual(plane.unreadCount(50, 60, 0), 0);

    const duplicate = await plane.deliver(
      'small-group',
      'member-0',
      Object.assign(message('small-1-retry', 'changed'), {
        clientId: 'client-small-1'
      })
    );
    assert.strictEqual(duplicate.duplicate, true);
    console.log('group-message-plane: passed');
  } finally {
    reliability.close();
    fs.rmSync(root, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
