'use strict';

const fs = require('fs');
const crypto = require('crypto');
const os = require('os');
const path = require('path');
const { ShardCluster } = require('./shard-runtime');
const { ShardEventBus } = require('./shard-event-bus');
const { ShardMutationGateway } = require('./shard-gateway');
const { ShardLeaseManager } = require('./shard-lease');
const { migrateLegacyState } = require('./shard-migrate');
const { LegacyShadowRecorder, compareLegacyState } = require('./shard-shadow');
const { ShadowAdapter } = require('./shard-shadow-adapter');
const { ShardSnapshotMirror, buildStoreSets, compareSnapshots } = require('./shard-snapshot');

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
  const shardCount = Math.floor(Number(options && options.shardCount));
  if (!Number.isInteger(shardCount) || shardCount <= 1) {
    throw new Error('explicit shardCount >= 2 is required');
  }
  const dataDir = path.join(options.dataDir, 'shard-shadow');
  const writerLock = acquireWriterLock(dataDir, options.now);
  let leaseManager = null;
  const acquiredShards = [];
  try {
  const topologyId = String(options.topologyId || 'shards-' + shardCount);
  const safeTopology = topologyId.replace(/[^A-Za-z0-9._-]/g, '_');
  const topologyDir = path.join(dataDir, 'topologies', safeTopology);
  const ownerId = String(options.ownerId || (os.hostname() + ':' + process.pid));
  leaseManager = new ShardLeaseManager({
    dataDir: topologyDir,
    ownerId,
    ttlMs: Math.max(3000, Number(options.leaseTtlMs) || 30000)
  });
  try {
    for (let shard = 0; shard < shardCount; shard += 1) {
      const lease = leaseManager.acquire(shard);
      acquiredShards.push(shard);
      if (!lease || lease.ownerId !== ownerId) throw new Error('shard lease acquisition failed');
    }
  } catch (error) {
    for (const shard of acquiredShards) {
      try { leaseManager.release(shard); } catch (_) { /* best effort */ }
    }
    writerLock.release();
    throw error;
  }
  const cluster = new ShardCluster({
    dataDir: topologyDir,
    shardCount,
    topologyId
  });
  const bus = new ShardEventBus({ dataDir, shardCount, topologyId });
  const gateway = new ShardMutationGateway({
    cluster,
    bus,
    leaseManager,
    uid: options.uid,
    now: options.now
  });
  const snapshotMirror = new ShardSnapshotMirror({ gateway });
  const snapshotStores = options.snapshotStores === true
    || !!(options.legacy && Array.isArray(options.legacy.users));
  const migrate = (legacy) => migrateLegacyState(Object.assign({
    cluster
  }, legacy || {}));
  const migration = migrate(options.legacy || {});
  const capture = (setNames, legacy, options) => {
    if (!snapshotStores || !Array.isArray(setNames) || !setNames.length) return {};
    const sets = buildStoreSets(legacy || {});
    const results = {};
    const captureOptions = Object.assign({ replace: true }, options || {});
    for (const setName of setNames) {
      if (sets[setName]) {
        results[setName] = snapshotMirror.captureSet(setName, sets[setName], captureOptions);
      }
    }
    return results;
  };
  if (snapshotStores) snapshotMirror.captureStore(options.legacy || {});
  const recorder = new LegacyShadowRecorder({ gateway });
  const adapter = new ShadowAdapter({ recorder });
  const reportFile = path.join(topologyDir, 'shadow-audit.json');
  const diffHistoryFile = path.join(topologyDir, 'shadow-diffs.jsonl');
  const leaseTimer = setInterval(() => {
    for (let shard = 0; shard < shardCount; shard += 1) {
      try { leaseManager.renew(shard); }
      catch (error) {
        console.log('[分片租约] shard ' + shard + ' 已丢失：'
          + String(error && error.message || error));
      }
    }
  }, Math.max(1000, Math.floor((Number(options.leaseTtlMs) || 30000) / 3)));
  leaseTimer.unref();
  let closed = false;
  const close = () => {
    if (closed) return;
    closed = true;
    clearInterval(leaseTimer);
    for (const shard of acquiredShards) {
      try { leaseManager.release(shard); } catch (_) { /* best effort */ }
    }
    writerLock.release();
  };
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
      const state = compareLegacyState(cluster, legacy);
      const snapshotDiffs = snapshotStores ? compareSnapshots(cluster, legacy || {}) : [];
      const diffs = state.diffs.concat(snapshotDiffs);
      return Object.assign({}, state, {
        ok: state.ok && snapshotDiffs.length === 0,
        diffs,
        snapshotsEnabled: snapshotStores
      });
    },
    reconcile(legacy) {
      const result = migrate(legacy || {});
      if (snapshotStores) snapshotMirror.captureStore(legacy || {});
      return result;
    },
    capture(setNames, legacy, options) {
      try {
        return capture(setNames, legacy || {}, options || {});
      } catch (error) {
        return { error: String(error && error.message || error) };
      }
    },
    audit(legacy) {
      const report = Object.assign({
        at: options.now ? options.now() : new Date().toISOString(),
        migration
      }, this.compare(legacy || {}));
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
    close,
    ownerId,
    topologyId,
    writerLockFile: writerLock.file
  };
  } catch (error) {
    if (leaseManager) {
      for (const shard of acquiredShards) {
        try { leaseManager.release(shard); } catch (_) { /* best effort */ }
      }
    }
    writerLock.release();
    throw error;
  }
}

module.exports = { createShardShadowService };
