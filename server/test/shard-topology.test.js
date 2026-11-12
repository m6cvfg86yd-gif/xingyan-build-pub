'use strict';

const assert = require('assert');
const path = require('path');
const { resolveTopology } = require('../lib/shard-topology');

const file = path.join(__dirname, '..', 'shard-topologies.json');
const six = resolveTopology(file, 'server-a-shards-6');
const seven = resolveTopology(file, 'server-b-shards-7');

assert.strictEqual(six.shardCount, 6);
assert.deepStrictEqual(six.ports, [5299, 5399, 5499, 5599, 5699, 5799]);
assert.strictEqual(seven.shardCount, 7);
assert.deepStrictEqual(seven.ports, [5299, 5399, 5499, 5599, 5699, 5799, 5899]);
assert.throws(() => resolveTopology(file, ''), /topology id is required/);
assert.throws(() => resolveTopology(file, 'missing'), /unknown shard topology/);

console.log('shard-topology: passed');
