'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { GroupRouteStore } = require('../lib/group-route-store');
const { GroupCellRouter } = require('../lib/group-cell-router');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-group-route-store-'));
const databaseFile = path.join(root, 'routes.sqlite3');
const storeA = new GroupRouteStore({
  databaseFile,
  now: () => '2026-11-15T00:00:00.000Z'
});
const storeB = new GroupRouteStore({
  databaseFile,
  now: () => '2026-11-15T00:00:00.000Z'
});
const cells = { 'cell-a': {}, 'cell-b': {} };
const routerA = new GroupCellRouter({ cells, routeStore: storeA });
const routerB = new GroupCellRouter({ cells, routeStore: storeB });

try {
  assert.strictEqual(routerA.assign('group-1', 'cell-a', 1).ok, true);
  assert.strictEqual(routerB.route('group-1').cellId, 'cell-a');
  assert.strictEqual(routerB.assign('group-1', 'cell-a', 2).ok, true);
  const stale = routerA.assign('group-1', 'cell-b', 1);
  assert.strictEqual(stale.ok, false);
  assert.strictEqual(stale.stale, true);
  assert.strictEqual(routerA.route('group-1').epoch, 2);

  const migration = routerB.beginMigration('group-1', 'cell-b', 3);
  assert.strictEqual(migration.ok, true);
  assert.strictEqual(routerA.route('group-1').status, 'migrating');
  assert.strictEqual(routerA.owner('group-1'), 'cell-a');
  assert.strictEqual(routerA.completeMigration('group-1', 3).ok, true);
  assert.strictEqual(routerB.owner('group-1'), 'cell-b');
  console.log('group-route-store: passed');
} finally {
  storeA.close();
  storeB.close();
  fs.rmSync(root, { recursive: true, force: true });
}
