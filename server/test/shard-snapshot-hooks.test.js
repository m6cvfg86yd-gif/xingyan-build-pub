'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const source = fs.readFileSync(path.join(__dirname, '..', 'server.js'), 'utf8');
const required = [
  "captureShardSnapshots(['users']",
  "captureShardSnapshots(['friendships']",
  "captureShardSnapshots(['chats']",
  "captureShardSnapshots(['reads']",
  "captureShardSnapshots(['friendMeta']",
  "captureShardSnapshots(['moments']",
  "captureShardSnapshots(['momentNotices', 'momentNoticeSeen']",
  "captureShardSnapshots(['transfers']",
  "captureShardSnapshots(['redpackets']",
  "captureShardSnapshots(['messageThreads']"
];

for (const marker of required) {
  assert.ok(source.includes(marker), 'missing persistent snapshot hook: ' + marker);
}
assert.ok(
  source.split("captureShardSnapshots(['messageThreads']").length >= 3,
  'message append and full-file rewrite must both be mirrored'
);

console.log('shard-snapshot-hooks: passed');
