'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const {
  classifyPath,
  buildPlacementReport,
  buildPlacementReportFromEntries
} = require('../lib/shard-data-placement');

assert.strictEqual(classifyPath('users.json').placement, 'user-shard');
assert.strictEqual(classifyPath('messages/c1.jsonl').placement, 'chat-shard');
assert.strictEqual(classifyPath('uploads/a.jpg').placement, 'object-store');
assert.strictEqual(classifyPath('money-journal.jsonl').placement, 'payment-authority');
assert.strictEqual(classifyPath('music.json').domain, 'music');
assert.strictEqual(classifyPath('game-scores.json').domain, 'game');
assert.strictEqual(classifyPath('ui.json.bak-1').placement, 'archive');
const manifestReport = buildPlacementReportFromEntries([
  { path: 'users.json', bytes: 10 },
  { path: 'messages/', directory: true },
  { path: 'data/', directory: true }
], { shallowKnownDirectories: true });
assert.strictEqual(manifestReport.ok, true);
assert.strictEqual(manifestReport.files, 3);

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-placement-'));
try {
  fs.mkdirSync(path.join(root, 'messages'));
  fs.mkdirSync(path.join(root, 'uploads'));
  fs.writeFileSync(path.join(root, 'users.json'), '{}');
  fs.writeFileSync(path.join(root, 'chats.json'), '{}');
  fs.writeFileSync(path.join(root, 'music.json'), '{}');
  fs.writeFileSync(path.join(root, 'game-scores.json'), '{}');
  fs.writeFileSync(path.join(root, 'messages', 'c1.jsonl'), '');
  fs.writeFileSync(path.join(root, 'uploads', 'a.jpg'), 'x');
  fs.writeFileSync(path.join(root, 'ui.json.bak-old'), '{}');

  const report = buildPlacementReport(root);
  assert.strictEqual(report.ok, true);
  assert.strictEqual(report.files, 7);
  assert.strictEqual(report.byPlacement['user-shard'].files, 1);
  assert.strictEqual(report.byPlacement['object-store'].files, 1);
  assert.strictEqual(report.byPlacement.archive.files, 1);

  console.log('shard-data-placement: passed');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
