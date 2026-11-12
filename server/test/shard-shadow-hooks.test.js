'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const serverDir = path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(serverDir, 'server.js'), 'utf8');
const serviceSource = fs.readFileSync(
  path.join(serverDir, 'lib', 'shard-shadow-service.js'),
  'utf8'
);
const manifest = JSON.parse(fs.readFileSync(
  path.join(serverDir, 'shard-coverage.json'),
  'utf8'
));

for (const route of manifest.routes) {
  const marker = "observeShardShadow('" + route.id + "'";
  assert.ok(source.includes(marker), 'missing shadow hook: ' + route.id);
  assert.strictEqual(route.status, 'shadow', 'route must be in shadow mode: ' + route.id);
}

assert.ok(
  source.includes("enabled: process.env.SHARD_SHADOW_ENABLED || '0'"),
  'shadow mode must default to disabled'
);
assert.ok(
  serviceSource.includes("path.join(options.dataDir, 'shard-shadow')"),
  'shadow state must stay isolated from live shard state'
);

console.log('shard-shadow-hooks: passed');
