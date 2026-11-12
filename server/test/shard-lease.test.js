'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { ShardCluster } = require('../lib/shard-runtime');
const { ShardEventBus } = require('../lib/shard-event-bus');
const { ShardMutationGateway } = require('../lib/shard-gateway');
const { ShardLeaseManager } = require('../lib/shard-lease');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-shard-lease-'));

try {
  let clock = 1000;
  const now = () => clock;
  const dataDir = path.join(root, 'cluster');
  const cluster = new ShardCluster({
    dataDir,
    shardCount: 7,
    topologyId: 'server-b-shards-7'
  });
  const bus = new ShardEventBus({
    dataDir,
    shardCount: 7,
    topologyId: 'server-b-shards-7'
  });
  const leaseA = new ShardLeaseManager({
    dataDir,
    ownerId: 'node-a',
    ttlMs: 1000,
    now
  });
  const leaseB = new ShardLeaseManager({
    dataDir,
    ownerId: 'node-b',
    ttlMs: 1000,
    now
  });
  const first = leaseA.acquire(0);
  assert.strictEqual(first.epoch, 1);
  const gatewayA = new ShardMutationGateway({
    cluster,
    bus,
    leaseManager: leaseA,
    uid: (prefix) => prefix + '-a-' + clock,
    now: () => new Date(clock).toISOString()
  });
  let result = gatewayA.submit({
    entityType: 'transfer',
    entityId: 'lease-transfer-a',
    operation: 'claim',
    payload: { state: 'claimed' },
    eventId: 'lease-event-a'
  });
  assert.strictEqual(result.status, 'applied');
  assert.strictEqual(result.version, 1);

  clock = 2101;
  assert.strictEqual(leaseA.validate(0).reason, 'expired');
  const second = leaseB.acquire(0);
  assert.strictEqual(second.epoch, 2);
  assert.strictEqual(leaseA.validate(0).reason, 'not-owner');
  result = gatewayA.submit({
    entityType: 'transfer',
    entityId: 'lease-transfer-b',
    operation: 'claim',
    payload: { state: 'claimed' },
    eventId: 'lease-event-old-owner'
  });
  assert.strictEqual(result.status, 'fenced');

  const gatewayB = new ShardMutationGateway({
    cluster,
    bus,
    leaseManager: leaseB,
    uid: (prefix) => prefix + '-b-' + clock,
    now: () => new Date(clock).toISOString()
  });
  result = gatewayB.submit({
    entityType: 'transfer',
    entityId: 'lease-transfer-b',
    operation: 'claim',
    payload: { state: 'claimed' },
    eventId: 'lease-event-new-owner'
  });
  assert.strictEqual(result.status, 'applied');
  assert.strictEqual(cluster.get('transfer', 'lease-transfer-b').writerEpoch, 2);

  clock = 2500;
  assert.strictEqual(leaseB.renew(0).epoch, 2);
  assert.strictEqual(leaseB.validate(0).ok, true);
  leaseA.release(0);
  assert.strictEqual(leaseB.validate(0).ok, true, 'old owner must not release the new lease');
  assert.strictEqual(cluster.verify().ok, true);

  console.log('shard-lease: passed');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
