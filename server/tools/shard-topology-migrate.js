#!/usr/bin/env node
'use strict';

const path = require('path');
const { resolveTopology } = require('../lib/shard-topology');
const { migrateTopology } = require('../lib/shard-migrate-topology');

function arg(name, fallback) {
  const index = process.argv.indexOf('--' + name);
  return index >= 0 ? process.argv[index + 1] : fallback;
}

function flag(name) {
  return process.argv.includes('--' + name);
}

function main() {
  const baseDir = arg('base');
  const sourceId = arg('source');
  const targetId = arg('target');
  if (!baseDir || !sourceId || !targetId) {
    throw new Error('usage: shard-topology-migrate.js --base DIR --source ID --target ID '
      + '[--replace] [--dry-run]');
  }
  const registry = path.resolve(__dirname, '..', 'shard-topologies.json');
  const source = resolveTopology(registry, sourceId);
  const target = resolveTopology(registry, targetId);
  const report = migrateTopology({
    baseDir,
    source,
    target,
    apply: !flag('dry-run'),
    replace: flag('replace')
  });
  console.log(JSON.stringify(report, null, 2));
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    console.error(error.stack || error);
    process.exitCode = 1;
  }
}

module.exports = { main };
