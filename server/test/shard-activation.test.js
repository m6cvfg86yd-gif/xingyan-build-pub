'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { ShardCluster } = require('../lib/shard-runtime');
const { ShardMutationGateway } = require('../lib/shard-gateway');
const { migrateTopology } = require('../lib/shard-migrate-topology');
const {
  activeFile,
  readActiveTopology,
  activateTopology
} = require('../lib/shard-activation');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-topology-activation-'));

try {
  const baseDir = path.join(root, 'shard-shadow');
  const source = new ShardCluster({
    dataDir: path.join(baseDir, 'topologies', 'server-a-shards-6'),
    shardCount: 6,
    topologyId: 'server-a-shards-6'
  });
  let id = 0;
  const gateway = new ShardMutationGateway({
    cluster: source,
    uid: (prefix) => prefix + '-' + (++id),
    now: () => '2026-11-13T00:00:00.000Z'
  });
  for (let i = 0; i < 20; i += 1) {
    gateway.submit({
      entityType: 'profile',
      entityId: 'activation-user-' + i,
      operation: 'create',
      payload: { index: i },
      eventId: 'activation-event-' + i
    });
  }
  migrateTopology({
    baseDir,
    source: { id: 'server-a-shards-6', shardCount: 6 },
    target: { id: 'server-b-shards-7', shardCount: 7 },
    apply: true
  });
  const active = activateTopology({
    baseDir,
    topologyId: 'server-b-shards-7',
    shardCount: 7
  });
  assert.strictEqual(active.generation, 1);
  assert.strictEqual(active.topologyId, 'server-b-shards-7');
  assert.strictEqual(active.previousTopologyId, '');
  assert.ok(fs.existsSync(activeFile(baseDir)));
  assert.strictEqual(readActiveTopology(baseDir).entityChecksum, active.entityChecksum);
  const repeated = activateTopology({
    baseDir,
    topologyId: 'server-b-shards-7',
    shardCount: 7
  });
  assert.strictEqual(repeated.alreadyActive, true);
  assert.strictEqual(repeated.generation, 1);
  assert.throws(() => activateTopology({
    baseDir,
    topologyId: 'server-a-shards-6',
    shardCount: 6
  }), /migration report/);

  console.log('shard-activation: passed');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
