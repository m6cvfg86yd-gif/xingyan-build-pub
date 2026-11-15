#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { GroupCellRegistry } = require('../lib/group-cell-registry');
const { parseCellEndpoints } = require('../lib/remote-group-cell-shadow');

function arg(name, fallback) {
  const index = process.argv.indexOf('--' + name);
  return index >= 0 ? process.argv[index + 1] : fallback;
}

async function main() {
  const endpoints = parseCellEndpoints(arg('cells', ''));
  const token = arg('internal-token', process.env.GROUP_CELL_INTERNAL_TOKEN || '');
  const output = arg('output', '');
  if (!output) throw new Error('--output is required');
  const registry = new GroupCellRegistry({
    cells: Object.keys(endpoints).map((cellId) => ({
      cellId,
      baseUrl: endpoints[cellId],
      internalToken: token
    })),
    timeoutMs: Number(arg('timeout-ms', '2500'))
  });
  const snapshot = await registry.checkAll();
  const target = path.resolve(output);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  const temporary = target + '.tmp';
  fs.writeFileSync(temporary, JSON.stringify(snapshot, null, 2), 'utf8');
  fs.renameSync(temporary, target);
  process.stdout.write(JSON.stringify({
    output: target,
    cells: snapshot.cells.map((cell) => ({
      cellId: cell.cellId,
      healthy: cell.healthy,
      latencyMs: cell.latencyMs,
      lastError: cell.lastError
    }))
  }) + '\n');
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
