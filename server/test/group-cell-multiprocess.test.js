'use strict';

const assert = require('assert');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');
const { GroupRouteStore } = require('../lib/group-route-store');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-group-cell-process-'));
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
  ], {
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true
  });
  const logs = [];
  child.stdout.on('data', (chunk) => logs.push(chunk.toString()));
  child.stderr.on('data', (chunk) => logs.push(chunk.toString()));
  services.push(child);
  const base = 'http://127.0.0.1:' + port;
  for (let index = 0; index < 100; index += 1) {
    if (child.exitCode !== null) throw new Error(logs.join(''));
    try {
      if ((await fetch(base + '/internal/health')).ok) return { child, base };
    } catch (_) { }
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  throw new Error('cell start timeout:\n' + logs.join(''));
}

async function call(base, method, route, value) {
  const response = await fetch(base + route, {
    method,
    headers: value === undefined ? undefined : { 'Content-Type': 'application/json' },
    body: value === undefined ? undefined : JSON.stringify(value)
  });
  return { status: response.status, data: await response.json() };
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
  let store = null;
  try {
    const portA = await freePort();
    const portB = await freePort();
    const baseA = 'http://127.0.0.1:' + portA;
    const baseB = 'http://127.0.0.1:' + portB;
    await startCell('cell-a', portA, 'cell-b=' + baseB);
    await startCell('cell-b', portB, 'cell-a=' + baseA);
    store = new GroupRouteStore({ databaseFile: routeFile });
    assert.strictEqual(store.set({
      groupId: 'group-1',
      cellId: 'cell-a',
      epoch: 1,
      status: 'active'
    }).ok, true);

    for (const base of [baseA, baseB]) {
      let response = await call(base, 'POST', '/internal/groups/group-1/join', {
        userId: 'user-1',
        joinedSeq: 1
      });
      assert.strictEqual(response.status, 200);
    }
    let response = await call(baseA, 'POST', '/internal/groups/group-1/messages', {
      senderId: 'user-1',
      message: message('m1', 1)
    });
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    response = await call(baseB, 'POST', '/internal/groups/group-1/messages', {
      senderId: 'user-1',
      message: message('wrong', 2)
    });
    assert.strictEqual(response.status, 409);
    assert.strictEqual(response.data.error, 'wrong-cell');

    const current = store.get('group-1');
    assert.strictEqual(store.set(Object.assign({}, current, {
      epoch: 2,
      status: 'migrating',
      sourceCellId: 'cell-a',
      targetCellId: 'cell-b'
    })).ok, true);
    response = await call(baseB, 'POST', '/internal/groups/group-1/mirror', {
      epoch: 2,
      senderId: 'user-1',
      message: message('m1', 1)
    });
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    response = await call(baseA, 'POST', '/internal/groups/group-1/messages', {
      senderId: 'user-1',
      message: message('m2', 2)
    });
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(response.data.dualWrite.ok, true);

    assert.strictEqual(store.set({
      groupId: 'group-1',
      cellId: 'cell-b',
      epoch: 2,
      status: 'active'
    }).ok, true);
    response = await call(baseA, 'POST', '/internal/groups/group-1/messages', {
      senderId: 'user-1',
      message: message('stale', 3)
    });
    assert.strictEqual(response.status, 409);
    response = await call(baseB, 'GET',
      '/internal/groups/group-1/messages?userId=user-1&afterSeq=0&limit=20');
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.deepStrictEqual(response.data.messages.map((row) => row.seq), [1, 2]);
    console.log('group-cell-multiprocess: passed');
  } finally {
    if (store) store.close();
    for (const child of services) {
      if (child.exitCode === null) child.kill();
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
    fs.rmSync(root, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
