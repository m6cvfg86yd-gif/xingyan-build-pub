'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { ShardCluster } = require('../lib/shard-runtime');
const { ShardMutationGateway } = require('../lib/shard-gateway');
const {
  buildStoreSets,
  compareSnapshots,
  ShardSnapshotMirror
} = require('../lib/shard-snapshot');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-shard-snapshot-'));

try {
  const store = {
    users: [{
      id: 'u1',
      username: 'alice',
      nickname: 'Alice',
      avatar: '/a.png',
      phone: '13800000000',
      passwordHash: 'must-not-be-projected'
    }, {
      id: 'u2',
      username: 'bob',
      nickname: 'Bob',
      avatar: '/b.png'
    }],
    friendships: [{
      id: 'f1',
      fromId: 'u1',
      toId: 'u2',
      status: 'accepted'
    }],
    chats: [{
      id: 'c1',
      type: 'direct',
      memberIds: ['u1', 'u2'],
      pinnedFor: ['u1'],
      hiddenFor: []
    }],
    reads: { u1: { c1: 2 } },
    cleared: { u2: { c1: 1 } },
    friendMeta: { u1: { u2: { remark: 'B' } } },
    moments: [{
      id: 'm1',
      authorId: 'u1',
      content: 'hello',
      likes: [{ userId: 'u2' }],
      comments: []
    }],
    momentNotices: [{
      id: 'n1',
      toUserId: 'u1',
      momentId: 'm1'
    }],
    momentNoticeSeen: { u1: '2026-11-13T00:00:00.000Z' },
    transfers: [{
      id: 'tr1',
      fromId: 'u1',
      toId: 'u2',
      amount: 1,
      status: 'received'
    }],
    redpackets: [{
      id: 'rp1',
      fromId: 'u1',
      claims: [],
      total: 2
    }],
    messages: {
      c1: [{
        id: 'msg1',
        chatId: 'c1',
        seq: 1,
        senderId: 'u1',
        kind: 'text',
        content: 'secret message',
        createdAt: '2026-11-13T00:00:00.000Z'
      }]
    }
  };
  const sets = buildStoreSets(store);
  assert.strictEqual(sets.users.length, 2);
  assert.strictEqual(sets.chats.length, 1);
  assert.strictEqual(sets.reads.length, 2);
  assert.strictEqual(sets.friendMeta.length, 1);
  assert.strictEqual(sets.momentNotices.length, 1);
  assert.strictEqual(sets.messageThreads.length, 1);
  assert.ok(!JSON.stringify(sets.users).includes('13800000000'));
  assert.ok(!JSON.stringify(sets.messageThreads).includes('secret message'));

  const cluster = new ShardCluster({
    dataDir: path.join(root, 'cluster'),
    shardCount: 6
  });
  let id = 0;
  const gateway = new ShardMutationGateway({
    cluster,
    uid: (prefix) => prefix + '-' + (++id),
    now: () => '2026-11-13T00:00:00.000Z'
  });
  const mirror = new ShardSnapshotMirror({ gateway });
  mirror.captureStore(store);
  assert.deepStrictEqual(compareSnapshots(cluster, store), []);
  assert.strictEqual(cluster.verify().ok, true);

  store.chats[0].name = 'Renamed';
  store.messages.c1.push({
    id: 'msg2',
    chatId: 'c1',
    seq: 2,
    senderId: 'u2',
    kind: 'text',
    content: 'second',
    createdAt: '2026-11-13T00:00:01.000Z'
  });
  mirror.captureSet('chats', buildStoreSets({ chats: store.chats }).chats, { replace: true });
  mirror.captureSet('messageThreads', buildStoreSets({
    messages: { c1: store.messages.c1 }
  }).messageThreads, { replace: false });
  assert.deepStrictEqual(compareSnapshots(cluster, store), []);

  store.chats[0].name = 'Diverged without mirror';
  const diffs = compareSnapshots(cluster, store);
  assert.ok(diffs.some((row) => row.kind === 'snapshot-entity' && row.set === 'chats'));
  assert.ok(diffs.some((row) => row.kind === 'snapshot-manifest' && row.set === 'chats'));

  store.friendships = [];
  assert.ok(compareSnapshots(cluster, store).some(
    (row) => row.kind === 'snapshot-manifest' && row.set === 'friendships'
  ));
  mirror.captureSet('friendships', buildStoreSets({
    friendships: store.friendships
  }).friendships, { replace: true });
  assert.ok(!compareSnapshots(cluster, store).some(
    (row) => row.kind === 'snapshot-manifest' && row.set === 'friendships'
  ));

  console.log('shard-snapshot: passed');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
