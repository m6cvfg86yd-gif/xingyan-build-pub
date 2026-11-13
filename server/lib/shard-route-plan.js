'use strict';

const crypto = require('crypto');

const ALGORITHM = 'fnv1a32';

function stableRouteHash(value) {
  let hash = 2166136261;
  const text = String(value || '');
  for (let index = 0; index < text.length; index += 1) {
    hash ^= text.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

function routeKey(kind, id) {
  const prefix = kind === 'user' ? 'u' : kind === 'chat' ? 'c' : '';
  if (!prefix) throw new Error('unsupported route kind: ' + String(kind || ''));
  const value = String(id || '');
  if (!value) throw new Error(kind + ' route id is required');
  return prefix + ':' + value;
}

function routeShard(key, shardCount) {
  const count = Math.max(1, Math.floor(Number(shardCount) || 1));
  return stableRouteHash(key) % count;
}

function canonical(value) {
  if (value === null || typeof value !== 'object') {
    return JSON.stringify(value === undefined ? null : value);
  }
  if (Array.isArray(value)) {
    return '[' + value.map(canonical).join(',') + ']';
  }
  return '{' + Object.keys(value).sort().map((key) =>
    JSON.stringify(key) + ':' + canonical(value[key])
  ).join(',') + '}';
}

function planHash(plan) {
  return crypto.createHash('sha256').update(canonical({
    version: plan.version,
    algorithm: plan.algorithm,
    topologyId: plan.topologyId,
    shardCount: plan.shardCount,
    ports: plan.ports,
    assignments: plan.assignments
  })).digest('hex');
}

function addRoutes(assignments, counts, kind, rows, shardCount) {
  const seen = new Set();
  for (const row of rows || []) {
    const id = String(row && row.id || '');
    if (!id) throw new Error(kind + ' id is required');
    if (seen.has(id)) throw new Error('duplicate ' + kind + ' id: ' + id);
    seen.add(id);
    const key = routeKey(kind, id);
    const shard = routeShard(key, shardCount);
    assignments[key] = shard;
    counts[kind + 's'] += 1;
    counts.byShard[shard] += 1;
  }
  return seen.size;
}

function buildRoutePlan(options) {
  const opts = options || {};
  const shardCount = Math.floor(Number(opts.shardCount));
  if (!Number.isInteger(shardCount) || shardCount < 2) {
    throw new Error('shardCount must be an integer >= 2');
  }
  const topologyId = String(opts.topologyId || '').trim();
  if (!topologyId) throw new Error('topologyId is required');
  const ports = Array.isArray(opts.ports) ? opts.ports.map((port) => Number(port)) : [];
  if (ports.length !== shardCount || ports.some((port) => !Number.isInteger(port) || port <= 0)) {
    throw new Error('one valid port is required for every shard');
  }
  const assignments = {};
  const counts = {
    users: 0,
    chats: 0,
    total: 0,
    byShard: Array.from({ length: shardCount }, () => 0)
  };
  addRoutes(assignments, counts, 'user', opts.users, shardCount);
  addRoutes(assignments, counts, 'chat', opts.chats, shardCount);
  counts.total = counts.users + counts.chats;
  const plan = {
    version: 1,
    algorithm: ALGORITHM,
    topologyId,
    shardCount,
    ports,
    baselineDate: String(opts.baselineDate || ''),
    createdAt: String(opts.createdAt || new Date().toISOString()),
    counts,
    assignments
  };
  plan.hash = planHash(plan);
  return plan;
}

function verifyRoutePlan(plan, options) {
  const opts = options || {};
  const failures = [];
  const assignments = plan && plan.assignments;
  const shardCount = Math.floor(Number(plan && plan.shardCount));
  if (!plan || plan.version !== 1 || plan.algorithm !== ALGORITHM) {
    failures.push({ kind: 'plan-format', message: 'unsupported route plan format' });
  }
  if (!Number.isInteger(shardCount) || shardCount < 2) {
    failures.push({ kind: 'shard-count', message: 'invalid shard count' });
  }
  if (!assignments || typeof assignments !== 'object' || Array.isArray(assignments)) {
    failures.push({ kind: 'assignments', message: 'assignments must be an object' });
  }
  if (failures.length) return { ok: false, failures, counts: {} };

  const expectedHash = planHash(plan);
  if (expectedHash !== plan.hash) {
    failures.push({
      kind: 'plan-checksum',
      expected: expectedHash,
      actual: plan.hash || ''
    });
  }

  const byShard = Array.from({ length: shardCount }, () => 0);
  let users = 0;
  let chats = 0;
  for (const key of Object.keys(assignments).sort()) {
    if (!/^[uc]:/.test(key)) {
      failures.push({ kind: 'route-key', key });
      continue;
    }
    const shard = Number(assignments[key]);
    if (!Number.isInteger(shard) || shard < 0 || shard >= shardCount) {
      failures.push({ kind: 'route-shard', key, shard });
      continue;
    }
    const expected = routeShard(key, shardCount);
    if (shard !== expected) {
      failures.push({ kind: 'route-drift', key, expected, actual: shard });
    }
    byShard[shard] += 1;
    if (key.startsWith('u:')) users += 1;
    else chats += 1;
  }
  const totals = { users, chats, total: users + chats, byShard };
  if (opts.users) {
    for (const row of opts.users) {
      const key = routeKey('user', row && row.id);
      if (!Object.prototype.hasOwnProperty.call(assignments, key)) {
        failures.push({ kind: 'user-uncovered', key });
      }
    }
  }
  if (opts.chats) {
    for (const row of opts.chats) {
      const key = routeKey('chat', row && row.id);
      if (!Object.prototype.hasOwnProperty.call(assignments, key)) {
        failures.push({ kind: 'chat-uncovered', key });
      }
    }
  }
  return {
    ok: failures.length === 0,
    algorithm: ALGORITHM,
    topologyId: plan.topologyId,
    shardCount,
    hash: plan.hash,
    counts: totals,
    failures: failures.slice(0, 500)
  };
}

function resolveRoute(plan, kind, id) {
  const key = routeKey(kind, id);
  const shardCount = Math.max(1, Math.floor(Number(plan && plan.shardCount) || 1));
  const assigned = plan && plan.assignments && plan.assignments[key];
  return Number.isInteger(assigned) ? assigned : routeShard(key, shardCount);
}

module.exports = {
  ALGORITHM,
  stableRouteHash,
  routeKey,
  routeShard,
  buildRoutePlan,
  verifyRoutePlan,
  resolveRoute
};
