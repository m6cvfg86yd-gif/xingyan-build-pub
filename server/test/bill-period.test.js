'use strict';

const assert = require('assert');
const {
  normalizeBillTimeZone,
  billDateKey,
  billMonthKey,
  summarizeBills
} = require('../lib/bill-period');

const shanghai = 'Asia/Shanghai';
const rows = [
  {
    amount: 0.1,
    direction: 'out',
    status: 'received',
    createdAt: '2026-10-31T16:30:00.000Z'
  },
  {
    amount: 0.2,
    direction: 'out',
    status: 'pending',
    createdAt: '2026-10-31T15:59:59.999Z'
  },
  {
    amount: 10.1,
    direction: 'in',
    status: 'received',
    createdAt: '2026-10-31T16:31:00.000Z'
  },
  {
    amount: 99,
    direction: 'out',
    status: 'received',
    createdAt: '2026-09-30T12:00:00.000Z'
  }
];

assert.equal(billDateKey('2026-10-31T16:30:00.000Z', shanghai), '2026-11-01');
assert.equal(billMonthKey('2026-10-31T15:59:59.999Z', shanghai), '2026-10');
assert.equal(billDateKey('not-a-date', shanghai), '');
assert.equal(normalizeBillTimeZone('Not/AZone'), 'UTC');

const november = summarizeBills(rows, '2026-11', shanghai);
assert.deepEqual(november, {
  out: 0.1,
  in: 10.1,
  pendingOut: 0,
  pendingIn: 0,
  count: 2,
  month: '2026-11'
});

const october = summarizeBills(rows, '2026-10', shanghai);
assert.deepEqual(october, {
  out: 0.2,
  in: 0,
  pendingOut: 1,
  pendingIn: 0,
  count: 1,
  month: '2026-10'
});

assert.equal(summarizeBills([
  { amount: 0.1, direction: 'out', status: 'received', createdAt: '2026-11-01T00:00:00.000Z' },
  { amount: 0.2, direction: 'out', status: 'received', createdAt: '2026-11-01T00:01:00.000Z' }
], '2026-11', 'UTC').out, 0.3);

console.log('bill-period: passed');
