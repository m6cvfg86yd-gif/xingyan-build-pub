#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { GroupRouteStore } = require('../lib/group-route-store');
const { RemoteGroupMigrationWorker } = require('../lib/remote-group-migration-worker');
const { inspectPilotGroup } = require('../lib/group-cell-pilot-gate');

function arg(name, fallback) {
  const index = process.argv.indexOf('--' + name);
  return index >= 0 ? process.argv[index + 1] : fallback;
}

function writeJson(file, value) {
  const target = path.resolve(file);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  const temporary = target + '.tmp';
  fs.writeFileSync(temporary, JSON.stringify(value, null, 2), 'utf8');
  fs.renameSync(temporary, target);
  return target;
}

async function main() {
  const sourceUrl = arg('source-url', '');
  const targetUrl = arg('target-url', '');
  const groupId = arg('group', '');
  const output = arg('output', '');
  const internalToken = arg('internal-token', process.env.GROUP_CELL_INTERNAL_TOKEN || '');
  const apply = process.argv.includes('--apply');
  if (!sourceUrl || !targetUrl || !groupId || !output) {
    throw new Error('--source-url, --target-url, --group and --output are required');
  }
  const preflight = await inspectPilotGroup({
    sourceUrl,
    targetUrl,
    groupId,
    internalToken,
    pageSize: Number(arg('page-size', '500')),
    maxMessages: Number(arg('max-messages', '100000'))
  });
  if (!preflight.ok) {
    writeJson(output, { applied: false, preflight });
    process.exitCode = 2;
    return;
  }
  if (!apply) {
    writeJson(output, { applied: false, preflight });
    process.stdout.write(JSON.stringify({
      output: path.resolve(output),
      ok: true,
      applied: false,
      groupId,
      messages: preflight.source.messages.count,
      sourceHash: preflight.source.messages.hash
    }) + '\n');
    return;
  }

  const sourceCellId = arg('source-cell', '');
  const targetCellId = arg('target-cell', '');
  const epoch = Math.floor(Number(arg('epoch', '0')) || 0);
  const stateDir = arg('state-dir', '');
  const databaseFile = arg('route-db', '');
  const confirmation = arg('confirm', '');
  const expected = 'MIGRATE:' + groupId + ':' + targetCellId + ':' + epoch;
  if (!sourceCellId || !targetCellId || epoch <= 0 || !stateDir || !databaseFile) {
    throw new Error('apply requires source-cell, target-cell, epoch, state-dir and route-db');
  }
  if (confirmation !== expected) {
    throw new Error('apply requires --confirm ' + expected);
  }

  const routeStore = new GroupRouteStore({ databaseFile });
  try {
    const worker = new RemoteGroupMigrationWorker({
      routeStore,
      sourceUrl,
      targetUrl,
      internalToken,
      stateDir,
      pageSize: Number(arg('page-size', '200'))
    });
    const report = await worker.migrate({
      groupId,
      sourceCellId,
      targetCellId,
      epoch,
      finalize: true
    });
    writeJson(output, { applied: report.ok, preflight, migration: report });
    if (!report.ok) process.exitCode = 2;
  } finally {
    routeStore.close();
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
