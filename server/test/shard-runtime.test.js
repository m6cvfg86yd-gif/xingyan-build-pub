'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const {
  stableShard,
  ShardDirectory,
  VersionedEntityLog,
  ShardCluster
} = require('../lib/shard-runtime');
const { ShardEventBus } = require('../lib/shard-event-bus');
const { ShardDomain } = require('../lib/shard-domain');

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-shard-runtime-'));
const logFile = path.join(dir, 'events.jsonl');
const mapFile = path.join(dir, 'assignments.json');

try {
  for (const key of ['u1', 'u2', 'chat1', 'chat2']) {
    assert.strictEqual(stableShard(key, 6), stableShard(key, 6));
  }
  assert.ok(stableShard('u1', 6) >= 0 && stableShard('u1', 6) < 6);

  const readJson = (file, fallback) => {
    try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch (_) { return fallback; }
  };
  const writeJson = (file, value) => fs.writeFileSync(file, JSON.stringify(value), 'utf8');
  const directory = new ShardDirectory({ shardCount: 6, file: mapFile, readJson, writeJson });
  const firstUserShard = directory.userShard('u1');
  const firstChatShard = directory.chatShard('chat1');
  const reopenedDirectory = new ShardDirectory({ shardCount: 6, file: mapFile, readJson, writeJson });
  assert.strictEqual(reopenedDirectory.userShard('u1'), firstUserShard);
  assert.strictEqual(reopenedDirectory.chatShard('chat1'), firstChatShard);

  const log = new VersionedEntityLog({ file: logFile });
  const base = {
    entityType: 'friendship',
    entityId: 'u1|u2',
    writerShard: firstUserShard,
    payload: { status: 'accepted' }
  };
  let result = log.apply(Object.assign({}, base, { eventId: 'e1', version: 1 }));
  assert.strictEqual(result.status, 'applied');
  result = log.apply(Object.assign({}, base, { eventId: 'e2', version: 2, payload: { status: 'deleted' }, deleted: true }));
  assert.strictEqual(result.status, 'applied');
  result = log.apply(Object.assign({}, base, { eventId: 'e1', version: 1 }));
  assert.strictEqual(result.status, 'duplicate');
  result = log.apply(Object.assign({}, base, { eventId: 'e0', version: 1, payload: { status: 'stale' } }));
  assert.strictEqual(result.status, 'stale');
  result = log.apply(Object.assign({}, base, { eventId: 'e3', version: 2, payload: { status: 'conflict' } }));
  assert.strictEqual(result.status, 'conflict');
  result = log.apply(Object.assign({}, base, { eventId: 'e4', version: 3, payload: { status: 'must-not-resurrect' } }));
  assert.strictEqual(result.status, 'tombstoned');
  result = log.apply(Object.assign({}, base, {
    eventId: 'e5',
    version: 4,
    deleted: false,
    allowAfterTombstone: true,
    payload: { status: 're-added' }
  }));
  assert.strictEqual(result.status, 'applied');
  assert.strictEqual(log.get('friendship', 'u1|u2').payload.status, 're-added');

  result = log.apply(Object.assign({}, base, {
    eventId: 'wrong-shard',
    entityId: 'u3|u4',
    version: 1,
    writerShard: (firstUserShard + 1) % 6
  }), { expectedShard: firstUserShard });
  assert.strictEqual(result.status, 'wrong-shard');

  const reopened = new VersionedEntityLog({ file: logFile });
  assert.strictEqual(reopened.get('friendship', 'u1|u2').version, 4);
  assert.strictEqual(reopened.get('friendship', 'u1|u2').payload.status, 're-added');
  result = reopened.apply(Object.assign({}, base, { eventId: 'e1', version: 1 }));
  assert.strictEqual(result.status, 'duplicate');

  const clusterDir = path.join(dir, 'cluster');
  const cluster = new ShardCluster({
    dataDir: clusterDir,
    shardCount: 6,
    readJson,
    writeJson
  });
  const routed = new Map();
  for (let i = 0; i < 120; i += 1) {
    const userId = 'user-' + i;
    const chatId = 'chat-' + i;
    const userShard = cluster.ownerShard('user', userId);
    const chatShard = cluster.ownerShard('chat', chatId);
    assert.ok(userShard >= 0 && userShard < 6);
    assert.ok(chatShard >= 0 && chatShard < 6);
    routed.set(userId, userShard);
    cluster.apply('user', userId, {
      eventId: 'user-event-' + i,
      version: 1,
      payload: { active: true }
    });
    cluster.apply('chat', chatId, {
      eventId: 'chat-event-' + i,
      version: 1,
      payload: { active: true }
    });
  }
  const reopenedCluster = new ShardCluster({
    dataDir: clusterDir,
    shardCount: 6,
    readJson,
    writeJson
  });
  for (let i = 0; i < 120; i += 1) {
    const userId = 'user-' + i;
    const chatId = 'chat-' + i;
    assert.strictEqual(reopenedCluster.ownerShard('user', userId), routed.get(userId));
    assert.strictEqual(reopenedCluster.get('user', userId).version, 1);
    assert.strictEqual(reopenedCluster.get('chat', chatId).version, 1);
  }

  const bus = new ShardEventBus({ dataDir: clusterDir, shardCount: 6 });
  bus.publish({
    eventId: 'moment-event-1',
    entityType: 'moment',
    entityId: 'moment-1',
    version: 1,
    payload: { content: 'hello' }
  });
  let replay = bus.replayInto(reopenedCluster);
  assert.strictEqual(replay.replayed, 1);
  assert.strictEqual(reopenedCluster.get('moment', 'moment-1').payload.content, 'hello');
  replay = bus.replayInto(reopenedCluster);
  assert.strictEqual(replay.replayed, 0);

  let nextId = 0;
  const domain = new ShardDomain({
    cluster: reopenedCluster,
    bus,
    uid: (prefix) => prefix + '-domain-' + (++nextId),
    now: () => '2026-11-13T00:00:00.000Z'
  });
  domain.acceptFriend('alice', 'bob', 1);
  assert.strictEqual(domain.canMessage('alice', 'bob').allowed, true);
  domain.deleteFriend('alice', 'bob', 2);
  assert.strictEqual(domain.canMessage('alice', 'bob').allowed, false);
  assert.strictEqual(domain.canMessage('bob', 'alice').reason, 'needs-verification');
  domain.readdFriend('alice', 'bob', 3);
  assert.strictEqual(domain.canMessage('alice', 'bob').allowed, true);

  domain.hideChat('chat-alice-bob', 'alice', 1);
  assert.strictEqual(domain.chatVisible('chat-alice-bob', 'alice'), false);
  domain.showChatForMessage('chat-alice-bob', 'alice', 2);
  assert.strictEqual(domain.chatVisible('chat-alice-bob', 'alice'), true);

  domain.dismissGroup('group-1', 1);
  assert.strictEqual(domain.restoreGroup('group-1', 2).status, 'tombstoned');

  const claimEvent = 'transfer-claim-once';
  assert.strictEqual(domain.claimTransfer('transfer-1', 'bob', 1, claimEvent).status, 'applied');
  assert.strictEqual(domain.claimTransfer('transfer-1', 'bob', 2, claimEvent).status,
    'already-claimed');
  assert.strictEqual(domain.claimTransfer('transfer-1', 'bob', 2, claimEvent).status,
    'already-claimed');

  console.log('shard-runtime: passed');
} finally {
  fs.rmSync(dir, { recursive: true, force: true });
}
