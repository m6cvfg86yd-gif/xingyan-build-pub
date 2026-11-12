'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { inventoryData } = require('../lib/shard-data-inventory');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-data-inventory-'));

try {
  const data = path.join(root, 'data');
  fs.mkdirSync(path.join(data, 'messages'), { recursive: true });
  fs.mkdirSync(path.join(data, 'uploads'), { recursive: true });
  fs.writeFileSync(path.join(data, 'users.json'), JSON.stringify({
    users: [{ id: 'u1' }, { id: 'u2' }]
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
  fs.writeFileSync(path.join(data, 'friendmeta.json'), JSON.stringify({
    byOwner: { u1: { u2: { remark: 'Bob' } } }
  }));
  fs.writeFileSync(path.join(data, 'transfers.json'), JSON.stringify({ transfers: [] }));
  fs.writeFileSync(path.join(data, 'redpackets.json'), JSON.stringify({ redpackets: [] }));
  fs.writeFileSync(path.join(data, 'uploads', 'photo.jpg'), 'photo');
  fs.writeFileSync(path.join(data, 'messages', 'c1.jsonl'), JSON.stringify({
    id: 'msg1',
    chatId: 'c1',
    seq: 1,
    senderId: 'u1',
    kind: 'image',
    content: '/uploads/photo.jpg'
  }) + '\n');

  const report = inventoryData({
    dataDir: data,
    sourceId: 'fixture',
    baselineDate: '2026-11-12'
  });
  assert.strictEqual(report.ok, true, JSON.stringify(report.issues));
  assert.strictEqual(report.baselineDate, '2026-11-12');
  assert.strictEqual(report.counts.users, 2);
  assert.strictEqual(report.counts.friendships, 1);
  assert.strictEqual(report.counts.messages, 1);
  assert.strictEqual(report.counts.uploads, 1);
  assert.strictEqual(report.shardPreview.users.shards6.reduce((a, b) => a + b, 0), 2);
  assert.strictEqual(report.shardPreview.users.shards7.reduce((a, b) => a + b, 0), 2);

  fs.writeFileSync(path.join(data, 'friendships.json'), JSON.stringify({
    friendships: [{ id: 'bad', fromId: 'u1', toId: 'missing', status: 'accepted' }]
  }));
  const invalid = inventoryData({ dataDir: data, sourceId: 'fixture-invalid' });
  assert.strictEqual(invalid.ok, false);
  assert.ok(invalid.issues.some((row) => row.kind === 'friendship-user'));

  console.log('shard-data-inventory: passed');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
