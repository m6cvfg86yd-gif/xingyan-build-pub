'use strict';

const fs = require('fs');
const path = require('path');

const USER_AUTHORITY = new Set([
  'users.json', 'friendmeta.json', 'friend-removals.json',
  'security-audit.jsonl', 'logins.json', 'login-devices.json',
  'banrow-snapshots', 'friendrow-snapshots', 'userrow-snapshots'
]);
const CHAT_AUTHORITY = new Set([
  'chats.json', 'reads.json', 'delivered.json', 'face-rooms.json',
  'chatrow-snapshots', 'readrow-snapshots'
]);
const MOMENT_AUTHORITY = new Set([
  'moments.json', 'moments-log.jsonl', 'moment-notices.json',
  'moment-views.json'
]);
const PAYMENT_AUTHORITY = new Set([
  'transfers.json', 'redpackets.json', 'payment-ledger-state.json',
  'payment-ledger.json', 'money-journal.jsonl', 'money-state.json',
  'biz.json', 'ledger.json', 'ledger-manual.json', 'wallet-ops.json',
  'wallet-rules.json', 'orders.json', 'payment-token-vault.json',
  'payment-intents.jsonl', 'idem.json', 'aml.json', 'aml-events.jsonl'
]);
const MUSIC = new Set(['music.json', 'music-now.json', 'redpacket-covers.json']);
const GAME = new Set(['games.json', 'game-scores.json', 'miniapps.json']);
const DERIVED = new Set([
  'shards', 'shards-6-final', 'shards-6-from-7', 'shards-source-7',
  'shards.7stage-20261024-091559', 'shards.bak-2core-20261014-062351',
  'shards.bak-2core-20261014-062442', 'shards.bak-2core-20261014-084244',
  'shards.bak-2core-20261014-084332',
  'shards.legacy-2shard-20261021-223235',
  'shards.6pre7-20261024-091213', 'shards.6pre7-20261024-091601'
]);
const OBJECT_DIRS = new Set([
  'uploads', 'hls', 'game-backups', 'retired-games', 'uploads-stage-partial'
]);
const ARCHIVE_PATTERN = /(?:\.bak(?:-|$)|\.tmp$|\.reviewbak$|\.BROKEN-|backup)/i;
const LOG_PATTERN = /(?:\.log$|\.jsonl$|^audit\.|^metrics-|^push-log|^feedback|^client-errors|^daily-active|^monitor-|^alerts|^support-tickets)/i;

function classifyPath(relative) {
  const rel = String(relative || '').replace(/\\/g, '/');
  const parts = rel.split('/');
  const base = parts[0];
  const name = parts[parts.length - 1];
  if (parts.length > 1) {
    if (base === 'messages') return { placement: 'chat-shard', domain: 'messages' };
    if (OBJECT_DIRS.has(base)) return { placement: 'object-store', domain: 'media' };
    if (USER_AUTHORITY.has(base)) return { placement: 'user-shard', domain: 'user-derived' };
    if (CHAT_AUTHORITY.has(base)) return { placement: 'chat-shard', domain: 'chat-derived' };
    if (DERIVED.has(base) || ARCHIVE_PATTERN.test(base)) {
      return { placement: 'derived-rebuild', domain: 'derived' };
    }
    return { placement: 'unclassified', domain: 'unknown-directory' };
  }
  if (ARCHIVE_PATTERN.test(name)) return { placement: 'archive', domain: 'historical' };
  if (USER_AUTHORITY.has(name)) return { placement: 'user-shard', domain: 'profile' };
  if (CHAT_AUTHORITY.has(name)) return { placement: 'chat-shard', domain: 'chat' };
  if (MOMENT_AUTHORITY.has(name)) return { placement: 'moment-shard', domain: 'moment' };
  if (PAYMENT_AUTHORITY.has(name)) return { placement: 'payment-authority', domain: 'payment' };
  if (MUSIC.has(name)) return { placement: 'global-replicated', domain: 'music' };
  if (GAME.has(name)) return { placement: 'global-replicated', domain: 'game' };
  if (LOG_PATTERN.test(name)) return { placement: 'global-log', domain: 'operations' };
  if (/\.(key|pem)$/i.test(name)) return { placement: 'secret-authority', domain: 'secret' };
  return { placement: 'global-replicated', domain: 'configuration' };
}

function walk(root, prefix) {
  const out = [];
  for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
    const full = path.join(root, entry.name);
    const rel = prefix ? prefix + '/' + entry.name : entry.name;
    if (entry.isDirectory()) out.push(...walk(full, rel));
    else if (entry.isFile()) out.push({ full, rel });
  }
  return out;
}

function classifyDirectory(name) {
  const base = String(name || '');
  if (base === 'messages') return { placement: 'chat-shard', domain: 'messages' };
  if (/^messages[-.]/.test(base)) {
    return { placement: 'derived-rebuild', domain: 'message-derived' };
  }
  if (OBJECT_DIRS.has(base)) return { placement: 'object-store', domain: 'media' };
  if (USER_AUTHORITY.has(base)) return { placement: 'user-shard', domain: 'user-derived' };
  if (CHAT_AUTHORITY.has(base)) return { placement: 'chat-shard', domain: 'chat-derived' };
  if (base === 'device-rows') return { placement: 'user-shard', domain: 'device-profile' };
  if (base === '_archive') return { placement: 'archive', domain: 'historical' };
  if (base === 'data' || /^shards(?:$|[.-])/.test(base)) {
    return { placement: 'derived-rebuild', domain: 'derived' };
  }
  if (DERIVED.has(base) || ARCHIVE_PATTERN.test(base)) {
    return { placement: 'derived-rebuild', domain: 'derived' };
  }
  return null;
}

function buildPlacementReportFromEntries(entries, options) {
  const rows = (entries || []).map((entry) => {
    const relative = String(entry.path || entry.rel || '').replace(/\\/g, '/');
    const isDirectory = entry.directory === true || relative.endsWith('/');
    const category = isDirectory
      ? (classifyDirectory(relative.replace(/\/+$/, '')) || classifyPath(relative))
      : classifyPath(relative);
    return Object.assign({
      path: relative,
      bytes: Number(entry.bytes || entry.size) || 0,
      directory: isDirectory
    }, category);
  });
  const byPlacement = {};
  const byDomain = {};
  for (const row of rows) {
    const p = byPlacement[row.placement] ||
      (byPlacement[row.placement] = { files: 0, bytes: 0 });
    p.files += 1;
    p.bytes += row.bytes;
    const d = byDomain[row.domain] ||
      (byDomain[row.domain] = { files: 0, bytes: 0 });
    d.files += 1;
    d.bytes += row.bytes;
  }
  const unclassified = rows.filter((row) => row.placement === 'unclassified');
  return {
    version: 1,
    ok: unclassified.length === 0,
    files: rows.length,
    bytes: rows.reduce((sum, row) => sum + row.bytes, 0),
    shallowKnownDirectories: !!(options && options.shallowKnownDirectories),
    byPlacement,
    byDomain,
    unclassified: unclassified.slice(0, 500),
    rows
  };
}

function buildPlacementReport(dataDir, options) {
  const root = path.resolve(String(dataDir || ''));
  if (!root) throw new Error('dataDir is required');
  const rows = [];
  const byPlacement = {};
  const byDomain = {};
  const shallowKnownDirectories = !!(options && options.shallowKnownDirectories);
  const entries = [];
  for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
    const full = path.join(root, entry.name);
    if (entry.isDirectory() && shallowKnownDirectories) {
      const category = classifyDirectory(entry.name);
      if (category) {
        entries.push({
          full,
          rel: entry.name + '/',
          directory: true,
          category
        });
        continue;
      }
    }
    if (entry.isDirectory()) {
      entries.push(...walk(full, entry.name).map((row) => ({
        full: row.full,
        rel: row.rel
      })));
    } else if (entry.isFile()) {
      entries.push({ full, rel: entry.name });
    }
  }
  for (const entry of entries) {
    const stat = fs.statSync(entry.full);
    const category = entry.category || classifyPath(entry.rel);
    const row = Object.assign({
      path: entry.rel,
      bytes: entry.directory ? 0 : stat.size,
      directory: !!entry.directory
    }, category);
    rows.push(row);
    const p = byPlacement[row.placement] ||
      (byPlacement[row.placement] = { files: 0, bytes: 0 });
    p.files += 1;
    p.bytes += stat.size;
    const d = byDomain[row.domain] ||
      (byDomain[row.domain] = { files: 0, bytes: 0 });
    d.files += 1;
    d.bytes += stat.size;
  }
  const unclassified = rows.filter((row) => row.placement === 'unclassified');
  return {
    version: 1,
    ok: unclassified.length === 0,
    dataDirName: path.basename(root),
    files: rows.length,
    bytes: rows.reduce((sum, row) => sum + row.bytes, 0),
    shallowKnownDirectories,
    byPlacement,
    byDomain,
    unclassified: unclassified.slice(0, 500),
    rows
  };
}

module.exports = {
  classifyPath,
  classifyDirectory,
  buildPlacementReport,
  buildPlacementReportFromEntries
};
