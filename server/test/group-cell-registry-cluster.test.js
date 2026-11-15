'use strict';

const assert = require('assert');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');
const { GroupCellRegistry } = require('../lib/group-cell-registry');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-cell-cluster-'));
const routeFile = path.join(root, 'routes.sqlite3');
const token = 'cluster-token';
const processes = new Map();

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
  processes.set(cellId, child);
  const logs = [];
  child.stdout.on('data', (chunk) => logs.push(chunk.toString()));
  child.stderr.on('data', (chunk) => logs.push(chunk.toString()));
  const baseUrl = 'http://127.0.0.1:' + port;
  for (let index = 0; index < 120; index += 1) {
    if (child.exitCode !== null) throw new Error(logs.join(''));
    try {
      if ((await fetch(baseUrl + '/internal/health')).ok) return baseUrl;
    } catch (_) { }
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  throw new Error('cell start timeout: ' + cellId);
}

async function stopCell(cellId) {
  const child = processes.get(cellId);
  if (!child || child.exitCode !== null) return;
  child.kill();
  await new Promise((resolve) => {
    const timer = setTimeout(resolve, 2000);
    child.once('exit', () => {
      clearTimeout(timer);
      resolve();
    });
  });
}

async function main() {
  const ports = await Promise.all([freePort(), freePort(), freePort()]);
  const cellIds = ['cell-a', 'cell-b', 'cell-c'];
  try {
    const urls = [];
    for (let index = 0; index < cellIds.length; index += 1) {
      urls.push(await startCell(cellIds[index], ports[index]));
    }
    const registry = new GroupCellRegistry({
      cells: cellIds.map((cellId, index) => ({
        cellId,
        baseUrl: urls[index],
        internalToken: token,
        capacityWeight: 100
      }))
    });

    let snapshot = await registry.checkAll();
    assert.deepStrictEqual(snapshot.cells.map((cell) => cell.healthy), [true, true, true]);

    await stopCell('cell-b');
    const before = registry.select('group-before-failure', 20);
    assert.ok(before);
    snapshot = await registry.checkAll();
    assert.deepStrictEqual(snapshot.cells.map((cell) => cell.healthy), [true, false, true]);
    const after = registry.select('group-after-failure', 20);
    assert.ok(after);
    assert.notStrictEqual(after.cellId, 'cell-b');

    await startCell('cell-b', ports[1]);
    snapshot = await registry.checkAll();
    assert.deepStrictEqual(snapshot.cells.map((cell) => cell.healthy), [true, true, true]);

    registry.setUsedWeight('cell-b', 100);
    assert.strictEqual(registry.get('cell-b', {
      requireHealthy: true,
      requireCapacity: true
    }), null);
    const capacityAware = registry.select('group-capacity', 20);
    assert.ok(capacityAware);
    assert.notStrictEqual(capacityAware.cellId, 'cell-b');
    console.log('group-cell-registry-cluster: passed');
  } finally {
    for (const cellId of Array.from(processes.keys())) {
      await stopCell(cellId);
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
    fs.rmSync(root, { recursive: true, force: true });
  }
}

main().catch(async (error) => {
  console.error(error.stack || error);
  for (const cellId of Array.from(processes.keys())) {
    await stopCell(cellId);
  }
  process.exitCode = 1;
});
