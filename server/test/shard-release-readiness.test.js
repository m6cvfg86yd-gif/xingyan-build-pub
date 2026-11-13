'use strict';

const assert = require('assert');
const { buildReleaseReadiness } = require('../lib/shard-release-readiness');
const { buildRoutePlan } = require('../lib/shard-route-plan');

const users = [{ id: 'u1' }, { id: 'u2' }];
const chats = [{ id: 'c1' }, { id: 'c2' }];
const routePlan = buildRoutePlan({
  users,
  chats,
  shardCount: 6,
  ports: [5299, 5399, 5499, 5599, 5699, 5799],
  topologyId: 'server-a-shards-6',
  baselineDate: '2026-11-12',
  createdAt: '2026-11-13T00:00:00.000Z'
});
const counts = {
  users: 2,
  friendships: 1,
  chats: 2,
  moments: 1,
  momentNotices: 1,
  transfers: 1,
  redpackets: 1,
  friendRemovals: 0,
  friendMeta: 1,
  reads: 1,
  cleared: 0,
  delivered: 1,
  messages: 3,
  uploads: 1,
  backgrounds: 1
};
const manifests = {
  users: { count: 2, hash: 'users' },
  friendships: { count: 1, hash: 'friendships' },
  chats: { count: 2, hash: 'chats' },
  messages: { count: 3, hash: 'before-repair' },
  uploads: { count: 1, hash: 'uploads' }
};
const baseline = {
  sourceId: 'baseline',
  baselineDate: '2026-11-12',
  counts,
  uploadBytes: 100,
  manifests,
  errorCount: 3,
  issueCounts: {
    'message-seq-duplicate': 2,
    'upload-missing': 1,
    'orphan-message-file': 1
  }
};
const candidate = {
  sourceId: 'candidate',
  baselineDate: '2026-11-12',
  counts,
  uploadBytes: 100,
  manifests: Object.assign({}, manifests, {
    messages: { count: 3, hash: 'after-repair' }
  }),
  errorCount: 1,
  warningCount: 1,
  issueCounts: {
    'upload-missing': 1,
    'orphan-message-file': 1
  },
  errors: [{
    kind: 'upload-missing',
    id: 'missing.png',
    severity: 'error'
  }]
};
const baseOptions = {
  baseline,
  candidate,
  allowlist: ['missing.png'],
  routePlan,
  users,
  chats
};

const ready = buildReleaseReadiness(baseOptions);
assert.strictEqual(ready.ok, true, JSON.stringify(ready.failures));
assert.strictEqual(ready.knownMissingMedia.length, 1);
assert.strictEqual(ready.route.counts.total, 4);

const unexpected = JSON.parse(JSON.stringify(candidate));
unexpected.errors[0].id = 'new-missing.png';
const blocked = buildReleaseReadiness(Object.assign({}, baseOptions, {
  candidate: unexpected
}));
assert.strictEqual(blocked.ok, false);
assert.ok(blocked.failures.some((row) => row.name === 'known-media-exact'));

const changedCount = JSON.parse(JSON.stringify(candidate));
changedCount.counts.users = 3;
const countBlocked = buildReleaseReadiness(Object.assign({}, baseOptions, {
  candidate: changedCount
}));
assert.strictEqual(countBlocked.ok, false);
assert.ok(countBlocked.failures.some((row) => row.name === 'collection-counts'));

const changedStableSet = JSON.parse(JSON.stringify(candidate));
changedStableSet.manifests.friendships.hash = 'changed';
const dataBlocked = buildReleaseReadiness(Object.assign({}, baseOptions, {
  candidate: changedStableSet
}));
assert.strictEqual(dataBlocked.ok, false);
assert.ok(dataBlocked.failures.some((row) => row.name === 'stable-collection-checksums'));

console.log('shard-release-readiness: passed');
