'use strict';

const fs = require('fs');
const path = require('path');
const { ShardCluster } = require('./shard-runtime');
const { ShardEventBus } = require('./shard-event-bus');
const { hash } = require('./shard-snapshot');

function entityManifest(cluster) {
  const entities = [];
  let events = 0;
  for (let shard = 0; shard < cluster.shardCount; shard += 1) {
    const log = cluster.log(shard);
    events += log.eventsById.size;
    for (const entity of log.entities.values()) {
      entities.push({
        entityType: entity.entityType,
        entityId: entity.entityId,
        version: entity.version,
        deleted: entity.deleted === true,
        lastEventId: entity.lastEventId,
        payload: entity.payload
      });
    }
  }
  entities.sort((a, b) =>
    (a.entityType + ':' + a.entityId).localeCompare(b.entityType + ':' + b.entityId));
  return {
    events,
    entities: entities.length,
    hash: hash(entities)
  };
}

function assignmentManifest(directory) {
  const rows = Object.keys(directory.assignments).sort().map((key) => ({
    key,
    shard: directory.assignments[key]
  }));
  return {
    count: rows.length,
    hash: hash(rows)
  };
}

function acquireMigrationLock(baseDir) {
  fs.mkdirSync(baseDir, { recursive: true });
  const writerLock = path.join(baseDir, 'writer.lock');
  if (fs.existsSync(writerLock)) {
    throw new Error('shadow writer is active; stop it before topology migration');
  }
  const file = path.join(baseDir, 'migration.lock');
  let fd;
  try {
    fd = fs.openSync(file, 'wx');
  } catch (error) {
    if (error && error.code === 'EEXIST') throw new Error('another topology migration is active');
    throw error;
  }
  fs.writeFileSync(fd, JSON.stringify({
    pid: process.pid,
    startedAt: new Date().toISOString()
  }), 'utf8');
  fs.fsyncSync(fd);
  fs.closeSync(fd);
  return () => {
    try { fs.unlinkSync(file); } catch (_) { /* already released */ }
  };
}

function migrateTopology(options) {
  const opts = options || {};
  const baseDir = path.resolve(String(opts.baseDir || ''));
  const source = opts.source || {};
  const target = opts.target || {};
  const sourceId = String(source.id || '');
  const targetId = String(target.id || '');
  if (!baseDir) throw new Error('baseDir is required');
  if (!sourceId || !targetId) throw new Error('source and target topology are required');
  if (sourceId === targetId) throw new Error('source and target topology must differ');
  const sourceCount = Number(source.shardCount);
  const targetCount = Number(target.shardCount);
  if (!Number.isInteger(sourceCount) || !Number.isInteger(targetCount)) {
    throw new Error('source and target shardCount are required');
  }
  if (targetCount < sourceCount) {
    throw new Error('online topology migration only supports expansion');
  }

  const safe = (id) => String(id).replace(/[^A-Za-z0-9._-]/g, '_');
  const sourceDir = path.join(baseDir, 'topologies', safe(sourceId));
  const targetDir = path.join(baseDir, 'topologies', safe(targetId));
  if (!fs.existsSync(path.join(sourceDir, 'shard-assignments.json'))) {
    throw new Error('source topology directory is missing assignments');
  }
  const release = acquireMigrationLock(baseDir);
  const stamp = new Date().toISOString().replace(/[^0-9]/g, '');
  const stageDir = path.join(baseDir, 'topologies',
    '.migration-' + safe(targetId) + '-' + process.pid + '-' + stamp);
  try {
    const sourceCluster = new ShardCluster({
      dataDir: sourceDir,
      shardCount: sourceCount,
      topologyId: sourceId
    });
    if (!sourceCluster.verify().ok) throw new Error('source topology verification failed');

    const targetCluster = new ShardCluster({
      dataDir: stageDir,
      shardCount: targetCount,
      topologyId: targetId
    });
    targetCluster.migrateAssignmentsFrom(sourceCluster);
    const bus = new ShardEventBus({
      dataDir: stageDir,
      shardCount: targetCount,
      topologyId: targetId
    });

    let copied = 0;
    for (let shard = 0; shard < sourceCount; shard += 1) {
      const log = sourceCluster.log(shard);
      for (const event of log.eventsById.values()) {
        const result = targetCluster.apply(event.entityType, event.entityId, event);
        if (result.status !== 'applied') {
          throw new Error('event migration failed at ' + event.eventId + ': ' + result.status);
        }
        bus.publish(Object.assign({}, event, {
          writerShard: result.state.writerShard,
          topologyId: targetId
        }));
        copied += 1;
      }
    }

    const sourceEntities = entityManifest(sourceCluster);
    const targetEntities = entityManifest(targetCluster);
    const sourceAssignments = assignmentManifest(sourceCluster.directory);
    const targetAssignments = assignmentManifest(targetCluster.directory);
    const targetVerification = targetCluster.verify();
    const checks = {
      eventCount: sourceEntities.events === targetEntities.events,
      entityCount: sourceEntities.entities === targetEntities.entities,
      entityChecksum: sourceEntities.hash === targetEntities.hash,
      assignmentCount: sourceAssignments.count === targetAssignments.count,
      assignmentChecksum: sourceAssignments.hash === targetAssignments.hash,
      targetIntegrity: targetVerification.ok
    };
    const ok = Object.values(checks).every(Boolean);
    const report = {
      version: 1,
      ok,
      createdAt: new Date().toISOString(),
      source: Object.assign({ id: sourceId, shardCount: sourceCount }, sourceEntities,
        { assignments: sourceAssignments }),
      target: Object.assign({ id: targetId, shardCount: targetCount }, targetEntities,
        { assignments: targetAssignments }),
      copied,
      checks,
      targetFailures: targetVerification.crossShardFailures
    };
    fs.writeFileSync(path.join(stageDir, 'migration-report.json'),
      JSON.stringify(report, null, 2), 'utf8');
    if (!ok) throw new Error('topology migration verification failed');
    if (opts.apply === false) return Object.assign({ staged: stageDir }, report);

    let backupDir = '';
    if (fs.existsSync(targetDir)) {
      if (opts.replace !== true) {
        throw new Error('target topology already exists; use replace to keep a backup');
      }
      backupDir = targetDir + '.backup-' + stamp;
      fs.renameSync(targetDir, backupDir);
    }
    try {
      fs.renameSync(stageDir, targetDir);
    } catch (error) {
      if (backupDir && !fs.existsSync(targetDir)) fs.renameSync(backupDir, targetDir);
      throw error;
    }
    return Object.assign({
      targetDir,
      backupDir
    }, report);
  } finally {
    release();
  }
}

module.exports = {
  entityManifest,
  assignmentManifest,
  migrateTopology
};
