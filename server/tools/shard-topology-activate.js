#!/usr/bin/env node
'use strict';

const path = require('path');
const { resolveTopology } = require('../lib/shard-topology');
const { activateTopology } = require('../lib/shard-activation');

function arg(name, fallback) {
  const index = process.argv.indexOf('--' + name);
  return index >= 0 ? process.argv[index + 1] : fallback;
}

function main() {
  const baseDir = arg('base');
  const topologyId = arg('topology');
  if (!baseDir || !topologyId) {
    throw new Error('usage: shard-topology-activate.js --base DIR --topology ID');
  }
  const registry = path.resolve(__dirname, '..', 'shard-topologies.json');
  const topology = resolveTopology(registry, topologyId);
  const active = activateTopology({
    baseDir,
    topologyId,
    shardCount: topology.shardCount
  });
  console.log(JSON.stringify(active, null, 2));
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
