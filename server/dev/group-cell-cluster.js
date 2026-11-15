#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const { GroupCellRegistry } = require('../lib/group-cell-registry');

function arg(name, fallback) {
  const index = process.argv.indexOf('--' + name);
  return index >= 0 ? process.argv[index + 1] : fallback;
}

function parseCells(value) {
  const rows = [];
  String(value || '').split(',').forEach((entry) => {
    const raw = entry.trim();
    const split = raw.indexOf('=');
    if (split <= 0) return;
    const cellId = raw.slice(0, split).trim();
    const port = Math.floor(Number(raw.slice(split + 1)) || 0);
    if (!cellId || port <= 0 || port > 65535) {
      throw new Error('invalid cell definition: ' + raw);
    }
    rows.push({ cellId, port, baseUrl: 'http://127.0.0.1:' + port });
  });
  if (!rows.length) throw new Error('--cells is required');
  if (new Set(rows.map((row) => row.cellId)).size !== rows.length) {
    throw new Error('cell IDs must be unique');
  }
  if (new Set(rows.map((row) => row.port)).size !== rows.length) {
    throw new Error('cell ports must be unique');
  }
  return rows;
}

function writeJsonAtomic(file, value) {
  const temporary = file + '.' + process.pid + '.tmp';
  fs.writeFileSync(temporary, JSON.stringify(value, null, 2), 'utf8');
  fs.renameSync(temporary, file);
}

const specs = parseCells(arg('cells', ''));
const dataRoot = path.resolve(String(arg('data-root', '')));
const routeFile = path.resolve(String(arg('route-db', '')));
const statusFile = path.resolve(String(arg('status-file', '')));
const internalToken = String(
  arg('internal-token', process.env.GROUP_CELL_INTERNAL_TOKEN || '')
);
const registryInterval = Math.max(1000, Number(arg('health-interval', '2000')) || 2000);
if (!arg('data-root', '') || !arg('route-db', '') || !arg('status-file', '')) {
  throw new Error('--data-root, --route-db and --status-file are required');
}
fs.mkdirSync(dataRoot, { recursive: true });
fs.mkdirSync(path.dirname(routeFile), { recursive: true });
fs.mkdirSync(path.dirname(statusFile), { recursive: true });

const registry = new GroupCellRegistry({
  cells: specs.map((spec) => ({
    cellId: spec.cellId,
    baseUrl: spec.baseUrl,
    internalToken
  })),
  timeoutMs: 1200
});
const children = new Map();
const restartTimers = new Map();
let shuttingDown = false;
let statusTimer = null;

function logsFor(state, chunk) {
  String(chunk || '').split(/\r?\n/).filter(Boolean).forEach((line) => {
    state.logs.push(line.slice(0, 500));
    if (state.logs.length > 40) state.logs.shift();
  });
}

function spawnCell(spec) {
  let state = children.get(spec.cellId);
  if (!state) {
    state = {
      spec,
      child: null,
      pid: 0,
      restartCount: 0,
      state: 'starting',
      logs: []
    };
    children.set(spec.cellId, state);
  }
  const peerArgs = [];
  specs.forEach((peer) => {
    if (peer.cellId === spec.cellId) return;
    peerArgs.push('--peer', peer.cellId + '=' + peer.baseUrl);
  });
  const child = spawn(process.execPath, [
    path.join(__dirname, 'group-cell-server.js'),
    '--cell-id', spec.cellId,
    '--port', String(spec.port),
    '--data-dir', path.join(dataRoot, spec.cellId),
    '--route-db', routeFile,
    ...peerArgs
  ], {
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true,
    env: Object.assign({}, process.env, {
      GROUP_CELL_INTERNAL_TOKEN: internalToken
    })
  });
  state.child = child;
  state.pid = child.pid || 0;
  state.state = 'running';
  child.stdout.on('data', (chunk) => logsFor(state, chunk));
  child.stderr.on('data', (chunk) => logsFor(state, chunk));
  child.once('exit', (code, signal) => {
    state.state = 'exited';
    state.pid = 0;
    state.logs.push('exit code=' + code + ' signal=' + (signal || ''));
    if (state.logs.length > 40) state.logs.shift();
    if (shuttingDown) return;
    state.restartCount += 1;
    const delay = Math.min(10000, 500 * Math.pow(2, state.restartCount - 1));
    state.state = 'restarting';
    const timer = setTimeout(() => {
      restartTimers.delete(spec.cellId);
      if (!shuttingDown) spawnCell(spec);
    }, delay);
    timer.unref();
    restartTimers.set(spec.cellId, timer);
  });
}

function snapshot() {
  const health = new Map(registry.snapshot().cells.map((row) => [row.cellId, row]));
  return {
    version: 1,
    pid: process.pid,
    updatedAt: new Date().toISOString(),
    routeFile: path.basename(routeFile),
    cells: specs.map((spec) => {
      const state = children.get(spec.cellId);
      const healthState = health.get(spec.cellId) || {};
      return {
        cellId: spec.cellId,
        baseUrl: spec.baseUrl,
        pid: state ? state.pid : 0,
        processState: state ? state.state : 'stopped',
        restartCount: state ? state.restartCount : 0,
        healthy: healthState.healthy === true,
        latencyMs: Number(healthState.latencyMs) || 0,
        consecutiveFailures: Number(healthState.consecutiveFailures) || 0,
        lastError: String(healthState.lastError || ''),
        logs: state ? state.logs.slice() : []
      };
    })
  };
}

function writeStatus() {
  writeJsonAtomic(statusFile, snapshot());
}

function shutdown() {
  if (shuttingDown) return;
  shuttingDown = true;
  registry.stop();
  if (statusTimer) clearInterval(statusTimer);
  for (const timer of restartTimers.values()) clearTimeout(timer);
  restartTimers.clear();
  for (const state of children.values()) {
    if (state.child && state.child.exitCode === null) state.child.kill();
  }
  writeStatus();
  setTimeout(() => process.exit(0), 250).unref();
}

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

specs.forEach(spawnCell);
registry.start(registryInterval);
statusTimer = setInterval(writeStatus, 1000);
statusTimer.unref();
writeStatus();
process.stdout.write(JSON.stringify({
  ready: true,
  pid: process.pid,
  cells: specs,
  statusFile
}) + '\n');
