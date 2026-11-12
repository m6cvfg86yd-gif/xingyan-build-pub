'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { stableShard, ShardDirectory, VersionedEntityLog } = require('../lib/shard-runtime');

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

  console.log('shard-runtime: passed');
} finally {
  fs.rmSync(dir, { recursive: true, force: true });
}
