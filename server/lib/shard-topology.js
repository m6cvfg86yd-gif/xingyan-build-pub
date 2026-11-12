'use strict';

const fs = require('fs');

function resolveTopology(file, topologyId) {
  const id = String(topologyId || '');
  if (!id) throw new Error('explicit shard topology id is required');
  const registry = JSON.parse(fs.readFileSync(file, 'utf8'));
  const topology = registry && registry.topologies && registry.topologies[id];
  if (!topology) throw new Error('unknown shard topology: ' + id);
  const shardCount = Number(topology.shardCount);
  const ports = Array.isArray(topology.ports) ? topology.ports.map(Number) : [];
  if (!Number.isInteger(shardCount) || shardCount < 2 || shardCount > 64) {
    throw new Error('invalid shard count for topology: ' + id);
  }
  if (ports.length !== shardCount || ports.some((port) =>
    !Number.isInteger(port) || port < 1 || port > 65535)) {
    throw new Error('invalid shard ports for topology: ' + id);
  }
  return {
    id,
    shardCount,
    ports
  };
}

module.exports = { resolveTopology };
