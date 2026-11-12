'use strict';

const path = require('path');
const { ShardCluster } = require('./shard-runtime');
const { ShardEventBus } = require('./shard-event-bus');
const { ShardMutationGateway } = require('./shard-gateway');
const { migrateLegacyState } = require('./shard-migrate');
const { LegacyShadowRecorder, compareLegacyState } = require('./shard-shadow');
const { ShadowAdapter } = require('./shard-shadow-adapter');

function createShardShadowService(options) {
  const enabled = String(options && options.enabled || '') === '1';
  if (!enabled) {
    return {
      enabled: false,
      observe() { return { status: 'disabled' }; },
      compare() { return { ok: true, diffs: [], disabled: true }; }
    };
  }
  const dataDir = path.join(options.dataDir, 'shard-shadow');
  const cluster = new ShardCluster({
    dataDir,
    shardCount: Number(options.shardCount) || 6
  });
  const bus = new ShardEventBus({ dataDir, shardCount: Number(options.shardCount) || 6 });
  const gateway = new ShardMutationGateway({
    cluster,
    bus,
    uid: options.uid,
    now: options.now
  });
  const migrate = (legacy) => migrateLegacyState(Object.assign({
    cluster
  }, legacy || {}));
  const migration = migrate(options.legacy || {});
  const recorder = new LegacyShadowRecorder({ gateway });
  const adapter = new ShadowAdapter({ recorder });
  return {
    enabled: true,
    observe(routeId, payload) {
      try {
        return adapter.handle(routeId, payload || {});
      } catch (error) {
        return { status: 'error', error: String(error && error.message || error) };
      }
    },
    compare(legacy) {
      return compareLegacyState(cluster, legacy);
    },
    reconcile(legacy) {
      return migrate(legacy || {});
    },
    cluster,
    migration
  };
}

module.exports = { createShardShadowService };
