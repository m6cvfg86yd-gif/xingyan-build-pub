'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { inventoryData } = require('../lib/shard-data-inventory');
const { createSecurityVault } = require('../lib/security-vault');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-data-inventory-'));

try {
  const data = path.join(root, 'data');
  fs.mkdirSync(path.join(data, 'messages'), { recursive: true });
  fs.mkdirSync(path.join(data, 'uploads'), { recursive: true });
  fs.mkdirSync(path.join(root, 'public', 'bg'), { recursive: true });
  fs.writeFileSync(path.join(data, 'users.json'), JSON.stringify({
    users: [{
      id: 'u1',
      chatBackground: '/uploads/photo.jpg',
      chatBackgrounds: { c1: '/bg/w1.jpg' }
    }, { id: 'u2' }]
  }));
  fs.writeFileSync(path.join(data, 'friendships.json'), JSON.stringify({
    friendships: [{ id: 'f1', fromId: 'u1', toId: 'u2', status: 'accepted' }]
  }));
  fs.writeFileSync(path.join(data, 'chats.json'), JSON.stringify({
    chats: [{
      id: 'c1',
      type: 'direct',
      memberIds: ['u1', 'u2'],
      ownerId: 'u1'
    }]
  }));
  fs.writeFileSync(path.join(data, 'reads.json'), JSON.stringify({
    reads: { u1: { c1: 1 } },
    cleared: {}
  }));
  fs.writeFileSync(path.join(data, 'moments.json'), JSON.stringify({
    moments: [{ id: 'm1', authorId: 'u1', comments: [] }]
  }));
  fs.writeFileSync(path.join(data, 'moment-notices.json'), JSON.stringify({
    items: [], seen: {}
  }));
  fs.writeFileSync(path.join(data, 'delivered.json'), JSON.stringify({
    delivered: { u1: { c1: 1 } }
  }));
  fs.writeFileSync(path.join(data, 'chat-bg.json'), JSON.stringify({
    default: '/bg/w1.jpg',
    presets: [{ path: '/bg/w1.jpg' }]
  }));
  fs.writeFileSync(path.join(data, 'friendmeta.json'), JSON.stringify({
    byOwner: { u1: { u2: { remark: 'Bob' } } }
  }));
  fs.writeFileSync(path.join(data, 'transfers.json'), JSON.stringify({ transfers: [] }));
  fs.writeFileSync(path.join(data, 'redpackets.json'), JSON.stringify({ redpackets: [] }));
  fs.writeFileSync(path.join(data, 'uploads', 'photo.jpg'), 'photo');
  fs.writeFileSync(path.join(root, 'public', 'bg', 'w1.jpg'), 'background');
  fs.writeFileSync(path.join(data, 'messages', 'c1.jsonl'), JSON.stringify({
    id: 'msg1',
    chatId: 'c1',
    seq: 1,
    senderId: 'u1',
    kind: 'image',
    content: '/uploads/photo.jpg'
  }) + '\n');
  fs.writeFileSync(path.join(data, 'secret.key'), 'inventory-test-secret');
  const vault = createSecurityVault({
    dataDir: data,
    rootMaterial: 'inventory-test-secret'
  });
  vault.rotate('message', 'test', 'inventory kv2 fixture');
  const kv2 = vault.sealJson('message', 'c1', {
    id: 'msg2',
    chatId: 'c1',
    seq: 2,
    senderId: 'u2',
    kind: 'text',
    content: 'versioned message'
  });
  fs.appendFileSync(path.join(data, 'messages', 'c1.jsonl'), JSON.stringify(kv2) + '\n');

  const report = inventoryData({
    dataDir: data,
    secret: 'inventory-test-secret',
    sourceId: 'fixture',
    baselineDate: '2026-11-12',
    publicDir: path.join(root, 'public')
  });
  assert.strictEqual(report.ok, true, JSON.stringify(report.issues));
  assert.strictEqual(report.baselineDate, '2026-11-12');
  assert.strictEqual(report.counts.users, 2);
  assert.strictEqual(report.counts.friendships, 1);
  assert.strictEqual(report.counts.messages, 2);
  assert.strictEqual(report.counts.uploads, 1);
  assert.strictEqual(report.counts.friendMeta, 1);
  assert.strictEqual(report.counts.reads, 1);
  assert.strictEqual(report.counts.delivered, 1);
  assert.strictEqual(report.counts.backgrounds >= 3, true);
  assert.strictEqual(report.errorCount, 0);
  assert.strictEqual(report.warningCount, 0);
  assert.strictEqual(report.shardPreview.users.shards6.reduce((a, b) => a + b, 0), 2);
  assert.strictEqual(report.shardPreview.users.shards7.reduce((a, b) => a + b, 0), 2);

  fs.rmSync(path.join(data, 'uploads', 'photo.jpg'));
  const invalid = inventoryData({
    dataDir: data,
    secret: 'inventory-test-secret',
    publicDir: path.join(root, 'public'),
    sourceId: 'fixture-invalid'
  });
  assert.strictEqual(invalid.ok, false);
  assert.ok(invalid.issues.some((row) =>
    row.kind === 'upload-missing' || row.kind === 'wallpaper-missing'));

  console.log('shard-data-inventory: passed');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
