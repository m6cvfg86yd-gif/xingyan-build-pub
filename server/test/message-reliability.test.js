'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { MessageReliabilityStore } = require('../lib/message-reliability');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-message-reliability-'));
const databaseFile = path.join(root, 'message-reliability.sqlite3');

try {
    const store = new MessageReliabilityStore({
        databaseFile,
        now: () => '2026-11-14T13:00:00.000Z',
        uid: (() => {
            let index = 0;
            return (prefix) => `${prefix}_${++index}`;
        })()
    });

    const first = store.reserveMessage({
        id: 'm1',
        chatId: 'c1',
        senderId: 'u1',
        clientId: 'client-1',
        content: 'one'
    });
    assert.strictEqual(first.duplicate, false);
    assert.strictEqual(first.seq, 1);

    const duplicate = store.reserveMessage({
        id: 'm2',
        chatId: 'c1',
        senderId: 'u1',
        clientId: 'client-1',
        content: 'one retried'
    });
    assert.strictEqual(duplicate.duplicate, true);
    assert.strictEqual(duplicate.seq, 1);
    assert.strictEqual(duplicate.message.id, 'm1');

    const second = store.reserveMessage({
        id: 'm3',
        chatId: 'c1',
        senderId: 'u2',
        clientId: 'client-2',
        content: 'two'
    });
    assert.strictEqual(second.seq, 2);

    const systemOne = store.reserveMessage({
        id: 'm4', chatId: 'c1', senderId: 'system', kind: 'system', content: 'joined'
    });
    const systemTwo = store.reserveMessage({
        id: 'm5', chatId: 'c1', senderId: 'system', kind: 'system', content: 'left'
    });
    assert.strictEqual(systemOne.seq, 3);
    assert.strictEqual(systemTwo.seq, 4);
    assert.deepStrictEqual(store.messagesAfter('c1', 0, 10).map((m) => m.seq), [1, 2, 3, 4]);
    assert.deepStrictEqual(store.messagesBefore('c1', 4, 10).map((m) => m.seq), [1, 2, 3]);

    assert.strictEqual(store.ackDevice('u1', 'phone-a', 'c1', 2), true);
    assert.strictEqual(store.ackDevice('u1', 'phone-b', 'c1', 4), true);
    assert.strictEqual(store.markDeviceRead('u1', 'phone-b', 'c1', 4), true);
    assert.deepStrictEqual(store.deviceCursor('u1', 'phone-a', 'c1'), {
        deliveredSeq: 2,
        readSeq: 0,
        updatedAt: '2026-11-14T13:00:00.000Z'
    });
    assert.deepStrictEqual(store.deviceCursor('u1', 'phone-b', 'c1'), {
        deliveredSeq: 4,
        readSeq: 4,
        updatedAt: '2026-11-14T13:00:00.000Z'
    });

    store.recordEvent('message.recalled', 'm1', 1, {
        chatId: 'c1', messageId: 'm1', recalled: true
    });
    const events = store.eventsAfter(0, 10);
    assert.strictEqual(events.length, 5);
    assert.strictEqual(events[0].type, 'message.created');
    assert.strictEqual(events[3].entityId, 'm5');
    assert.strictEqual(events[4].type, 'message.recalled');

    const imported = store.importMessages('c2', [
      { id: 'legacy-1', chatId: 'c2', senderId: 'u1', seq: 1, content: 'legacy one' },
      { id: 'legacy-2', chatId: 'c2', senderId: 'u1', seq: 1, content: 'conflict' },
      { id: 'legacy-3', chatId: 'c2', senderId: 'u2', seq: 2, content: 'legacy two' }
    ]);
    assert.deepStrictEqual(imported, { imported: 2, existing: 0, conflicts: 1, total: 3 });
    assert.strictEqual(store.lastSequence('c2'), 2);
    assert.deepStrictEqual(store.messagesAfter('c2', 0, 10).map((m) => m.id),
      ['legacy-1', 'legacy-3']);
    assert.strictEqual(store.eventsAfter(0, 10).length, 5);
    assert.deepStrictEqual(store.importMessages('c2', [
      { id: 'legacy-1', chatId: 'c2', senderId: 'u1', seq: 1, content: 'legacy one' }
    ]), { imported: 0, existing: 1, conflicts: 0, total: 1 });
    store.setMetadata('audit', 'ok');
    assert.strictEqual(store.metadata('audit'), 'ok');
    store.close();

    const reopened = new MessageReliabilityStore({ databaseFile });
    assert.deepStrictEqual(reopened.messagesAfter('c1', 0, 10).map((m) => m.seq), [1, 2, 3, 4]);
    assert.deepStrictEqual(reopened.messagesAfter('c2', 0, 10).map((m) => m.seq), [1, 2]);
    assert.strictEqual(reopened.metadata('audit'), 'ok');
    const afterRestart = reopened.reserveMessage({
        id: 'm6',
        chatId: 'c1',
        senderId: 'u1',
        clientId: 'client-3',
        content: 'three'
    });
    assert.strictEqual(afterRestart.seq, 5);
    assert.strictEqual(reopened.deleteChatMessages('c1'), 5);
    assert.deepStrictEqual(reopened.messagesAfter('c1', 0, 10), []);
    assert.strictEqual(reopened.lastSequence('c1'), 5);
    reopened.close();

    console.log('message-reliability: passed');
} finally {
    if (process.platform !== 'win32') {
        fs.rmSync(root, { recursive: true, force: true });
    }
}
