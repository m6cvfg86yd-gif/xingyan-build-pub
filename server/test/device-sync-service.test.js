'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { MessageReliabilityStore } = require('../lib/message-reliability');
const { DeviceSyncService } = require('../lib/device-sync-service');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-device-sync-'));
const reliability = new MessageReliabilityStore({
  databaseFile: path.join(root, 'reliability.sqlite3'),
  now: () => '2026-11-15T00:00:00.000Z'
});
const chats = [
  { id: 'chat-a', seq: 0, memberIds: ['user-1', 'user-2'] },
  { id: 'chat-b', seq: 0, memberIds: ['user-1', 'user-2'] },
  { id: 'chat-private', seq: 0, memberIds: ['user-2'] }
];
const service = new DeviceSyncService({
  reliability,
  listChats: (userId) => chats.filter((chat) => chat.memberIds.includes(userId))
});

try {
  for (const chatId of ['chat-a', 'chat-b']) {
    for (let seq = 1; seq <= 3; seq += 1) {
      reliability.reserveMessage({
        id: chatId + '-m' + seq,
        chatId,
        senderId: 'user-2',
        seq,
        kind: 'text',
        content: 'message ' + seq,
        createdAt: '2026-11-15T00:00:00.000Z'
      });
    }
  }
  let page = service.state({ userId: 'user-1', deviceId: 'phone', limit: 1 });
  assert.strictEqual(page.items.length, 1);
  assert.strictEqual(page.items[0].chatId, 'chat-a');
  assert.strictEqual(page.items[0].lastSeq, 3);
  assert.strictEqual(page.items[0].deliveredSeq, 0);
  assert.strictEqual(page.items[0].hasDelta, true);
  assert.strictEqual(page.hasMore, true);

  page = service.state({
    userId: 'user-1',
    deviceId: 'phone',
    cursor: page.nextCursor,
    limit: 10
  });
  assert.deepStrictEqual(page.items.map((item) => item.chatId), ['chat-b']);
  assert.strictEqual(page.hasMore, false);

  let result = service.acknowledge({
    userId: 'user-1',
    deviceId: 'phone',
    items: [
      { chatId: 'chat-a', seq: 3 },
      { chatId: 'chat-b', seq: 2 },
      { chatId: 'chat-private', seq: 3 }
    ]
  });
  assert.strictEqual(result.acknowledged, 2);
  assert.strictEqual(result.rejected.length, 1);
  assert.deepStrictEqual(reliability.deviceCursor('user-1', 'phone', 'chat-a'), {
    deliveredSeq: 3,
    readSeq: 0,
    updatedAt: '2026-11-15T00:00:00.000Z'
  });
  assert.strictEqual(
    reliability.deviceCursor('user-1', 'desktop', 'chat-a').deliveredSeq,
    0
  );

  page = service.state({ userId: 'user-1', deviceId: 'phone', limit: 10 });
  assert.strictEqual(page.items.find((item) => item.chatId === 'chat-a').hasDelta, false);
  assert.strictEqual(page.items.find((item) => item.chatId === 'chat-b').hasDelta, true);
  console.log('device-sync-service: passed');
} finally {
  reliability.close();
  fs.rmSync(root, { recursive: true, force: true });
}
