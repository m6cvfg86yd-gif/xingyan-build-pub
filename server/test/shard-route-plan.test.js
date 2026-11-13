'use strict';

const assert = require('assert');
const {
  buildRoutePlan,
  routeKey,
  routeShard,
  verifyRoutePlan,
  resolveRoute
} = require('../lib/shard-route-plan');

const users = [{ id: 'u1' }, { id: 'u2' }, { id: 'u3' }];
const chats = [{ id: 'c1' }, { id: 'c2' }, { id: 'c3' }, { id: 'c4' }];
const plan = buildRoutePlan({
  users,
  chats,
  shardCount: 6,
  ports: [5299, 5399, 5499, 5599, 5699, 5799],
  topologyId: 'server-a-shards-6',
  baselineDate: '2026-11-12',
  createdAt: '2026-11-13T00:00:00.000Z'
});

assert.strictEqual(plan.counts.users, 3);
assert.strictEqual(plan.counts.chats, 4);
assert.strictEqual(plan.counts.total, 7);
assert.strictEqual(plan.counts.byShard.reduce((sum, value) => sum + value, 0), 7);
assert.strictEqual(Object.keys(plan.assignments).length, 7);

const verification = verifyRoutePlan(plan, { users, chats });
assert.strictEqual(verification.ok, true, JSON.stringify(verification.failures));
assert.strictEqual(verification.counts.users, 3);
assert.strictEqual(verification.counts.chats, 4);

for (const row of users) {
  const key = routeKey('user', row.id);
  assert.strictEqual(plan.assignments[key], routeShard(key, 6));
  assert.strictEqual(resolveRoute(plan, 'user', row.id), plan.assignments[key]);
}
for (const row of chats) {
  const key = routeKey('chat', row.id);
  assert.strictEqual(plan.assignments[key], routeShard(key, 6));
  assert.strictEqual(resolveRoute(plan, 'chat', row.id), plan.assignments[key]);
}

const drifted = JSON.parse(JSON.stringify(plan));
drifted.assignments['u:u1'] = (drifted.assignments['u:u1'] + 1) % 6;
drifted.hash = plan.hash;
const drift = verifyRoutePlan(drifted, { users, chats });
assert.strictEqual(drift.ok, false);
assert.ok(drift.failures.some((row) => row.kind === 'plan-checksum'));
assert.ok(drift.failures.some((row) => row.kind === 'route-drift'));

const uncovered = verifyRoutePlan(plan, {
  users,
  chats: chats.concat([{ id: 'c-new' }])
});
assert.strictEqual(uncovered.ok, false);
assert.ok(uncovered.failures.some((row) => row.kind === 'chat-uncovered'));
assert.strictEqual(
  resolveRoute(plan, 'chat', 'c-new'),
  routeShard(routeKey('chat', 'c-new'), 6)
);

assert.throws(() => buildRoutePlan({
  users: [{ id: 'same' }, { id: 'same' }],
  chats: [],
  shardCount: 6,
  ports: [5299, 5399, 5499, 5599, 5699, 5799],
  topologyId: 'server-a-shards-6'
}), /duplicate user id/);

console.log('shard-route-plan: passed');
