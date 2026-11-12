'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const {
  stableShard,
  routingKey,
  ShardDirectory,
  VersionedEntityLog,
  ShardCluster
} = require('../lib/shard-runtime');
const { ShardEventBus } = require('../lib/shard-event-bus');
const { ShardDomain } = require('../lib/shard-domain');
const { migrateLegacyState } = require('../lib/shard-migrate');
const { ShardMutationGateway } = require('../lib/shard-gateway');
const { LegacyShadowRecorder, compareLegacyState } = require('../lib/shard-shadow');
const { ShadowAdapter } = require('../lib/shard-shadow-adapter');

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-shard-runtime-'));
const logFile = path.join(dir, 'events.jsonl');
const mapFile = path.join(dir, 'assignments.json');

try {
  for (const key of ['u1', 'u2', 'chat1', 'chat2']) {
    assert.strictEqual(stableShard(key, 6), stableShard(key, 6));
  }
  assert.ok(stableShard('u1', 6) >= 0 && stableShard('u1', 6) < 6);
  assert.strictEqual(routingKey('friend_visibility', 'actor|target'), 'actor');
  assert.strictEqual(routingKey('chat_visibility', 'chat|owner'), 'owner');
  assert.strictEqual(routingKey('chat_user_state', 'chat|owner'), 'owner');
  assert.strictEqual(routingKey('chat_membership', 'chat|member'), 'member');
  assert.strictEqual(routingKey('moment_comment', 'moment|comment'), 'moment');

  const topology7Dir = path.join(dir, 'topology-7');
  const topology7 = new ShardCluster({
    dataDir: topology7Dir,
    shardCount: 7,
    topologyId: 'server-b-shards-7'
  });
  const topology7Shard = topology7.ownerShard('user', 'topology-user');
  assert.ok(topology7Shard >= 0 && topology7Shard < 7);
  topology7.apply('user', 'topology-user', {
    eventId: 'topology-7-event',
    version: 1,
    payload: { active: true }
  });
  assert.strictEqual(topology7.verify().ok, true);
  assert.throws(() => new ShardCluster({
    dataDir: topology7Dir,
    shardCount: 6,
    topologyId: 'server-a-shards-6'
  }), /topology mismatch/);
  const expanded7Dir = path.join(dir, 'topology-7-expanded');
  const expanded7 = new ShardCluster({
    dataDir: expanded7Dir,
    shardCount: 7,
    topologyId: 'server-b-shards-7-expanded'
  });
  const sourceAssignments = topology7.directory.exportAssignments();
  const migratedAssignments = expanded7.migrateAssignmentsFrom(topology7);
  assert.strictEqual(migratedAssignments, Object.keys(sourceAssignments).length);
  for (const key of Object.keys(sourceAssignments)) {
    assert.strictEqual(expanded7.directory.assignments[key], sourceAssignments[key],
      'expansion must not move existing assignments: ' + key);
  }

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
  assert.strictEqual(cluster.ownerShard('transfer', 'payment-1'), 0);
  assert.strictEqual(cluster.ownerShard('transfer', 'payment-2'), 0);
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

  const crossShardDir = path.join(dir, 'cross-shard-verify');
  const crossShardCluster = new ShardCluster({
    dataDir: crossShardDir,
    shardCount: 6
  });
  const firstShard = crossShardCluster.ownerShard('profile', 'cross-a');
  let otherEntityId = '';
  for (let i = 0; i < 100; i += 1) {
    const candidate = 'cross-' + i;
    if (crossShardCluster.ownerShard('profile', candidate) !== firstShard) {
      otherEntityId = candidate;
      break;
    }
  }
  assert.ok(otherEntityId);
  const sharedEventId = 'duplicate-across-shards';
  crossShardCluster.apply('profile', 'cross-a', {
    eventId: sharedEventId,
    version: 1,
    payload: { value: 'a' }
  });
  crossShardCluster.apply('profile', otherEntityId, {
    eventId: sharedEventId,
    version: 1,
    payload: { value: 'b' }
  });
  const crossShardVerification = crossShardCluster.verify();
  assert.strictEqual(crossShardVerification.ok, false);
  assert.ok(crossShardVerification.crossShardFailures.some(
    (failure) => failure.code === 'cross-shard-duplicate-event'
  ));

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
  bus.publish({
    eventId: 'moment-event-2',
    entityType: 'moment',
    entityId: 'moment-2',
    version: 1,
    writerShard: 3,
    payload: { content: 'sharded bus' }
  });
  assert.notStrictEqual(bus.file(0), bus.file(3));
  assert.strictEqual(bus.read(0, 3).length, 1);
  replay = bus.replayInto(reopenedCluster);
  assert.strictEqual(replay.replayed, 1);
  assert.strictEqual(reopenedCluster.get('moment', 'moment-2').payload.content, 'sharded bus');
  const repairDir = path.join(dir, 'bus-repair');
  const repairCluster = new ShardCluster({
    dataDir: repairDir,
    shardCount: 6
  });
  repairCluster.apply('profile', 'cluster-only-profile', {
    eventId: 'cluster-only-event',
    version: 1,
    operation: 'create',
    payload: { direct: true }
  });
  const repairBus = new ShardEventBus({ dataDir: repairDir, shardCount: 6 });
  const repair = repairBus.syncFromCluster(repairCluster);
  assert.strictEqual(repair.repaired, 1);
  assert.strictEqual(repairBus.syncFromCluster(repairCluster).repaired, 0);
  const orphanBus = new ShardEventBus({
    dataDir: path.join(dir, 'orphan-bus'),
    shardCount: 6
  });
  orphanBus.publish({
    eventId: 'orphan-event',
    entityType: 'profile',
    entityId: 'orphan-user',
    version: 1,
    payload: {}
  });
  const orphanCluster = new ShardCluster({
    dataDir: path.join(dir, 'orphan-cluster'),
    shardCount: 6
  });
  assert.throws(() => orphanBus.syncFromCluster(orphanCluster),
    /missing from cluster facts/);

  const corruptBusDir = path.join(dir, 'corrupt-bus');
  const corruptBus = new ShardEventBus({ dataDir: corruptBusDir, shardCount: 6 });
  corruptBus.publish({
    eventId: 'bus-good-1',
    entityType: 'profile',
    entityId: 'corrupt-user',
    version: 1,
    payload: { active: true }
  });
  fs.appendFileSync(corruptBus.file(), '{broken-json}\n', 'utf8');
  assert.throws(() => corruptBus.read(0), /event bus corruption/);

  const duplicateBusDir = path.join(dir, 'duplicate-bus');
  const duplicateBus = new ShardEventBus({ dataDir: duplicateBusDir, shardCount: 6 });
  const duplicateEvent = {
    eventId: 'bus-duplicate-1',
    entityType: 'profile',
    entityId: 'duplicate-user',
    version: 1,
    payload: { active: true }
  };
  duplicateBus.publish(duplicateEvent);
  duplicateBus.publish(duplicateEvent);
  assert.throws(() => duplicateBus.read(0), /duplicate event/);

  const cursorBusDir = path.join(dir, 'cursor-bus');
  const cursorBus = new ShardEventBus({ dataDir: cursorBusDir, shardCount: 6 });
  cursorBus.publish({
    eventId: 'cursor-good-1',
    entityType: 'profile',
    entityId: 'cursor-user',
    version: 1,
    payload: { active: true }
  });
  fs.writeFileSync(
    path.join(cursorBusDir, 'topologies', 'shards-6', 'shard-event-cursor.json'),
    JSON.stringify({ cursor: 99 }),
    'utf8'
  );
  const cursorCluster = new ShardCluster({
    dataDir: path.join(cursorBusDir, 'cluster'),
    shardCount: 6
  });
  assert.throws(() => cursorBus.replayInto(cursorCluster), /cursor is beyond/);

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

  const migrationDir = path.join(dir, 'migration');
  const migrationCluster = new ShardCluster({
    dataDir: migrationDir,
    shardCount: 6,
    readJson,
    writeJson
  });
  const counts = migrateLegacyState({
    cluster: migrationCluster,
    friendships: [{ id: 'f1', fromId: 'm1', toId: 'm2', status: 'accepted' }],
    chats: [
      { id: 'c1', type: 'direct', memberIds: ['m1', 'm2'], hiddenFor: ['m1'] },
      { id: 'g1', type: 'group', memberIds: ['m1', 'm2'], ownerId: 'm1', dismissed: true }
    ],
    moments: [{
      id: 'mo1',
      authorId: 'm1',
      content: 'legacy',
      likes: [{ userId: 'm2', at: 'now' }],
      comments: [{
        id: 'cm1',
        userId: 'm2',
        content: 'legacy comment',
        likes: [{ userId: 'm1', at: 'now' }]
      }]
    }],
    transfers: [
      { id: 'tr1', toId: 'm2', status: 'received' },
      { id: 'tr2', toId: 'm2', status: 'pending' }
    ]
  });
  assert.strictEqual(counts.friendships, 1);
  assert.strictEqual(counts.chatVisibility, 1);
  assert.strictEqual(counts.groupsDissolved, 1);
  assert.strictEqual(counts.moments, 1);
  assert.strictEqual(counts.comments, 1);
  assert.strictEqual(counts.likes, 2);
  assert.strictEqual(counts.transfers, 2);
  assert.strictEqual(migrationCluster.get('friendship', 'm1|m2').payload.status, 'accepted');
  assert.strictEqual(migrationCluster.get('chat_visibility', 'c1|m1').deleted, true);
  assert.strictEqual(migrationCluster.get('chat', 'g1').deleted, true);
  assert.strictEqual(migrationCluster.get('moment_comment', 'mo1|cm1').payload.content, 'legacy comment');
  assert.strictEqual(migrationCluster.get('transfer', 'tr1').payload.state, 'claimed');

  let gatewayId = 0;
  const gateway = new ShardMutationGateway({
    cluster: reopenedCluster,
    bus,
    uid: (prefix) => prefix + '-gateway-' + (++gatewayId),
    now: () => '2026-11-13T00:00:00.000Z'
  });
  let write = gateway.submit({
    entityType: 'profile',
    entityId: 'alice',
    operation: 'update',
    payload: { nickname: 'Alice A' },
    eventId: 'profile-event-1'
  });
  assert.strictEqual(write.status, 'applied');
  assert.strictEqual(write.version, 1);
  write = gateway.submit({
    entityType: 'profile',
    entityId: 'alice',
    operation: 'update',
    payload: { nickname: 'Alice A' },
    eventId: 'profile-event-1'
  });
  assert.strictEqual(write.status, 'duplicate');
  write = gateway.submit({
    entityType: 'profile',
    entityId: 'alice',
    operation: 'update',
    payload: { nickname: 'Different payload' },
    eventId: 'profile-event-1'
  });
  assert.strictEqual(write.status, 'idempotency-conflict');
  write = gateway.submit({
    entityType: 'profile',
    entityId: 'alice',
    operation: 'update',
    payload: { nickname: 'Alice B' },
    eventId: 'profile-event-2',
    expectedVersion: 0
  });
  assert.strictEqual(write.status, 'version-conflict');
  write = gateway.submit({
    entityType: 'profile',
    entityId: 'alice',
    operation: 'update',
    payload: { nickname: 'Alice B' },
    eventId: 'profile-event-2',
    expectedVersion: 1
  });
  assert.strictEqual(write.status, 'applied');
  assert.strictEqual(write.version, 2);
  assert.strictEqual(reopenedCluster.verify().ok, true);

  const badLogDir = path.join(dir, 'bad-log');
  const badCluster = new ShardCluster({
    dataDir: badLogDir,
    shardCount: 6,
    readJson,
    writeJson
  });
  badCluster.apply('profile', 'bad-user', {
    eventId: 'bad-1',
    version: 1,
    operation: 'create',
    payload: { ok: true }
  });
  const badOwner = badCluster.ownerShard('profile', 'bad-user');
  const badLogFile = path.join(badLogDir, 'shard-' + badOwner + '-events.jsonl');
  fs.appendFileSync(badLogFile, JSON.stringify({
    eventId: 'bad-2',
    entityType: 'profile',
    entityId: 'bad-user',
    version: 1,
    operation: 'regression',
    payload: {}
  }) + '\n', 'utf8');
  const badResult = new VersionedEntityLog({ file: badLogFile, strict: false }).verify();
  assert.strictEqual(badResult.ok, false);
  assert.ok(badResult.failures.some((failure) => failure.code === 'duplicate-version'));

  const shadowDir = path.join(dir, 'shadow');
  const shadowCluster = new ShardCluster({
    dataDir: shadowDir,
    shardCount: 6,
    readJson,
    writeJson
  });
  let shadowId = 0;
  const shadowGateway = new ShardMutationGateway({
    cluster: shadowCluster,
    uid: (prefix) => prefix + '-shadow-' + (++shadowId),
    now: () => '2026-11-13T00:00:00.000Z'
  });
  const shadow = new LegacyShadowRecorder({ gateway: shadowGateway });
  const legacy = {
    friendships: [{ id: 'sf1', fromId: 's1', toId: 's2', status: 'accepted' }],
    chats: [{
      id: 'sc1',
      hiddenFor: ['s1'],
      dismissed: false
    }, {
      id: 'sg1',
      dismissed: true,
      hiddenFor: []
    }],
    moments: [{
      id: 'smo1',
      authorId: 's1',
      content: 'shadow',
      likes: [{ userId: 's2' }],
      comments: [{ id: 'scm1', userId: 's2', content: 'shadow comment' }]
    }],
    transfers: [{
      id: 'str1',
      status: 'received',
      fromId: 's1',
      toId: 's2',
      amount: 10
    }]
  };
  shadow.friendAccepted(legacy.friendships[0]);
  shadow.chatHidden('sc1', 's1', 'legacy-chat-hide');
  shadow.groupDismissed('sg1', 'legacy-group-dismiss');
  shadow.momentPublished(legacy.moments[0]);
  shadow.momentCommented('smo1', legacy.moments[0].comments[0]);
  shadow.momentLiked('smo1', 's2');
  shadow.transferClaimed(legacy.transfers[0]);
  assert.strictEqual(compareLegacyState(shadowCluster, legacy).ok, true);

  const coverageManifest = JSON.parse(fs.readFileSync(
    path.join(__dirname, '..', 'shard-coverage.json'),
    'utf8'
  ));
  const adapter = new ShadowAdapter({ recorder: shadow });
  for (const route of coverageManifest.routes) {
    const result = adapter.handle(route.id, {});
    assert.notStrictEqual(result && result.status, 'unmapped', 'unmapped route: ' + route.id);
  }

  console.log('shard-runtime: passed');
} finally {
  fs.rmSync(dir, { recursive: true, force: true });
}
