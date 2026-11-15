'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { GroupMembershipStore } = require('../lib/group-membership-store');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-group-membership-'));
const databaseFile = path.join(root, 'memberships.sqlite3');
let tick = 0;
const store = new GroupMembershipStore({
  databaseFile,
  now: () => new Date(1700000000000 + (++tick)).toISOString()
});

try {
  assert.strictEqual(store.join('group-1', 'alice', 1).joined, true);
  assert.strictEqual(store.join('group-1', 'alice', 2).alreadyActive, true);
  assert.strictEqual(store.join('group-1', 'bob', 5).joined, true);
  assert.strictEqual(store.join('group-1', 'carol', 1).joined, true);
  assert.strictEqual(store.leave('group-1', 'carol', 7).left, true);
  assert.strictEqual(store.join('group-1', 'carol', 10).joined, true);

  assert.strictEqual(store.canReadSync('group-1', 'alice', 1), true);
  assert.strictEqual(store.canReadSync('group-1', 'bob', 4), false);
  assert.strictEqual(store.canReadSync('group-1', 'bob', 5), true);
  assert.strictEqual(store.canReadSync('group-1', 'carol', 6), true);
  assert.strictEqual(store.canReadSync('group-1', 'carol', 7), false);
  assert.strictEqual(store.canReadSync('group-1', 'carol', 10), true);

  assert.strictEqual(store.countActive('group-1', 1), 2);
  assert.strictEqual(store.countActive('group-1', 7), 2);
  assert.strictEqual(store.countActive('group-1', 10), 3);
  assert.deepStrictEqual(
    store.activeMembers('group-1', 10, 0, 2).map((row) => row.userId),
    ['alice', 'bob']
  );
  assert.deepStrictEqual(
    store.activeMembers('group-1', 10, 2, 2).map((row) => row.userId),
    ['carol']
  );
  assert.strictEqual(store.get('group-1', 'carol', 7), null);
  assert.strictEqual(store.get('group-1', 'carol', 10).joinedSeq, 10);

  console.log('group-membership-store: passed');
} finally {
  store.close();
  fs.rmSync(root, { recursive: true, force: true });
}
