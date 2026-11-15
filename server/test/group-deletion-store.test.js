'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { GroupDeletionStore } = require('../lib/group-deletion-store');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-group-deletions-'));
const store = new GroupDeletionStore({
  databaseFile: path.join(root, 'deletions.sqlite3'),
  now: () => '2026-11-15T00:00:00.000Z'
});

function messages() {
  return [1, 2, 3, 4, 5].map((seq) => ({
    id: 'message-' + seq,
    chatId: 'group-1',
    seq,
    senderId: 'user-1',
    kind: 'text',
    content: 'message ' + seq
  }));
}

try {
  store.hideForUser('group-1', 'alice', 'message-2');
  assert.deepStrictEqual(
    store.apply('group-1', 'alice', messages()).map((row) => row.seq),
    [1, 3, 4, 5]
  );
  assert.deepStrictEqual(
    store.apply('group-1', 'bob', messages()).map((row) => row.seq),
    [1, 2, 3, 4, 5]
  );

  assert.strictEqual(store.recall('group-1', 'message-3', 3, 'user-1').updated, true);
  const recalled = store.apply('group-1', 'bob', messages())
    .find((row) => row.id === 'message-3');
  assert.strictEqual(recalled.recalled, true);
  assert.strictEqual(recalled.content, '');
  assert.strictEqual(recalled.deletionAction, 'recall');
  assert.strictEqual(store.recall('group-1', 'message-3', 3, 'user-1').duplicate, false);

  assert.strictEqual(store.takedown(
    'group-1',
    'message-4',
    4,
    'admin',
    'policy'
  ).updated, true);
  const takenDown = store.apply('group-1', 'bob', messages())
    .find((row) => row.id === 'message-4');
  assert.strictEqual(takenDown.deletionAction, 'takedown');
  assert.strictEqual(takenDown.deletionVersion, 3);
  assert.strictEqual(takenDown.deletionReason, 'policy');

  assert.strictEqual(store.clearForUser('group-1', 'alice', 4), 4);
  assert.strictEqual(store.clearance('group-1', 'alice'), 4);
  assert.strictEqual(store.clearForUser('group-1', 'alice', 2), 2);
  assert.strictEqual(store.clearance('group-1', 'alice'), 4);

  console.log('group-deletion-store: passed');
} finally {
  store.close();
  fs.rmSync(root, { recursive: true, force: true });
}
