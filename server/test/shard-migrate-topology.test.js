'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { ShardCluster } = require('../lib/shard-runtime');
const { ShardMutationGateway } = require('../lib/shard-gateway');
const { migrateTopology } = require('../lib/shard-migrate-topology');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-topology-migrate-'));

try {
  const baseDir = path.join(root, 'shard-shadow');
  const sourceDir = path.join(baseDir, 'topologies', 'server-a-shards-6');
  const source = new ShardCluster({
    dataDir: sourceDir,
    shardCount: 6,
    topologyId: 'server-a-shards-6'
  });
  let id = 0;
  const gateway = new ShardMutationGateway({
    cluster: source,
    uid: (prefix) => prefix + '-' + (++id),
    now: () => '2026-11-13T00:00:00.000Z'
  });
  for (let i = 0; i < 80; i += 1) {
    const result = gateway.submit({
      entityType: 'profile',
      entityId: 'migration-user-' + i,
      operation: 'create',
      payload: { name: 'User ' + i },
      eventId: 'migration-event-' + i
    });
    assert.strictEqual(result.status, 'applied');
  }
  gateway.submit({
    entityType: 'transfer',
    entityId: 'migration-transfer',
    operation: 'claim',
    payload: { amount: 1.25, state: 'claimed' },
    eventId: 'migration-transfer-event'
  });

  const report = migrateTopology({
    baseDir,
    source: { id: 'server-a-shards-6', shardCount: 6 },
    target: { id: 'server-b-shards-7', shardCount: 7 },
    apply: true
  });
  assert.strictEqual(report.ok, true);
  assert.strictEqual(report.copied, 81);
  assert.strictEqual(report.checks.entityChecksum, true);
  assert.strictEqual(report.checks.assignmentChecksum, true);

  const targetDir = path.join(baseDir, 'topologies', 'server-b-shards-7');
  const target = new ShardCluster({
    dataDir: targetDir,
    shardCount: 7,
    topologyId: 'server-b-shards-7'
  });
  assert.strictEqual(target.verify().ok, true);
  assert.strictEqual(target.get('profile', 'migration-user-0').payload.name, 'User 0');
  assert.strictEqual(target.get('transfer', 'migration-transfer').payload.amount, 1.25);
  assert.strictEqual(target.log(6).eventsById.size, 0);
  const reportFile = JSON.parse(fs.readFileSync(
    path.join(targetDir, 'migration-report.json'),
    'utf8'
  ));
  assert.strictEqual(reportFile.ok, true);

  assert.throws(() => migrateTopology({
    baseDir,
    source: { id: 'server-a-shards-6', shardCount: 6 },
    target: { id: 'server-b-shards-7', shardCount: 7 },
    apply: true
  }), /already exists/);

  console.log('shard-migrate-topology: passed');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
