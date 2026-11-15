'use strict';

const assert = require('assert');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');
const { GroupRouteStore } = require('../lib/group-route-store');
const { RemoteGroupMigrationWorker } = require('../lib/remote-group-migration-worker');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-remote-migration-'));
const routeFile = path.join(root, 'routes.sqlite3');
const services = [];

function freePort() {
  return new Promise((resolve, reject) => {
    const socket = net.createServer();
    socket.once('error', reject);
    socket.listen(0, '127.0.0.1', () => {
      const port = socket.address().port;
      socket.close(() => resolve(port));
    });
  });
}

async function startCell(cellId, port, peer) {
  const child = spawn(process.execPath, [
    path.join(__dirname, '..', 'dev', 'group-cell-server.js'),
    '--cell-id', cellId,
    '--port', String(port),
    '--data-dir', path.join(root, cellId),
    '--route-db', routeFile,
    '--peer', peer
  ], { stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true });
  services.push(child);
  const base = 'http://127.0.0.1:' + port;
  for (let index = 0; index < 100; index += 1) {
    if (child.exitCode !== null) throw new Error('cell exited');
    try {
      if ((await fetch(base + '/internal/health')).ok) return base;
    } catch (_) { }
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  throw new Error('cell start timeout');
}

async function call(base, method, route, value) {
  const response = await fetch(base + route, {
    method,
    headers: value === undefined ? undefined : { 'Content-Type': 'application/json' },
    body: value === undefined ? undefined : JSON.stringify(value)
  });
  return { status: response.status, data: await response.json() };
}

function message(seq) {
  return {
    id: 'message-' + seq,
    seq,
    senderId: 'user-1',
    clientId: 'client-' + seq,
    kind: 'text',
    content: 'message ' + seq,
    createdAt: '2026-11-15T00:00:00.000Z'
  };
}

async function main() {
  let store = null;
  try {
    const portA = await freePort();
    const portB = await freePort();
    const baseA = 'http://127.0.0.1:' + portA;
    const baseB = 'http://127.0.0.1:' + portB;
    await startCell('cell-a', portA, 'cell-b=' + baseB);
    await startCell('cell-b', portB, 'cell-a=' + baseA);
    store = new GroupRouteStore({ databaseFile: routeFile });
    store.set({ groupId: 'group-1', cellId: 'cell-a', epoch: 1, status: 'active' });
    for (const [userId, joinedSeq] of [['user-1', 1], ['user-2', 1]]) {
      const joined = await call(baseA, 'POST', '/internal/groups/group-1/join', {
        userId,
        joinedSeq
      });
      assert.strictEqual(joined.status, 200);
    }
    for (let seq = 1; seq <= 60; seq += 1) {
      const sent = await call(baseA, 'POST', '/internal/groups/group-1/messages', {
        senderId: 'user-1',
        message: message(seq)
      });
      assert.strictEqual(sent.status, 200, JSON.stringify(sent.data));
    }
    await call(baseA, 'POST', '/internal/groups/group-1/hide', {
      userId: 'user-2',
      messageId: 'message-11'
    });
    await call(baseA, 'POST', '/internal/groups/group-1/clear', {
      userId: 'user-2',
      seq: 5
    });
    await call(baseA, 'POST', '/internal/groups/group-1/recall', {
      messageId: 'message-10',
      seq: 10,
      actorUserId: 'user-1'
    });
    await call(baseA, 'POST', '/internal/groups/group-1/ack', {
      userId: 'user-1',
      deviceId: 'phone',
      seq: 40
    });
    await call(baseA, 'POST', '/internal/groups/group-1/read-cursor', {
      userId: 'user-1',
      deviceId: 'phone',
      seq: 35
    });

    const worker = new RemoteGroupMigrationWorker({
      routeStore: store,
      sourceUrl: baseA,
      targetUrl: baseB,
      stateDir: path.join(root, 'worker-state'),
      pageSize: 20
    });
    let injected = false;
    const report = await worker.migrate({
      groupId: 'group-1',
      sourceCellId: 'cell-a',
      targetCellId: 'cell-b',
      epoch: 2,
      finalize: true,
      afterPage: async ({ pages }) => {
        if (injected || pages !== 1) return;
        injected = true;
        const sent = await call(baseA, 'POST', '/internal/groups/group-1/messages', {
          senderId: 'user-1',
          message: message(61)
        });
        assert.strictEqual(sent.status, 200);
        assert.strictEqual(sent.data.dualWrite.ok, true);
      }
    });
    assert.strictEqual(report.ok, true, JSON.stringify(report, null, 2));
    assert.strictEqual(report.route.cellId, 'cell-b');
    const page = await call(baseB, 'GET',
      '/internal/groups/group-1/messages?userId=user-1&afterSeq=0&limit=100');
    assert.strictEqual(page.status, 200, JSON.stringify(page.data));
    assert.strictEqual(page.data.messages.length, 61);
    assert.strictEqual(page.data.messages[60].seq, 61);
    const recalled = page.data.messages.find((row) => row.id === 'message-10');
    assert.strictEqual(recalled.recalled, true);
    assert.strictEqual(recalled.content, '');
    console.log('group-remote-migration: passed');
  } finally {
    if (store) store.close();
    for (const child of services) {
      if (child.exitCode === null) child.kill();
    }
    await new Promise((resolve) => setTimeout(resolve, 300));
    fs.rmSync(root, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
