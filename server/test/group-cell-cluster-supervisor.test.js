'use strict';

const assert = require('assert');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-cell-supervisor-'));
const statusFile = path.join(root, 'cluster-status.json');
const token = 'supervisor-token';
let supervisor = null;

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

async function waitFor(test, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const value = test();
      if (value) return value;
    } catch (_) { }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('condition timeout');
}

function readStatus() {
  return JSON.parse(fs.readFileSync(statusFile, 'utf8'));
}

async function main() {
  try {
    const ports = await Promise.all([freePort(), freePort()]);
    supervisor = spawn(process.execPath, [
      path.join(__dirname, '..', 'dev', 'group-cell-cluster.js'),
      '--cells', 'cell-a=' + ports[0] + ',cell-b=' + ports[1],
      '--data-root', path.join(root, 'cells'),
      '--route-db', path.join(root, 'routes.sqlite3'),
      '--status-file', statusFile,
      '--health-interval', '1000',
      '--internal-token', token
    ], {
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true
    });
    const logs = [];
    supervisor.stdout.on('data', (chunk) => logs.push(chunk.toString()));
    supervisor.stderr.on('data', (chunk) => logs.push(chunk.toString()));

    let status = await waitFor(() => {
      const current = readStatus();
      return current.cells.length === 2
        && current.cells.every((cell) => cell.healthy) ? current : null;
    }, 10000);
    const killed = status.cells.find((cell) => cell.cellId === 'cell-b');
    assert.ok(killed.pid > 0);
    process.kill(killed.pid);

    status = await waitFor(() => {
      const current = readStatus();
      const cell = current.cells.find((row) => row.cellId === 'cell-b');
      return cell && cell.restartCount >= 1 && cell.healthy && cell.pid > 0
        ? current : null;
    }, 15000);
    assert.ok(status.cells.every((cell) => cell.healthy));
    supervisor.kill();
    await new Promise((resolve) => supervisor.once('exit', resolve));
    console.log('group-cell-cluster-supervisor: passed');
  } catch (error) {
    throw new Error((error.stack || error) + '\n' + (supervisor && supervisor.spawnargs
      ? supervisor.spawnargs.join(' ') : ''));
  } finally {
    if (supervisor && supervisor.exitCode === null) supervisor.kill();
    await new Promise((resolve) => setTimeout(resolve, 300));
    fs.rmSync(root, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
