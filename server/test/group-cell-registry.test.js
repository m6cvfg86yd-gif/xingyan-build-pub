'use strict';

const assert = require('assert');
const { GroupCellRegistry } = require('../lib/group-cell-registry');

let clock = 1000;
const seenTokens = [];
const registry = new GroupCellRegistry({
  timeoutMs: 500,
  now: () => clock,
  cells: [
    {
      cellId: 'cell-a',
      baseUrl: 'http://cell-a.example:6201',
      internalToken: 'token-a',
      capacityWeight: 100,
      usedWeight: 20
    },
    {
      cellId: 'cell-b',
      baseUrl: 'http://cell-b.example:6201',
      internalToken: 'token-b',
      capacityWeight: 100,
      usedWeight: 70
    },
    {
      cellId: 'cell-c',
      baseUrl: 'http://cell-c.example:6201',
      capacityWeight: 100,
      usedWeight: 0,
      draining: true
    }
  ],
  fetchImpl: async (url, options) => {
    seenTokens.push(String(options.headers['X-Internal-Token'] || ''));
    clock += 3;
    if (url.includes('cell-b')) {
      return {
        ok: false,
        async json() { return { ok: false, error: 'offline' }; }
      };
    }
    return {
      ok: true,
      async json() {
        return {
          ok: true,
          stats: { fanout: { queued: 0 }, lastFanoutError: '' }
        };
      }
    };
  }
});

async function main() {
  let snapshot = await registry.checkAll();
  assert.deepStrictEqual(snapshot.cells.map((cell) => cell.healthy), [true, false, true]);
  assert.ok(snapshot.cells[0].latencyMs >= 3 && snapshot.cells[0].latencyMs <= 9);
  assert.deepStrictEqual(seenTokens.sort(), ['', 'token-a', 'token-b']);
  assert.strictEqual(registry.get('cell-a', { requireHealthy: true }).remainingWeight, 80);
  assert.strictEqual(registry.get('cell-b', { requireHealthy: true }), null);
  assert.strictEqual(registry.get('cell-c', { requireHealthy: true }), null);

  const selected = registry.select('group-large', 90);
  assert.strictEqual(selected, null);
  const next = registry.select('group-small', 10);
  assert.strictEqual(next.cellId, 'cell-a');
  registry.setUsedWeight('cell-a', 95);
  assert.strictEqual(registry.select('group-small', 10), null);

  snapshot = registry.snapshot();
  assert.ok(!JSON.stringify(snapshot).includes('token-a'));
  assert.ok(!JSON.stringify(snapshot).includes('token-b'));
  console.log('group-cell-registry: passed');
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
