'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { MessageReliabilityStore } = require('../lib/message-reliability');
const { MessageWritePipeline } = require('../lib/message-write-pipeline');

class MemoryThreadStore {
  constructor() {
    this.threads = new Map();
    this.failAppend = false;
  }

  rows(chatId) {
    return this.threads.get(chatId) || [];
  }

  async read(chatId) {
    return this.rows(chatId).slice();
  }

  async hasMessage(chatId, messageId) {
    return this.rows(chatId).some((row) => row.id === messageId);
  }

  async append(chatId, message) {
    if (this.failAppend) throw new Error('simulated storage outage');
    const rows = this.rows(chatId).slice();
    if (!rows.some((row) => row.id === message.id)) rows.push(message);
    this.threads.set(chatId, rows);
  }
}

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-message-pipeline-'));
const databaseFile = path.join(root, 'message-reliability.sqlite3');
let uid = 0;
const reliability = new MessageReliabilityStore({
  databaseFile,
  now: () => '2026-11-15T00:00:00.000Z',
  uid: (prefix) => prefix + '-' + (++uid)
});
const threadStore = new MemoryThreadStore();
const pipeline = new MessageWritePipeline({
  reliability,
  threadStore,
  now: () => '2026-11-15T00:00:00.000Z'
});

function input(chatId, id, senderId, clientId, content) {
  return {
    id,
    chatId,
    senderId,
    clientId,
    kind: 'text',
    content,
    createdAt: '2026-11-15T00:00:00.000Z'
  };
}

async function main() {
  try {
    threadStore.failAppend = true;
    const pending = await pipeline.append(
      'chat-repair',
      input('chat-repair', 'repair-1', 'user-a', 'client-repair', 'original')
    );
    assert.strictEqual(pending.ok, false);
    assert.strictEqual(pending.durable, true);
    assert.strictEqual(pending.storagePending, true);
    assert.strictEqual(pending.seq, 1);
    assert.strictEqual(threadStore.rows('chat-repair').length, 0);

    threadStore.failAppend = false;
    const repaired = await pipeline.append(
      'chat-repair',
      input('chat-repair', 'different-id', 'user-a', 'client-repair', 'changed')
    );
    assert.strictEqual(repaired.ok, true);
    assert.strictEqual(repaired.duplicate, true);
    assert.strictEqual(repaired.storageRepaired, true);
    assert.strictEqual(repaired.message.id, 'repair-1');
    assert.strictEqual(repaired.message.content, 'original');
    assert.strictEqual(repaired.seq, 1);
    assert.deepStrictEqual(threadStore.rows('chat-repair').map((row) => row.id),
      ['repair-1']);

    const concurrentDuplicate = await Promise.all(
      Array.from({ length: 12 }, (_, index) => pipeline.append(
        'chat-duplicate',
        input('chat-duplicate', 'duplicate-' + index, 'user-a',
          'same-client-id', 'duplicate payload ' + index)
      ))
    );
    assert.strictEqual(new Set(concurrentDuplicate.map((row) => row.message.id)).size, 1);
    assert.strictEqual(new Set(concurrentDuplicate.map((row) => row.seq)).size, 1);
    assert.strictEqual(threadStore.rows('chat-duplicate').length, 1);
    assert.strictEqual(threadStore.rows('chat-duplicate')[0].content, 'duplicate payload 0');

    const ordered = await Promise.all(
      Array.from({ length: 120 }, (_, index) => pipeline.append(
        'chat-ordered',
        input('chat-ordered', 'ordered-' + index, 'user-' + (index % 4),
          'ordered-client-' + index, 'message ' + index)
      ))
    );
    assert.deepStrictEqual(
      ordered.map((row) => row.seq),
      Array.from({ length: 120 }, (_, index) => index + 1)
    );
    assert.deepStrictEqual(
      threadStore.rows('chat-ordered').map((row) => row.seq),
      Array.from({ length: 120 }, (_, index) => index + 1)
    );

    const events = reliability.eventsAfter(0, 1000)
      .filter((event) => event.type === 'message.created');
    assert.strictEqual(events.length, 122);
    assert.strictEqual(new Set(events.map((event) => event.entityId)).size, 122);
    assert.strictEqual(reliability.lastSequence('chat-repair'), 1);
    assert.strictEqual(reliability.lastSequence('chat-duplicate'), 1);
    assert.strictEqual(reliability.lastSequence('chat-ordered'), 120);

    console.log('message-write-pipeline: passed');
  } finally {
    reliability.close();
    fs.rmSync(root, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
