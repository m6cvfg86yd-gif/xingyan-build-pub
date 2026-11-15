'use strict';

const assert = require('assert');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');
const { inspectPilotGroup, sequenceSummary } = require('../lib/group-cell-pilot-gate');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-pilot-gate-'));
const routeFile = path.join(root, 'routes.sqlite3');
const token = 'pilot-token';
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

async function startCell(cellId, port) {
  const child = spawn(process.execPath, [
    path.join(__dirname, '..', 'dev', 'group-cell-server.js'),
    '--cell-id', cellId,
    '--port', String(port),
    '--data-dir', path.join(root, cellId),
    '--route-db', routeFile
  ], {
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true,
    env: Object.assign({}, process.env, { GROUP_CELL_INTERNAL_TOKEN: token })
  });
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
    headers: {
      'Content-Type': 'application/json',
      'X-Internal-Token': token
    },
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
  try {
    const sourceUrl = await startCell('source', await freePort());
    const targetUrl = await startCell('target', await freePort());
    for (const userId of ['user-1', 'user-2']) {
      await call(sourceUrl, 'POST', '/internal/groups/group-1/join', {
        userId,
        joinedSeq: 1
      });
    }
    for (let seq = 1; seq <= 7; seq += 1) {
      const sent = await call(sourceUrl, 'POST', '/internal/groups/group-1/shadow', {
        senderId: 'user-1',
        message: message(seq)
      });
      assert.strictEqual(sent.status, 200, JSON.stringify(sent.data));
    }

    const report = await inspectPilotGroup({
      sourceUrl,
      targetUrl,
      groupId: 'group-1',
      internalToken: token
    });
    assert.strictEqual(report.ok, true, JSON.stringify(report, null, 2));
    assert.strictEqual(report.source.messages.count, 7);
    assert.strictEqual(report.source.messages.firstSeq, 1);
    assert.strictEqual(report.source.messages.lastSeq, 7);
    assert.strictEqual(report.source.membershipPeriods, 2);
    assert.strictEqual(report.target.messages.count, 0);

    const broken = sequenceSummary([
      message(1),
      message(3),
      message(3)
    ]);
    assert.strictEqual(broken.gaps.length, 2);
    assert.deepStrictEqual(broken.duplicateSequences, [3]);
    console.log('group-cell-pilot-gate: passed');
  } finally {
    for (const child of services) {
      if (child.exitCode === null) child.kill();
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
    fs.rmSync(root, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  for (const child of services) {
    if (child.exitCode === null) child.kill();
  }
  process.exitCode = 1;
});
