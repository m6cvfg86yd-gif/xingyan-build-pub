'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { GroupRouteStore } = require('../lib/group-route-store');
const {
  previewGroupCellRouteImport,
  applyGroupCellRouteImport
} = require('../lib/group-cell-route-import');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-group-route-import-'));
const databaseFile = path.join(root, 'routes.sqlite3');
let store = new GroupRouteStore({
  databaseFile,
  now: () => '2026-11-15T00:00:00.000Z'
});

try {
  store.set({
    groupId: 'group-1',
    cellId: 'cell-a',
    epoch: 1,
    status: 'active'
  });
  const plan = {
    assignmentHash: 'plan-hash',
    assignments: [
      { groupId: 'group-2', cellId: 'cell-b' },
      { groupId: 'group-1', cellId: 'cell-a' }
    ]
  };
  let preview = previewGroupCellRouteImport(plan, store);
  assert.strictEqual(preview.ok, true);
  assert.deepStrictEqual(preview.inserted.map((row) => row.groupId), ['group-2']);
  assert.deepStrictEqual(preview.unchanged.map((row) => row.groupId), ['group-1']);

  let result = applyGroupCellRouteImport(plan, store);
  assert.strictEqual(result.ok, true);
  assert.strictEqual(store.get('group-2').cellId, 'cell-b');
  result = applyGroupCellRouteImport(plan, store);
  assert.strictEqual(result.inserted.length, 0);
  assert.strictEqual(result.unchanged.length, 2);

  const conflictPlan = {
    assignments: [
      { groupId: 'group-1', cellId: 'cell-b' },
      { groupId: 'group-3', cellId: 'cell-b' }
    ]
  };
  preview = previewGroupCellRouteImport(conflictPlan, store);
  assert.strictEqual(preview.ok, false);
  assert.strictEqual(preview.conflicts.length, 1);
  result = applyGroupCellRouteImport(conflictPlan, store);
  assert.strictEqual(result.ok, false);
  assert.strictEqual(store.get('group-3'), null);

  const batch = store.setInitialMany([
    { groupId: 'group-4', cellId: 'cell-a', epoch: 1 },
    { groupId: 'group-1', cellId: 'cell-b', epoch: 1 }
  ]);
  assert.strictEqual(batch.ok, false);
  assert.strictEqual(store.get('group-4'), null);
  assert.strictEqual(store.get('group-1').cellId, 'cell-a');

  store.close();
  store = new GroupRouteStore({ databaseFile, readOnly: true });
  assert.strictEqual(store.get('group-2').cellId, 'cell-b');
  assert.throws(() => store.setInitialMany([
    { groupId: 'group-5', cellId: 'cell-a', epoch: 1 }
  ]), /read-only/);
  console.log('group-cell-route-import: passed');
} finally {
  try { store.close(); } catch (_) { }
  fs.rmSync(root, { recursive: true, force: true });
}
