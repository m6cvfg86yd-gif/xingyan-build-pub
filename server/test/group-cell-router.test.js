'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { GroupMessageCell } = require('../lib/group-message-cell');
const { GroupCellRouter } = require('../lib/group-cell-router');

class Sink {
  async notifyUser() {}
  async publishGroupSignal() {}
  async enqueueUser() {}
  async enqueuePartition() {}
}

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-group-router-'));
let cellA = null;
let cellB = null;

function createCell(id) {
  return new GroupMessageCell({
    cellId: id,
    dataDir: path.join(root, id),
    realtime: new Sink(),
    pushQueue: new Sink(),
    presence: null,
    largeGroupThreshold: 500,
    schedule: (work) => setImmediate(work),
    now: () => '2026-11-15T00:00:00.000Z'
  });
}

function message(id, seq) {
  return {
    id,
    seq,
    senderId: 'user-1',
    clientId: 'client-' + id,
    kind: 'text',
    content: id,
    createdAt: '2026-11-15T00:00:00.000Z'
  };
}

async function main() {
  try {
    cellA = createCell('cell-a');
    cellB = createCell('cell-b');
    const router = new GroupCellRouter({
      cells: { 'cell-a': cellA, 'cell-b': cellB }
    });
    router.assign('group-1', 'cell-a', 1);
    cellA.join('group-1', 'user-1', 1);

    let result = await router.send('group-1', 'cell-a', 'user-1', message('m1', 1));
    assert.strictEqual(result.ok, true);
    result = await router.send('group-1', 'cell-b', 'user-1', message('wrong', 2));
    assert.strictEqual(result.ok, false);
    assert.strictEqual(result.error, 'wrong-cell');

    cellB.join('group-1', 'user-1', 1);
    const migration = router.beginMigration('group-1', 'cell-b', 2);
    assert.strictEqual(migration.route.status, 'migrating');
    assert.strictEqual(router.owner('group-1'), 'cell-a');
    result = await router.send('group-1', 'cell-a', 'user-1', message('m2', 2));
    assert.strictEqual(result.ok, true);
    result = await router.send('group-1', 'cell-b', 'user-1', message('m3', 3));
    assert.strictEqual(result.ok, false);

    await cellB.mirror('group-1', 'user-1', message('m1', 1));
    await cellB.mirror('group-1', 'user-1', message('m2', 2));
    const completed = router.completeMigration('group-1', 2);
    assert.strictEqual(completed.route.cellId, 'cell-b');
    assert.strictEqual(router.owner('group-1'), 'cell-b');
    result = await router.send('group-1', 'cell-a', 'user-1', message('stale', 3));
    assert.strictEqual(result.ok, false);
    result = await router.send('group-1', 'cell-b', 'user-1', message('m3', 3));
    assert.strictEqual(result.ok, true);
    const page = await router.read('group-1', 'cell-b', {
      userId: 'user-1',
      afterSeq: 0,
      limit: 20
    });
    assert.deepStrictEqual(page.messages.map((row) => row.seq), [1, 2, 3]);

    console.log('group-cell-router: passed');
  } finally {
    if (cellA) cellA.close();
    if (cellB) cellB.close();
    fs.rmSync(root, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
