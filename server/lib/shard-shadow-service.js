'use strict';

const fs = require('fs');
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
  const reportFile = path.join(dataDir, 'shadow-audit.json');
  const diffHistoryFile = path.join(dataDir, 'shadow-diffs.jsonl');
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
    audit(legacy) {
      const report = Object.assign({
        at: options.now ? options.now() : new Date().toISOString(),
        migration
      }, compareLegacyState(cluster, legacy || {}));
      fs.mkdirSync(dataDir, { recursive: true });
      const temporary = reportFile + '.tmp';
      fs.writeFileSync(temporary, JSON.stringify(report, null, 2), 'utf8');
      fs.renameSync(temporary, reportFile);
      if (!report.ok) {
        fs.appendFileSync(diffHistoryFile, JSON.stringify({
          at: report.at,
          checked: report.checked,
          diffs: report.diffs.slice(0, 200),
          truncated: report.diffs.length > 200
        }) + '\n', 'utf8');
      }
      return report;
    },
    cluster,
    migration,
    reportFile,
    diffHistoryFile
  };
}

module.exports = { createShardShadowService };
