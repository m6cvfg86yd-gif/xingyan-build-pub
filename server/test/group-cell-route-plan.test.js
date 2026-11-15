'use strict';

const assert = require('assert');
const { planGroupCells } = require('../lib/group-cell-route-plan');

const groups = Array.from({ length: 101 }, (_, index) => ({
  groupId: 'group-' + String(index).padStart(3, '0'),
  memberCount: index + 2
}));
const cellIds = ['cell-c', 'cell-a', 'cell-b'];
const plan = planGroupCells({ groups, cellIds });
const reversed = planGroupCells({ groups: groups.slice().reverse(), cellIds: cellIds.slice().reverse() });

assert.strictEqual(plan.groupCount, groups.length);
assert.strictEqual(new Set(plan.assignments.map((row) => row.groupId)).size, groups.length);
assert.ok(plan.assignments.every((row) => cellIds.includes(row.cellId)));
assert.ok(plan.maxSkew <= 1);
assert.strictEqual(plan.assignmentHash, reversed.assignmentHash);
assert.deepStrictEqual(plan.assignments, reversed.assignments);

const previous = {
  assignments: plan.assignments.slice(0, 80).map((row) => ({
    groupId: row.groupId,
    cellId: row.cellId
  }))
};
const incremental = planGroupCells({
  groups: groups.concat([{ groupId: 'group-new', memberCount: 5 }]),
  cellIds,
  previousAssignments: previous
});
const previousMap = new Map(previous.assignments.map((row) => [row.groupId, row.cellId]));
assert.ok(previous.assignments.every((row) => {
  const assigned = incremental.assignments.find((next) => next.groupId === row.groupId);
  return assigned && assigned.cellId === previousMap.get(row.groupId);
}));
assert.strictEqual(incremental.preservedAssignments, previous.assignments.length);
assert.strictEqual(incremental.newAssignments, 22);

assert.throws(() => planGroupCells({ groups: [], cellIds }), /at least one group/);
assert.throws(() => planGroupCells({ groups, cellIds: [] }), /at least one cell/);
console.log('group-cell-route-plan: passed');
