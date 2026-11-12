'use strict';

const fs = require('fs');
const path = require('path');
const { ShardCluster } = require('./shard-runtime');
const { hash } = require('./shard-snapshot');
const { entityManifest, assignmentManifest } = require('./shard-migrate-topology');

function activeFile(baseDir) {
  return path.join(baseDir, 'active-topology.json');
}

function readActiveTopology(baseDir) {
  try {
    return JSON.parse(fs.readFileSync(activeFile(baseDir), 'utf8'));
  } catch (_) {
    return null;
  }
}

function activateTopology(options) {
  const baseDir = path.resolve(String(options && options.baseDir || ''));
  const topologyId = String(options && options.topologyId || '');
  const shardCount = Number(options && options.shardCount);
  if (!baseDir || !topologyId || !Number.isInteger(shardCount)) {
    throw new Error('baseDir, topologyId and shardCount are required');
  }
  if (fs.existsSync(path.join(baseDir, 'writer.lock'))) {
    throw new Error('shadow writer is active; stop all writers before activation');
  }
  const targetDir = path.join(baseDir, 'topologies',
    topologyId.replace(/[^A-Za-z0-9._-]/g, '_'));
  const reportPath = path.join(targetDir, 'migration-report.json');
  let report;
  try {
    report = JSON.parse(fs.readFileSync(reportPath, 'utf8'));
  } catch (_) {
    throw new Error('verified migration report is required');
  }
  if (!report.ok || !report.checks || !Object.values(report.checks).every(Boolean)) {
    throw new Error('migration report is not clean');
  }
  if (report.target.id !== topologyId || Number(report.target.shardCount) !== shardCount) {
    throw new Error('migration report topology does not match activation target');
  }
  const cluster = new ShardCluster({
    dataDir: targetDir,
    shardCount,
    topologyId
  });
  const verification = cluster.verify();
  if (!verification.ok) throw new Error('target cluster integrity failed');
  const entities = entityManifest(cluster);
  const assignments = assignmentManifest(cluster.directory);
  if (entities.events !== report.target.events
      || entities.entities !== report.target.entities
      || entities.hash !== report.target.hash
      || assignments.count !== report.target.assignments.count
      || assignments.hash !== report.target.assignments.hash) {
    throw new Error('target data no longer matches the verified migration report');
  }
  const previous = readActiveTopology(baseDir);
  if (previous && previous.topologyId === topologyId
      && previous.migrationReportHash === hash(report)) {
    return Object.assign({ alreadyActive: true }, previous);
  }
  const active = {
    version: 1,
    generation: (Number(previous && previous.generation) || 0) + 1,
    topologyId,
    shardCount,
    previousTopologyId: String(previous && previous.topologyId || ''),
    migrationReportHash: hash(report),
    entityChecksum: entities.hash,
    assignmentChecksum: assignments.hash,
    activatedAt: new Date().toISOString()
  };
  const file = activeFile(baseDir);
  const temporary = file + '.' + process.pid + '.tmp';
  fs.writeFileSync(temporary, JSON.stringify(active, null, 2), 'utf8');
  fs.renameSync(temporary, file);
  return active;
}

module.exports = {
  activeFile,
  readActiveTopology,
  activateTopology
};
