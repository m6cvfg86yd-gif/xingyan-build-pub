#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { GroupRouteStore } = require('../lib/group-route-store');
const {
  previewGroupCellRouteImport,
  applyGroupCellRouteImport
} = require('../lib/group-cell-route-import');

function arg(name, fallback) {
  const index = process.argv.indexOf('--' + name);
  return index >= 0 ? process.argv[index + 1] : fallback;
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(path.resolve(String(file || '')), 'utf8'));
}

function writeJson(file, value) {
  const target = path.resolve(file);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  const temporary = target + '.tmp';
  fs.writeFileSync(temporary, JSON.stringify(value, null, 2), 'utf8');
  fs.renameSync(temporary, target);
  return target;
}

function main() {
  const planFile = arg('plan', '');
  const databaseFile = arg('route-db', '');
  const output = arg('output', '');
  const apply = process.argv.includes('--apply');
  const confirmation = arg('confirm', '');
  if (!planFile || !databaseFile || !output) {
    throw new Error('--plan, --route-db and --output are required');
  }
  const plan = readJson(planFile);
  if (apply && confirmation !== 'IMPORT:' + String(plan.assignmentHash || '')) {
    throw new Error('apply requires --confirm IMPORT:<assignmentHash>');
  }

  const store = new GroupRouteStore({
    databaseFile,
    readOnly: !apply
  });
  try {
    const result = apply
      ? applyGroupCellRouteImport(plan, store)
      : previewGroupCellRouteImport(plan, store);
    const report = Object.assign({}, result, {
      applied: apply && result.ok,
      assignmentHash: String(plan.assignmentHash || '')
    });
    writeJson(output, report);
    process.stdout.write(JSON.stringify({
      output: path.resolve(output),
      applied: report.applied,
      ok: report.ok,
      inserted: report.inserted.length,
      unchanged: report.unchanged.length,
      conflicts: report.conflicts.length
    }) + '\n');
    if (!result.ok) process.exitCode = 2;
  } finally {
    store.close();
  }
}

try {
  main();
} catch (error) {
  console.error(error.stack || error);
  process.exitCode = 1;
}
