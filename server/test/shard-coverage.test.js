'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const {
  validateCoverageManifest,
  coverageSummary
} = require('../lib/shard-coverage');

const manifest = JSON.parse(fs.readFileSync(
  path.join(__dirname, '..', 'shard-coverage.json'),
  'utf8'
));

const validation = validateCoverageManifest(manifest);
assert.strictEqual(validation.ok, true, JSON.stringify(validation.failures));
assert.strictEqual(validation.routes, 21);

const summary = coverageSummary(manifest);
assert.strictEqual(summary.total, 21);
assert.strictEqual(summary.ready, false);
assert.strictEqual(summary.byStatus.pending, 0);
assert.strictEqual(summary.byStatus.shadow, 21);
assert.strictEqual(summary.byFamily.friendship, 6);
assert.strictEqual(summary.byFamily.chat, 8);
assert.strictEqual(summary.byFamily.moment, 6);
assert.strictEqual(summary.byFamily.payment, 1);

const duplicate = JSON.parse(JSON.stringify(manifest));
duplicate.routes.push(JSON.parse(JSON.stringify(duplicate.routes[0])));
const duplicateValidation = validateCoverageManifest(duplicate);
assert.strictEqual(duplicateValidation.ok, false);
assert.ok(duplicateValidation.failures.some((row) => row.code === 'duplicate-or-empty-id'));

console.log('shard-coverage: passed');
