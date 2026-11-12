'use strict';

const crypto = require('crypto');

function canonical(value) {
  if (value === null || typeof value !== 'object') {
    return JSON.stringify(value === undefined ? null : value);
  }
  if (Array.isArray(value)) {
    return '[' + value.map(canonical).join(',') + ']';
  }
  return '{' + Object.keys(value).sort().map((key) =>
    JSON.stringify(key) + ':' + canonical(value[key])
  ).join(',') + '}';
}

function hash(value) {
  return crypto.createHash('sha256').update(canonical(value)).digest('hex');
}

function safeUser(user) {
  const row = user || {};
  return {
    id: row.id || '',
    username: row.username || '',
    nickname: row.nickname || '',
    avatar: row.avatar || '',
    bio: row.bio || '',
    gender: row.gender || '',
    bot: row.bot === true,
    banned: row.banned === true,
    createdAt: row.createdAt || '',
    tokenVersion: Number(row.tokenVersion) || 0
  };
}

function messageProjection(message) {
  const row = message || {};
  return {
    id: row.id || '',
    chatId: row.chatId || '',
    seq: Number(row.seq) || 0,
    senderId: row.senderId || '',
    kind: row.kind || '',
    clientId: row.clientId || '',
    createdAt: row.createdAt || '',
    editedAt: row.editedAt || '',
    recalled: row.recalled === true,
    burn: row.burn === true,
    seenAt: row.seenAt || 0,
    seenBy: Array.isArray(row.seenBy) ? row.seenBy.slice().sort() : [],
    contentHash: hash(row.content === undefined ? '' : row.content)
  };
}

function collection(rows, idOf, project) {
  return (rows || [])
    .filter(Boolean)
    .map((row) => {
      const id = String(idOf(row) || '');
      return id ? { id, hash: hash(project ? project(row) : row) } : null;
    })
    .filter(Boolean)
    .sort((a, b) => a.id.localeCompare(b.id));
}

function manifest(rows) {
  const entities = rows.slice().sort((a, b) => a.id.localeCompare(b.id));
  return {
    count: entities.length,
    hash: hash(entities)
  };
}

function buildStoreSets(data) {
  const input = data || {};
  const users = collection(input.users, (row) => row.id, safeUser);
  const friendships = collection(
    input.friendships,
    (row) => [String(row.fromId || ''), String(row.toId || '')].sort().join('|')
  );
  const chats = collection(input.chats, (row) => row.id);
  const reads = [];
  for (const ownerId of Object.keys(input.reads || {}).sort()) {
    for (const chatId of Object.keys(input.reads[ownerId] || {}).sort()) {
      reads.push({
        id: chatId + '|' + ownerId,
        hash: hash({
          ownerId,
          chatId,
          seq: Number(input.reads[ownerId][chatId]) || 0
        })
      });
    }
  }
  for (const ownerId of Object.keys(input.cleared || {}).sort()) {
    for (const chatId of Object.keys(input.cleared[ownerId] || {}).sort()) {
      reads.push({
        id: chatId + '|' + ownerId + '|cleared',
        hash: hash({
          ownerId,
          chatId,
          seq: Number(input.cleared[ownerId][chatId]) || 0,
          kind: 'cleared'
        })
      });
    }
  }
  const friendMeta = [];
  for (const ownerId of Object.keys(input.friendMeta || {}).sort()) {
    const byFriend = input.friendMeta[ownerId] || {};
    for (const targetId of Object.keys(byFriend).sort()) {
      friendMeta.push({
        id: ownerId + '|' + targetId,
        hash: hash(byFriend[targetId] || {})
      });
    }
  }
  const moments = collection(input.moments, (row) => row.id);
  const momentNoticeSeen = Object.keys(input.momentNoticeSeen || {}).sort().map((ownerId) => ({
    id: ownerId,
    hash: hash({ ownerId, seenAt: input.momentNoticeSeen[ownerId] || '' })
  }));
  const momentNotices = collection(input.momentNotices, (row) => row.id);
  const transfers = collection(input.transfers, (row) => row.id);
  const redpackets = collection(input.redpackets, (row) => row.id);
  const messageThreads = Object.keys(input.messages || {}).sort().map((chatId) => ({
    id: chatId,
    hash: hash((input.messages[chatId] || []).map(messageProjection))
  }));
  return {
    users,
    friendships,
    chats,
    reads: reads.sort((a, b) => a.id.localeCompare(b.id)),
    friendMeta: friendMeta.sort((a, b) => a.id.localeCompare(b.id)),
    moments,
    momentNoticeSeen: momentNoticeSeen.sort((a, b) => a.id.localeCompare(b.id)),
    momentNotices,
    transfers,
    redpackets,
    messageThreads
  };
}

class ShardSnapshotMirror {
  constructor(options) {
    this.gateway = options && options.gateway;
    if (!this.gateway) throw new Error('gateway is required');
    this.last = new Map();
    this.sets = new Map();
  }

  submit(entityType, entityId, digest, payload) {
    const entityKey = entityType + ':' + entityId;
    if (this.last.get(entityKey) === digest) {
      return { status: 'unchanged', entityType, entityId, hash: digest };
    }
    const result = this.gateway.submit({
      entityType,
      entityId,
      operation: 'snapshot',
      payload: payload || { hash: digest },
      eventId: 'snapshot:' + entityType + ':' + entityId + ':' + digest
    });
    if (result.status === 'applied' || result.status === 'duplicate') {
      this.last.set(entityKey, digest);
    }
    return Object.assign({}, result, { entityType, entityId, hash: digest });
  }

  captureSet(setName, rows, options) {
    const replace = !!(options && options.replace === true);
    if (!this.sets.has(setName) || replace) this.sets.set(setName, new Map());
    const tracked = this.sets.get(setName);
    const type = 'snapshot_' + setName;
    for (const row of rows || []) {
      tracked.set(row.id, row.hash);
      this.submit(type, row.id, row.hash, { hash: row.hash });
    }
    const completeRows = Array.from(tracked.entries()).map(([id, hashValue]) => ({
      id,
      hash: hashValue
    }));
    const summary = manifest(completeRows);
    return this.submit('snapshot_manifest', setName, summary.hash, summary);
  }

  captureStore(data) {
    const sets = buildStoreSets(data);
    const results = {};
    for (const setName of Object.keys(sets)) {
      results[setName] = this.captureSet(setName, sets[setName], { replace: true });
    }
    return results;
  }
}

function compareSnapshots(cluster, data) {
  const diffs = [];
  const sets = buildStoreSets(data || {});
  for (const setName of Object.keys(sets)) {
    const type = 'snapshot_' + setName;
    const rows = sets[setName];
    for (const row of rows) {
      const state = cluster.get(type, row.id);
      if (!state || state.deleted || !state.payload || state.payload.hash !== row.hash) {
        diffs.push({
          kind: 'snapshot-entity',
          set: setName,
          id: row.id
        });
      }
    }
    const expectedManifest = manifest(rows);
    const manifestState = cluster.get('snapshot_manifest', setName);
    const actualManifest = manifestState && !manifestState.deleted
      ? manifestState.payload || {}
      : {};
    if (actualManifest.count !== expectedManifest.count
        || actualManifest.hash !== expectedManifest.hash) {
      diffs.push({
        kind: 'snapshot-manifest',
        set: setName,
        expected: expectedManifest,
        actual: actualManifest
      });
    }
  }
  return diffs;
}

module.exports = {
  canonical,
  hash,
  buildStoreSets,
  compareSnapshots,
  ShardSnapshotMirror
};
