'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { GroupMessageCell } = require('../lib/group-message-cell');
const { GroupCellRouter } = require('../lib/group-cell-router');
const { GroupMigrationWorker } = require('../lib/group-migration-worker');

class Sink {
  async notifyUser() {}
  async publishGroupSignal() {}
  async enqueueUser() {}
  async enqueuePartition() {}
}

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-group-migration-'));
let source = null;
let target = null;
let worker = null;

function cell(id) {
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

function message(seq) {
  return {
    id: 'message-' + seq,
    chatId: 'group-1',
    seq,
    senderId: 'user-1',
    clientId: 'client-' + seq,
    kind: 'text',
    content: 'message ' + seq,
    createdAt: '2026-11-15T00:00:00.000Z'
  };
}

async function main() {
  try {
    source = cell('source');
    target = cell('target');
    source.join('group-1', 'user-1', 1);
    source.join('group-1', 'user-2', 1);
    for (let seq = 1; seq <= 120; seq += 1) {
      await source.mirror('group-1', 'user-1', message(seq), { fanout: false });
    }
    source.recall('group-1', 'message-10', 10, 'user-1');
    source.hideForUser('group-1', 'user-2', 'message-11');
    source.clearForUser('group-1', 'user-2', 5);
    source.acknowledge('group-1', 'user-1', 'phone', 80);
    source.markRead('group-1', 'user-1', 'phone', 70);

    const router = new GroupCellRouter({
      cells: { source, target }
    });
    router.assign('group-1', 'source', 1);
    worker = new GroupMigrationWorker({
      router,
      stateDir: path.join(root, 'migration-state'),
      pageSize: 25
    });

    let injected = false;
    const report = await worker.migrate({
      groupId: 'group-1',
      sourceCellId: 'source',
      targetCellId: 'target',
      epoch: 2,
      finalize: true,
      afterPage: async ({ pageCount }) => {
        if (injected || pageCount !== 1) return;
        injected = true;
        const result = await router.send(
          'group-1',
          'source',
          'user-1',
          Object.assign(message(121), {
            id: 'message-121',
            clientId: 'client-121'
          })
        );
        assert.strictEqual(result.ok, true);
        assert.strictEqual(result.dualWrite.ok, true);
      }
    });
    assert.strictEqual(report.ok, true, JSON.stringify(report, null, 2));
    assert.strictEqual(report.route.cellId, 'target');
    assert.strictEqual(router.owner('group-1'), 'target');

    const page = await target.read({
      groupId: 'group-1',
      userId: 'user-1',
      afterSeq: 0,
      limit: 20
    });
    assert.strictEqual(page.ok, true);
    assert.deepStrictEqual(page.messages.map((row) => row.seq).slice(0, 3), [1, 2, 3]);
    const last = target.reliability.lastSequence('group-1');
    assert.strictEqual(last, 121);
    assert.strictEqual(target.reliability.deviceCursor('user-1', 'phone', 'group-1').readSeq, 70);
    assert.strictEqual(target.deletions.clearance('group-1', 'user-2'), 5);
    assert.strictEqual(target.deletions.globalState('message-10').action, 'recall');

    const checkpoint = worker.get('group-1');
    assert.strictEqual(checkpoint.status, 'done');
    assert.strictEqual(checkpoint.epoch, 2);
    const resumed = await worker.migrate({
      groupId: 'group-1',
      sourceCellId: 'source',
      targetCellId: 'target',
      epoch: 2,
      finalize: true
    });
    assert.strictEqual(resumed.resumed, true);
    console.log('group-migration-worker: passed');
  } finally {
    if (worker) worker.close();
    if (source) source.close();
    if (target) target.close();
    fs.rmSync(root, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
