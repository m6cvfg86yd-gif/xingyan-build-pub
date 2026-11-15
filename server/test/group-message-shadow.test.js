'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { GroupMessageShadow } = require('../lib/group-message-shadow');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-group-shadow-'));
async function main() {
  let shadow = null;
  try {
    shadow = new GroupMessageShadow({
      dataDir: root,
      largeGroupThreshold: 2,
      pushPartitionSize: 2,
      now: () => '2026-11-15T00:00:00.000Z',
      uid: (() => {
        let index = 0;
        return (prefix) => prefix + '-' + (++index);
      })()
    });
    const chat = {
      id: 'group-1',
      memberIds: ['user-1', 'user-2', 'user-3']
    };
    let result = shadow.observe({
      cellId: 'cell-a',
      chat,
      senderId: 'user-1',
      message: {
        id: 'real-message-1',
        chatId: 'group-1',
        seq: 1,
        senderId: 'user-1',
        clientId: 'client-1',
        kind: 'text',
        content: 'hello',
        createdAt: '2026-11-15T00:00:00.000Z'
      }
    });
    assert.strictEqual(result.ok, true);
    assert.strictEqual(result.imported.imported, 1);
    await shadow.waitForFanout();

    result = shadow.observe({
      cellId: 'cell-a',
      chat,
      senderId: 'user-1',
      message: {
        id: 'real-message-1',
        chatId: 'group-1',
        seq: 1,
        senderId: 'user-1',
        clientId: 'client-1',
        kind: 'text',
        content: 'hello',
        createdAt: '2026-11-15T00:00:00.000Z'
      }
    });
    assert.strictEqual(result.fanout, 'duplicate');
    const snapshot = shadow.snapshot();
    assert.strictEqual(snapshot.groups, 1);
    assert.strictEqual(snapshot.report.observedMessages, 2);
    assert.strictEqual(snapshot.report.importedMessages, 1);
    assert.strictEqual(snapshot.report.duplicateMessages, 1);
    assert.strictEqual(snapshot.report.conflicts, 0);
    const report = shadow.writeReport(path.join(root, 'report.json'));
    assert.strictEqual(fs.existsSync(report), true);
    console.log('group-message-shadow: passed');
  } finally {
    if (shadow) shadow.close();
    fs.rmSync(root, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
