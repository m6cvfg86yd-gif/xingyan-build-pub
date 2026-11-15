'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { MessageReliabilityStore } = require('../lib/message-reliability');
const { GroupMembershipStore } = require('../lib/group-membership-store');
const { GroupTimelineService } = require('../lib/group-timeline-service');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-group-timeline-'));
const reliability = new MessageReliabilityStore({
  databaseFile: path.join(root, 'messages.sqlite3'),
  now: () => '2026-11-15T00:00:00.000Z'
});
const membership = new GroupMembershipStore({
  databaseFile: path.join(root, 'membership.sqlite3'),
  now: () => '2026-11-15T00:00:00.000Z'
});
const cleared = new Map([
  ['group-1|carol', 2]
]);
const timeline = new GroupTimelineService({
  reliability,
  membership,
  cleared: {
    get(groupId, userId) {
      return cleared.get(groupId + '|' + userId) || 0;
    }
  }
});

async function main() {
  try {
    membership.join('group-1', 'alice', 1);
    membership.join('group-1', 'bob', 3);
    membership.join('group-1', 'carol', 1);
    membership.leave('group-1', 'carol', 4);
    for (let seq = 1; seq <= 6; seq += 1) {
      reliability.reserveMessage({
        id: 'message-' + seq,
        chatId: 'group-1',
        senderId: 'alice',
        clientId: 'client-' + seq,
        kind: 'text',
        content: 'message ' + seq,
        createdAt: '2026-11-15T00:00:00.000Z'
      });
    }

    let page = await timeline.read({
      groupId: 'group-1',
      userId: 'bob',
      afterSeq: 0,
      limit: 10
    });
    assert.strictEqual(page.ok, true);
    assert.deepStrictEqual(page.messages.map((row) => row.seq), [3, 4, 5, 6]);
    assert.strictEqual(page.lastSeq, 6);

    page = await timeline.read({
      groupId: 'group-1',
      userId: 'carol',
      afterSeq: 0,
      limit: 10
    });
    assert.deepStrictEqual(page.messages.map((row) => row.seq), [3]);
    assert.strictEqual(page.lastSeq, 3);

    assert.strictEqual(timeline.unread('group-1', 'alice', 'phone'), 6);
    timeline.acknowledge('group-1', 'alice', 'phone', 4);
    assert.strictEqual(timeline.unread('group-1', 'alice', 'phone'), 6);
    timeline.markRead('group-1', 'alice', 'phone', 5);
    assert.strictEqual(timeline.unread('group-1', 'alice', 'phone'), 1);
    assert.strictEqual(timeline.unread('group-1', 'bob', 'phone'), 4);

    page = await timeline.read({
      groupId: 'group-1',
      userId: 'outsider',
      afterSeq: 0,
      limit: 10
    });
    assert.strictEqual(page.ok, false);
    assert.strictEqual(page.denied, true);

    console.log('group-timeline-service: passed');
  } finally {
    membership.close();
    reliability.close();
    fs.rmSync(root, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
