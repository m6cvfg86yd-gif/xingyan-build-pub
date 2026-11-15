#!/usr/bin/env node
'use strict';

const http = require('http');
const path = require('path');
const { GroupMessageCell } = require('../lib/group-message-cell');
const { GroupRouteStore } = require('../lib/group-route-store');
const { GroupCellRouter } = require('../lib/group-cell-router');

function arg(name, fallback) {
  const index = process.argv.indexOf('--' + name);
  return index >= 0 ? process.argv[index + 1] : fallback;
}

function peers() {
  const out = {};
  process.argv.forEach((value, index) => {
    if (value !== '--peer') return;
    const raw = String(process.argv[index + 1] || '');
    const split = raw.indexOf('=');
    if (split <= 0) return;
    out[raw.slice(0, split)] = raw.slice(split + 1).replace(/\/+$/, '');
  });
  return out;
}

async function body(req) {
  const chunks = [];
  for await (const chunk of req) {
    chunks.push(chunk);
    if (Buffer.concat(chunks).length > 16 * 1024 * 1024) {
      throw new Error('request body too large');
    }
  }
  const text = Buffer.concat(chunks).toString('utf8');
  return text ? JSON.parse(text) : {};
}

function reply(res, status, value) {
  const text = JSON.stringify(value);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(text)
  });
  res.end(text);
}

const cellId = String(arg('cell-id', ''));
const port = Number(arg('port'));
const dataDir = path.resolve(String(arg('data-dir', '')));
const routeFile = path.resolve(String(arg('route-db', '')));
if (!cellId || !Number.isInteger(port) || !dataDir || !routeFile) {
  throw new Error('cell-id, port, data-dir and route-db are required');
}

const realtime = {
  async notifyUser() {},
  async publishGroupSignal() {}
};
const pushQueue = {
  async enqueueUser() {},
  async enqueuePartition() {}
};
const cell = new GroupMessageCell({
  cellId,
  dataDir,
  realtime,
  pushQueue,
  presence: null,
  largeGroupThreshold: Number(arg('large-threshold', '500')),
  pushPartitionSize: Number(arg('push-partition', '1000')),
  schedule: (work) => setImmediate(work)
});
const routeStore = new GroupRouteStore({ databaseFile: routeFile });
const router = new GroupCellRouter({
  cells: { [cellId]: cell },
  routeStore
});
const peerUrls = peers();

async function mirrorToTarget(groupId, route, senderId, message) {
  const target = String(route.targetCellId || '');
  const base = peerUrls[target];
  if (!target || !base) {
    return { ok: false, error: 'target-peer-unavailable', target };
  }
  try {
    const response = await fetch(base + '/internal/groups/'
      + encodeURIComponent(groupId) + '/mirror', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        epoch: route.epoch,
        senderId,
        message
      })
    });
    return await response.json();
  } catch (error) {
    return { ok: false, error: String(error && error.message || error) };
  }
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://localhost');
    const parts = url.pathname.split('/').filter(Boolean);
    if (url.pathname === '/internal/health') {
      return reply(res, 200, {
        ok: true,
        cellId,
        stats: cell.stats(),
        routes: routeStore.get('') ? 0 : undefined
      });
    }
    if (parts[0] !== 'internal' || parts[1] !== 'groups' || !parts[2]) {
      return reply(res, 404, { ok: false, error: 'not found' });
    }
    const groupId = decodeURIComponent(parts[2]);
    const action = parts[3] || '';
    if (req.method === 'POST' && action === 'join') {
      const input = await body(req);
      cell.join(groupId, input.userId, input.joinedSeq);
      return reply(res, 200, { ok: true });
    }
    if (req.method === 'POST' && action === 'leave') {
      const input = await body(req);
      cell.leave(groupId, input.userId, input.leftSeq);
      return reply(res, 200, { ok: true });
    }
    if (req.method === 'POST' && action === 'mirror') {
      const input = await body(req);
      const route = router.route(groupId);
      if (!route || route.status !== 'migrating'
          || route.targetCellId !== cellId
          || Number(route.epoch) !== Number(input.epoch)) {
        return reply(res, 409, { ok: false, error: 'mirror-fenced', route });
      }
      const result = await cell.mirror(
        groupId,
        input.senderId,
        input.message,
        { fanout: false }
      );
      return reply(res, result.ok ? 200 : 409, result);
    }
    if (req.method === 'GET' && action === 'export-metadata') {
      return reply(res, 200, {
        ok: true,
        groupId,
        membership: cell.membership.listPeriods(groupId),
        deletions: cell.deletions.exportGroup(groupId),
        cursors: cell.reliability.exportDeviceCursors(groupId)
      });
    }
    if (req.method === 'POST' && action === 'import-metadata') {
      const input = await body(req);
      const route = router.route(groupId);
      if (!route || route.status !== 'migrating'
          || route.targetCellId !== cellId
          || Number(route.epoch) !== Number(input.epoch)) {
        return reply(res, 409, { ok: false, error: 'metadata-fenced', route });
      }
      let membership = 0;
      for (const period of input.membership || []) {
        if (cell.membership.importPeriod(period)) membership += 1;
      }
      const deletions = cell.deletions.importGroup(groupId, input.deletions || {});
      const cursors = cell.reliability.importDeviceCursors(input.cursors || []);
      return reply(res, 200, {
        ok: true,
        imported: { membership, deletions, cursors }
      });
    }
    if (req.method === 'GET' && action === 'message-page') {
      const afterSeq = Number(url.searchParams.get('afterSeq')) || 0;
      const limit = Math.max(1, Math.min(500, Number(url.searchParams.get('limit')) || 500));
      const messages = cell.reliability.messagesAfter(groupId, afterSeq, limit);
      return reply(res, 200, {
        ok: true,
        messages,
        lastSeq: messages.length ? Number(messages[messages.length - 1].seq) : afterSeq,
        hasMore: messages.length === limit
      });
    }
    if (req.method === 'POST' && action === 'messages') {
      const input = await body(req);
      const owner = router.checkOwner(groupId, cellId);
      if (!owner.ok) {
        return reply(res, 409, { ok: false, error: owner.reason, route: owner.route });
      }
      const result = await cell.send(groupId, input.senderId, input.message);
      if (result.ok && owner.route.status === 'migrating') {
        result.dualWrite = await mirrorToTarget(
          groupId,
          owner.route,
          input.senderId,
          result.message
        );
      }
      return reply(res, result.ok ? 200 : 422, result);
    }
    if (req.method === 'GET' && action === 'messages') {
      const owner = router.checkOwner(groupId, cellId);
      if (!owner.ok) {
        return reply(res, 409, {
          ok: false,
          error: owner.reason,
          route: owner.route,
          messages: []
        });
      }
      const result = await cell.read({
        groupId,
        userId: String(url.searchParams.get('userId') || ''),
        afterSeq: Number(url.searchParams.get('afterSeq')) || 0,
        limit: Number(url.searchParams.get('limit')) || 200
      });
      return reply(res, result.ok ? 200 : 403, result);
    }
    if (req.method === 'GET' && action === 'debug-read') {
      const result = await cell.read({
        groupId,
        userId: String(url.searchParams.get('userId') || ''),
        afterSeq: Number(url.searchParams.get('afterSeq')) || 0,
        limit: Number(url.searchParams.get('limit')) || 200
      });
      return reply(res, result.ok ? 200 : 403, result);
    }
    if (req.method === 'POST' && (action === 'ack' || action === 'read-cursor')) {
      const input = await body(req);
      const owner = router.checkOwner(groupId, cellId);
      if (!owner.ok) return reply(res, 409, { ok: false, error: owner.reason });
      const advanced = action === 'ack'
        ? cell.acknowledge(groupId, input.userId, input.deviceId, input.seq)
        : cell.markRead(groupId, input.userId, input.deviceId, input.seq);
      return reply(res, 200, { ok: true, advanced });
    }
    if (req.method === 'POST' && ['hide', 'clear', 'recall', 'takedown'].includes(action)) {
      const input = await body(req);
      const owner = router.checkOwner(groupId, cellId);
      if (!owner.ok) return reply(res, 409, { ok: false, error: owner.reason });
      let result;
      if (action === 'hide') {
        result = cell.hideForUser(groupId, input.userId, input.messageId);
      } else if (action === 'clear') {
        result = cell.clearForUser(groupId, input.userId, input.seq);
      } else if (action === 'recall') {
        result = cell.recall(groupId, input.messageId, input.seq, input.actorUserId);
      } else {
        result = cell.takedown(
          groupId,
          input.messageId,
          input.seq,
          input.actorUserId,
          input.reason
        );
      }
      return reply(res, 200, { ok: true, result });
    }
    return reply(res, 404, { ok: false, error: 'not found' });
  } catch (error) {
    return reply(res, 500, {
      ok: false,
      error: String(error && error.message || error)
    });
  }
});

function shutdown() {
  server.close(() => {
    try { cell.close(); } catch (_) { }
    try { routeStore.close(); } catch (_) { }
    process.exit(0);
  });
}

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
server.listen(port, '127.0.0.1', () => {
  process.stdout.write(JSON.stringify({
    ready: true,
    cellId,
    port,
    dataDir
  }) + '\n');
});
