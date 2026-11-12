'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { PaymentLedger } = require('../payment-ledger');
const { stableShard, routingKey } = require('./shard-runtime');
const { canonical, hash } = require('./shard-snapshot');

function readJson(file, fallback) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); }
  catch (_) { return fallback; }
}

function fileDigest(file) {
  const data = fs.readFileSync(file);
  return {
    size: data.length,
    sha256: crypto.createHash('sha256').update(data).digest('hex')
  };
}

function secureKey(secret, name) {
  return crypto.createHmac('sha256', String(secret || '')).update('store:' + name).digest();
}

function openSecureValue(secret, name, value) {
  if (!value || typeof value !== 'object' || value.enc !== 1) return value;
  const decipher = crypto.createDecipheriv(
    'aes-256-gcm',
    secureKey(secret, name),
    Buffer.from(String(value.iv || ''), 'base64')
  );
  decipher.setAAD(Buffer.from('store:' + name, 'utf8'));
  decipher.setAuthTag(Buffer.from(String(value.tag || ''), 'base64'));
  const plain = Buffer.concat([
    decipher.update(Buffer.from(String(value.ct || ''), 'base64')),
    decipher.final()
  ]);
  return JSON.parse(plain.toString('utf8'));
}

function messageKey(secret, chatId) {
  return crypto.createHmac('sha256', String(secret || '')).update('msg:' + chatId).digest();
}

function openMessage(secret, chatId, line) {
  const stored = JSON.parse(line);
  if (!stored || stored.e !== 1) return stored;
  const decipher = crypto.createDecipheriv(
    'aes-256-gcm',
    messageKey(secret, chatId),
    Buffer.from(String(stored.iv || ''), 'base64')
  );
  decipher.setAuthTag(Buffer.from(String(stored.tag || ''), 'base64'));
  const plain = Buffer.concat([
    decipher.update(Buffer.from(String(stored.ct || ''), 'base64')),
    decipher.final()
  ]);
  return JSON.parse(plain.toString('utf8'));
}

function walkFiles(root, prefix) {
  const out = [];
  let entries = [];
  try { entries = fs.readdirSync(root, { withFileTypes: true }); }
  catch (_) { return out; }
  for (const entry of entries) {
    const full = path.join(root, entry.name);
    const rel = prefix ? prefix + '/' + entry.name : entry.name;
    if (entry.isDirectory()) out.push(...walkFiles(full, rel));
    else if (entry.isFile()) out.push({ full, rel });
  }
  return out;
}

function category(rows, idOf) {
  const normalized = (rows || []).map((row) => ({
    id: String(idOf(row) || ''),
    hash: hash(row)
  })).sort((a, b) => a.id.localeCompare(b.id));
  return {
    count: normalized.length,
    hash: hash(normalized)
  };
}

function assignment(count, rows, type, idOf) {
  const byShard = Array.from({ length: count }, () => 0);
  for (const row of rows || []) {
    const id = String(idOf(row) || '');
    if (!id) continue;
    const key = routingKey(type, id);
    const shard = type === 'transfer' ? 0 : stableShard(type + ':' + key, count);
    byShard[shard] += 1;
  }
  return byShard;
}

function inventoryData(options) {
  const opts = options || {};
  const dataDir = path.resolve(String(opts.dataDir || ''));
  if (!dataDir) throw new Error('dataDir is required');
  const secret = opts.secret || '';
  const issues = [];
  const issue = (kind, message, id) => {
    if (issues.length < 2000) issues.push({ kind, id: id || '', message });
  };
  const json = (name, fallback) => readJson(path.join(dataDir, name), fallback);
  const store = (name, fallback) => openSecureValue(
    secret,
    name,
    json(name, fallback)
  );

  const users = (json('users.json', { users: [] }).users || []);
  const friendships = (json('friendships.json', { friendships: [] }).friendships || []);
  const chats = (json('chats.json', { chats: [] }).chats || []);
  const readsStore = json('reads.json', { reads: {}, cleared: {} });
  const friendMetaRaw = json('friendmeta.json', { byOwner: {} });
  const friendMeta = friendMetaRaw.byOwner || {};
  const moments = (json('moments.json', { moments: [] }).moments || []);
  const noticeStore = json('moment-notices.json', { items: [], seen: {} });
  const transfers = (store('transfers.json', { transfers: [] }).transfers || []);
  const redpackets = (store('redpackets.json', { redpackets: [] }).redpackets || []);
  const paymentTokens = (json('payment-token-vault.json', { tokens: [] }).tokens || []);
  const userIds = new Set(users.map((row) => row.id));
  const chatIds = new Set(chats.map((row) => row.id));
  const messageByChat = {};
  const allMessages = [];
  const uploadReferences = new Set();
  const messagesDir = path.join(dataDir, 'messages');
  let messageFiles = [];
  try { messageFiles = fs.readdirSync(messagesDir).filter((name) => name.endsWith('.jsonl')); }
  catch (_) { messageFiles = []; }
  for (const name of messageFiles.sort()) {
    const chatId = name.slice(0, -'.jsonl'.length);
    if (!chatIds.has(chatId)) issue('orphan-message-file', 'message file has no chat', chatId);
    const file = path.join(messagesDir, name);
    const lines = fs.readFileSync(file, 'utf8').split('\n').filter((line) => line.trim());
    const rows = [];
    const seqs = new Set();
    for (let index = 0; index < lines.length; index += 1) {
      let message;
      try { message = openMessage(secret, chatId, lines[index]); }
      catch (_) {
        issue('message-decrypt', 'message could not be decrypted', chatId + ':' + (index + 1));
        continue;
      }
      if (!message || !message.id) {
        issue('message-invalid', 'message has no id', chatId + ':' + (index + 1));
        continue;
      }
      const seq = Number(message.seq);
      if (!Number.isFinite(seq) || seq <= 0) issue('message-seq', 'invalid message seq', message.id);
      if (seqs.has(seq)) issue('message-seq-duplicate', 'duplicate seq', chatId + ':' + seq);
      seqs.add(seq);
      if (message.senderId && !userIds.has(message.senderId)) {
        issue('message-sender', 'sender does not exist', message.senderId);
      }
      const content = String(message.content || '');
      const matches = content.match(/\/uploads\/[A-Za-z0-9._-]+/g) || [];
      matches.forEach((value) => uploadReferences.add(value.replace(/^\/uploads\//, '')));
      rows.push(message);
      allMessages.push(Object.assign({ chatId }, message));
    }
    messageByChat[chatId] = rows;
  }

  for (const row of users) {
    if (!row.id) issue('user-invalid', 'user has no id');
  }
  for (const row of friendships) {
    if (!userIds.has(row.fromId) || !userIds.has(row.toId)) {
      issue('friendship-user', 'friendship references missing user', row.id);
    }
  }
  for (const chat of chats) {
    const members = Array.isArray(chat.memberIds) ? chat.memberIds : [];
    for (const userId of members) {
      if (!userIds.has(userId)) issue('chat-member', 'chat member does not exist', chat.id + ':' + userId);
    }
    if (chat.type === 'direct' && members.length !== 2) {
      issue('direct-member-count', 'direct chat must have two members', chat.id);
    }
    if (chat.ownerId && !members.includes(chat.ownerId)) {
      issue('group-owner', 'owner is not a member', chat.id);
    }
  }
  for (const moment of moments) {
    if (moment.authorId && !userIds.has(moment.authorId)) {
      issue('moment-author', 'moment author does not exist', moment.id);
    }
    for (const comment of moment.comments || []) {
      if (comment.userId && !userIds.has(comment.userId)) {
        issue('comment-user', 'comment user does not exist', moment.id + ':' + comment.id);
      }
    }
  }
  for (const transfer of transfers) {
    if (!userIds.has(transfer.fromId) || (transfer.toId && !userIds.has(transfer.toId))) {
      issue('transfer-user', 'transfer references missing user', transfer.id);
    }
    if (transfer.chatId && !chatIds.has(transfer.chatId)) {
      issue('transfer-chat', 'transfer references missing chat', transfer.id);
    }
  }
  for (const token of paymentTokens) {
    if (!userIds.has(token.userId)) issue('payment-token-user', 'token user missing', token.tokenId);
  }

  const uploads = [];
  const uploadDir = path.join(dataDir, 'uploads');
  for (const entry of walkFiles(uploadDir, '')) {
    const digest = fileDigest(entry.full);
    uploads.push({
      path: entry.rel.replace(/\\/g, '/'),
      size: digest.size,
      sha256: digest.sha256,
      referenced: uploadReferences.has(entry.rel.replace(/\\/g, '/'))
        || uploadReferences.has(path.basename(entry.rel))
    });
  }
  for (const ref of uploadReferences) {
    if (!uploads.some((row) => row.path === ref || path.basename(row.path) === ref)) {
      issue('upload-missing', 'message references a missing upload', ref);
    }
  }

  const paymentJournalName = 'money-journal.jsonl';
  const paymentJournal = path.join(dataDir, paymentJournalName);
  let ledgerCheck = { available: false };
  if (fs.existsSync(paymentJournal) && secret) {
    const secureState = {};
    const readState = (name, fallback) => secureState[name] || fallback;
    const writeState = () => {};
    const ledger = new PaymentLedger({
      dataDir,
      journalName: paymentJournalName,
      stateName: 'payment-ledger-state.json',
      openSealed: (name, value) => openSecureValue(secret, name, value),
      sealValue: () => { throw new Error('inventory is read-only'); },
      readState: (name, fallback) => openSecureValue(
        secret,
        name,
        json(name, fallback)
      ),
      writeState,
      hmac: (payload) => crypto.createHmac('sha256', secret)
        .update('payment-ledger|' + payload).digest('hex'),
      uid: (prefix) => prefix + '-inventory',
      now: () => new Date().toISOString()
    });
    ledgerCheck = {
      available: true,
      integrity: ledger.verifyIntegrity(),
      entries: ledger.entriesForUser ? ledger.readEntries().length : 0
    };
    if (!ledgerCheck.integrity.ok) issue('payment-ledger', 'ledger integrity failed', paymentJournalName);
  }

  const files = [];
  const rootFiles = fs.readdirSync(dataDir, { withFileTypes: true })
    .filter((entry) => entry.isFile())
    .map((entry) => entry.name)
    .sort();
  for (const name of rootFiles) {
    const digest = fileDigest(path.join(dataDir, name));
    files.push({ path: name, size: digest.size, sha256: digest.sha256 });
  }

  const categoryRows = {
    users: [users, (row) => row.id],
    friendships: [friendships, (row) => [row.fromId, row.toId].sort().join('|')],
    chats: [chats, (row) => row.id],
    moments: [moments, (row) => row.id],
    momentNotices: [noticeStore.items || [], (row) => row.id],
    transfers: [transfers, (row) => row.id],
    redpackets: [redpackets, (row) => row.id]
  };
  const manifests = {};
  const shardPreview = {};
  for (const [name, pair] of Object.entries(categoryRows)) {
    manifests[name] = category(pair[0], pair[1]);
    const type = name === 'users' ? 'user' : name;
    shardPreview[name] = {
      shards6: assignment(6, pair[0], type, pair[1]),
      shards7: assignment(7, pair[0], type, pair[1])
    };
  }
  manifests.messages = category(allMessages, (row) => row.chatId + '|' + row.id);
  manifests.uploads = category(uploads, (row) => row.path);
  shardPreview.messages = {
    shards6: assignment(6, allMessages, 'chat', (row) => row.chatId),
    shards7: assignment(7, allMessages, 'chat', (row) => row.chatId)
  };

  return {
    version: 1,
    baselineDate: String(opts.baselineDate || ''),
    generatedAt: new Date().toISOString(),
    sourceId: String(opts.sourceId || ''),
    secretAvailable: !!secret,
    ok: issues.length === 0,
    dataDirName: path.basename(dataDir),
    counts: Object.fromEntries(Object.entries(manifests).map(([key, row]) => [key, row.count])),
    messageThreads: messageFiles.length,
    uploadBytes: uploads.reduce((sum, row) => sum + row.size, 0),
    manifests,
    shardPreview,
    ledger: ledgerCheck,
    issues,
    files
  };
}

module.exports = {
  openSecureValue,
  openMessage,
  inventoryData
};
