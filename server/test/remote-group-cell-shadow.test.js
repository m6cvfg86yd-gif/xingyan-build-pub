'use strict';

const assert = require('assert');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');
const { RemoteGroupCellShadow } = require('../lib/remote-group-cell-shadow');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-remote-shadow-'));
const token = 'shadow-test-token';
let child = null;

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

async function startCell(port) {
  child = spawn(process.execPath, [
    path.join(__dirname, '..', 'dev', 'group-cell-server.js'),
    '--cell-id', 'shadow-cell',
    '--port', String(port),
    '--data-dir', path.join(root, 'cell'),
    '--route-db', path.join(root, 'routes.sqlite3')
  ], {
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true,
    env: Object.assign({}, process.env, { GROUP_CELL_INTERNAL_TOKEN: token })
  });
  const logs = [];
  child.stdout.on('data', (chunk) => logs.push(chunk.toString()));
  child.stderr.on('data', (chunk) => logs.push(chunk.toString()));
  const base = 'http://127.0.0.1:' + port;
  for (let index = 0; index < 100; index += 1) {
    if (child.exitCode !== null) throw new Error(logs.join(''));
    try {
      if ((await fetch(base + '/internal/health')).ok) return base;
    } catch (_) { }
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  throw new Error('cell start timeout:\n' + logs.join(''));
}

async function call(base, method, route, value, useToken) {
  const headers = {};
  if (value !== undefined) headers['Content-Type'] = 'application/json';
  if (useToken) headers['X-Internal-Token'] = token;
  const response = await fetch(base + route, {
    method,
    headers,
    body: value === undefined ? undefined : JSON.stringify(value)
  });
  return { status: response.status, data: await response.json() };
}

function message(id, seq, senderId) {
  return {
    id,
    seq,
    senderId,
    clientId: 'client-' + id,
    kind: 'text',
    content: id,
    createdAt: '2026-11-15T00:00:00.000Z'
  };
}

async function main() {
  const shadow = new RemoteGroupCellShadow({
    cellId: 'shadow-cell',
    baseUrl: await startCell(await freePort()),
    internalToken: token,
    reportFile: path.join(root, 'report.json')
  });
  try {
    const chat = { id: 'group-1', type: 'group', memberIds: ['user-1', 'user-2'] };
    let result = await shadow.observe({
      chat,
      senderId: 'user-1',
      message: message('m1', 1, 'user-1')
    });
    assert.strictEqual(result.ok, true, JSON.stringify(result));

    result = await shadow.observe({
      chat,
      senderId: 'user-2',
      message: message('m2', 2, 'user-2')
    });
    assert.strictEqual(result.ok, true, JSON.stringify(result));

    let response = await call(
      shadow.baseUrl,
      'POST',
      '/internal/groups/group-1/shadow',
      { senderId: 'user-1', message: message('bad', 3, 'user-1') },
      false
    );
    assert.strictEqual(response.status, 401);

    chat.memberIds = ['user-1'];
    result = await shadow.observe({
      chat,
      senderId: 'user-1',
      message: message('m3', 3, 'user-1')
    });
    assert.strictEqual(result.ok, true, JSON.stringify(result));
    await shadow.waitForIdle();

    response = await call(
      shadow.baseUrl,
      'GET',
      '/internal/groups/group-1/debug-read?userId=user-1&afterSeq=0&limit=20',
      undefined,
      true
    );
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.deepStrictEqual(response.data.messages.map((row) => row.seq), [1, 2, 3]);

    response = await call(
      shadow.baseUrl,
      'GET',
      '/internal/groups/group-1/debug-read?userId=user-2&afterSeq=0&limit=20',
      undefined,
      true
    );
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.deepStrictEqual(response.data.messages.map((row) => row.seq), [1, 2]);

    const snapshot = shadow.snapshot();
    assert.strictEqual(snapshot.pending, 0);
    assert.strictEqual(snapshot.report.observedMessages, 3);
    assert.strictEqual(snapshot.report.importedMessages, 3);
    assert.deepStrictEqual(snapshot.report.errors, []);
    assert.strictEqual(fs.existsSync(shadow.writeReport()), true);
    console.log('remote-group-cell-shadow: passed');
  } finally {
    await shadow.close();
    if (child && child.exitCode === null) child.kill();
    await new Promise((resolve) => setTimeout(resolve, 250));
    fs.rmSync(root, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  if (child && child.exitCode === null) child.kill();
  process.exitCode = 1;
});
