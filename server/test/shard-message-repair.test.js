'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { repairMessageSequences } = require('../lib/shard-message-repair');
const { createSecurityVault } = require('../lib/security-vault');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-message-repair-'));
try {
  fs.mkdirSync(path.join(root, 'messages'));
  const secret = 'repair-test-secret';
  fs.writeFileSync(path.join(root, 'secret.key'), secret);
  const vault = createSecurityVault({ dataDir: root, rootMaterial: secret });
  vault.rotate('message', 'test', 'repair fixture');
  const messages = [
    { id: 'm1', chatId: 'c1', seq: 1, senderId: 'u1', content: 'one' },
    { id: 'm2', chatId: 'c1', seq: 1, senderId: 'u1', content: 'two' },
    { id: 'm3', chatId: '', seq: 2, senderId: 'u2', content: 'three' }
  ].map((message) => JSON.stringify(vault.sealJson('message', 'c1', message)));
  fs.writeFileSync(path.join(root, 'messages', 'c1.jsonl'), messages.join('\n') + '\n');

  const dry = repairMessageSequences({
    messagesDir: path.join(root, 'messages'),
    secret,
    dryRun: true
  });
  assert.strictEqual(dry.changed, 2);
  assert.strictEqual(dry.failed, 0);

  const report = repairMessageSequences({
    messagesDir: path.join(root, 'messages'),
    secret
  });
  assert.strictEqual(report.changed, 2);
  assert.strictEqual(report.failed, 0);
  const opened = fs.readFileSync(path.join(root, 'messages', 'c1.jsonl'), 'utf8')
    .trim().split('\n')
    .map((line) => vault.openJson('message', 'c1', JSON.parse(line), null));
  assert.deepStrictEqual(opened.map((row) => row.seq), [1, 2, 3]);
  assert.deepStrictEqual(opened.map((row) => row.chatId), ['c1', 'c1', 'c1']);

  console.log('shard-message-repair: passed');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
