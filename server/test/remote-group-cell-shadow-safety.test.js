'use strict';

const assert = require('assert');
const { RemoteGroupCellShadow } = require('../lib/remote-group-cell-shadow');

function message(id, seq) {
  return {
    id,
    seq,
    senderId: 'user-1',
    kind: 'text',
    content: id,
    createdAt: '2026-11-15T00:00:00.000Z'
  };
}

function response(value) {
  return {
    ok: true,
    status: 200,
    async json() { return value; }
  };
}

async function boundedQueue() {
  let release = null;
  const waiting = new Promise((resolve) => { release = resolve; });
  const shadow = new RemoteGroupCellShadow({
    cellId: 'cell-a',
    baseUrl: 'http://127.0.0.1:6200',
    maxPending: 1,
    fetchImpl: async () => {
      await waiting;
      return response({ ok: true, imported: { imported: 1 } });
    }
  });
  const chat = { id: 'group-1', memberIds: ['user-1'] };
  const first = shadow.observe({ chat, senderId: 'user-1', message: message('m1', 1) });
  await new Promise((resolve) => setImmediate(resolve));
  const second = await shadow.observe({
    chat,
    senderId: 'user-1',
    message: message('m2', 2)
  });
  assert.strictEqual(second.ok, false);
  assert.strictEqual(second.skipped, true);
  assert.strictEqual(shadow.snapshot().report.queueFull, 1);
  release();
  await first;
  await shadow.close();
}

async function circuitBreaker() {
  let clock = 1000;
  let online = false;
  let calls = 0;
  const shadow = new RemoteGroupCellShadow({
    cellId: 'cell-a',
    baseUrl: 'http://127.0.0.1:6200',
    failureBackoffMs: 5000,
    now: () => clock,
    fetchImpl: async () => {
      calls += 1;
      if (!online) throw new Error('offline');
      return response({ ok: true, imported: { imported: 1 } });
    }
  });
  const chat = { id: 'group-1', memberIds: ['user-1'] };
  let result = await shadow.observe({
    chat,
    senderId: 'user-1',
    message: message('m1', 1)
  });
  assert.strictEqual(result.ok, false);
  assert.strictEqual(calls, 1);

  result = await shadow.observe({
    chat,
    senderId: 'user-1',
    message: message('m2', 2)
  });
  assert.strictEqual(result.skipped, true);
  assert.strictEqual(calls, 1);
  assert.strictEqual(shadow.snapshot().report.circuitSkipped, 1);

  clock += 6000;
  online = true;
  result = await shadow.observe({
    chat,
    senderId: 'user-1',
    message: message('m3', 3)
  });
  assert.strictEqual(result.ok, true);
  assert.strictEqual(shadow.snapshot().consecutiveFailures, 0);
  assert.strictEqual(shadow.snapshot().circuitOpenUntil, 0);
  await shadow.close();
}

async function main() {
  await boundedQueue();
  await circuitBreaker();
  console.log('remote-group-cell-shadow-safety: passed');
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
