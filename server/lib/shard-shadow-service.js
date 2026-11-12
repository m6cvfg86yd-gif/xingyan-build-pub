'use strict';

const fs = require('fs');
const crypto = require('crypto');
const os = require('os');
const path = require('path');
const { ShardCluster } = require('./shard-runtime');
const { ShardEventBus } = require('./shard-event-bus');
const { ShardMutationGateway } = require('./shard-gateway');
const { migrateLegacyState } = require('./shard-migrate');
const { LegacyShadowRecorder, compareLegacyState } = require('./shard-shadow');
const { ShadowAdapter } = require('./shard-shadow-adapter');

function acquireWriterLock(dataDir, now) {
  fs.mkdirSync(dataDir, { recursive: true });
  const file = path.join(dataDir, 'writer.lock');
  const token = crypto.randomBytes(16).toString('hex');
  const owner = {
    pid: process.pid,
    hostname: os.hostname(),
    token,
    startedAt: now ? now() : new Date().toISOString()
  };
  const tryAcquire = () => {
    const fd = fs.openSync(file, 'wx');
    try {
      fs.writeFileSync(fd, JSON.stringify(owner), 'utf8');
      fs.fsyncSync(fd);
    } finally {
      fs.closeSync(fd);
    }
  };
  try {
    tryAcquire();
  } catch (error) {
    if (!error || error.code !== 'EEXIST') throw error;
    let existing = null;
    try { existing = JSON.parse(fs.readFileSync(file, 'utf8')); } catch (_) { existing = null; }
    let stale = false;
    if (existing && existing.hostname === owner.hostname && existing.pid) {
      try {
        process.kill(Number(existing.pid), 0);
        stale = false;
      } catch (probeError) {
        stale = !!(probeError && probeError.code === 'ESRCH');
      }
    }
    if (!stale) throw new Error('shard shadow writer already active on '
      + String(existing && existing.hostname || 'unknown host'));
    fs.unlinkSync(file);
    tryAcquire();
  }
  let released = false;
  const release = () => {
    if (released) return;
    released = true;
    try {
      const current = JSON.parse(fs.readFileSync(file, 'utf8'));
      if (current && current.token === token) fs.unlinkSync(file);
    } catch (_) { /* process exit or a replaced lock */ }
  };
  process.once('exit', release);
  return { file, token, release };
}

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
  const writerLock = acquireWriterLock(dataDir, options.now);
  try {
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
    diffHistoryFile,
    close: writerLock.release,
    writerLockFile: writerLock.file
  };
  } catch (error) {
    writerLock.release();
    throw error;
  }
}

module.exports = { createShardShadowService };
