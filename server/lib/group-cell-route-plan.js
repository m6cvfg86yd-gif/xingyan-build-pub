'use strict';

const crypto = require('crypto');
const { hash } = require('./shard-snapshot');

function textCompare(left, right) {
  return String(left) < String(right) ? -1 : (String(left) > String(right) ? 1 : 0);
}

function digest(value) {
  return crypto.createHash('sha256').update(String(value)).digest('hex');
}

function normalizeCells(cellIds) {
  const cells = Array.from(new Set(
    (cellIds || []).map((cellId) => String(cellId || '').trim()).filter(Boolean)
  )).sort(textCompare);
  if (!cells.length) throw new Error('at least one cell is required');
  return cells;
}

function normalizeGroups(rows) {
  const groups = new Map();
  for (const row of rows || []) {
    const id = String(row && (row.groupId || row.id) || '').trim();
    if (!id) continue;
    const memberCount = Math.max(0, Math.floor(Number(row.memberCount) || 0));
    const explicitWeight = Number(row.weight);
    const weight = explicitWeight > 0
      ? explicitWeight
      : Math.max(1, Math.ceil(Math.log2(memberCount + 2)));
    groups.set(id, {
      groupId: id,
      memberCount,
      weight
    });
  }
  if (!groups.size) throw new Error('at least one group is required');
  return Array.from(groups.values()).sort((left, right) =>
    textCompare(left.groupId, right.groupId)
  );
}

function normalizePrevious(value) {
  const rows = value && value.assignments || value || [];
  const out = new Map();
  for (const row of rows) {
    const groupId = String(row && (row.groupId || row.id) || '').trim();
    const cellId = String(row && row.cellId || '').trim();
    if (groupId && cellId) out.set(groupId, cellId);
  }
  return out;
}

function planGroupCells(options) {
  const opts = options || {};
  const cells = normalizeCells(opts.cellIds);
  const groups = normalizeGroups(opts.groups);
  const previous = normalizePrevious(opts.previousAssignments);
  const cellSet = new Set(cells);
  const loads = new Map(cells.map((cellId) => [
    cellId,
    { groups: 0, weight: 0 }
  ]));
  const groupById = new Map(groups.map((group) => [group.groupId, group]));
  const assignments = new Map();

  for (const group of groups) {
    const previousCell = previous.get(group.groupId);
    if (!previousCell || !cellSet.has(previousCell)) continue;
    assignments.set(group.groupId, previousCell);
    const load = loads.get(previousCell);
    load.groups += 1;
    load.weight += group.weight;
  }

  const pending = groups
    .filter((group) => !assignments.has(group.groupId))
    .sort((left, right) =>
      textCompare(digest(left.groupId), digest(right.groupId))
      || textCompare(left.groupId, right.groupId)
    );

  for (const group of pending) {
    const minimum = Math.min(...Array.from(loads.values()).map((load) => load.weight));
    const candidates = cells
      .filter((cellId) => loads.get(cellId).weight === minimum)
      .sort((left, right) =>
        textCompare(digest(group.groupId + '\0' + left),
          digest(group.groupId + '\0' + right))
        || textCompare(left, right)
      );
    const cellId = candidates[0];
    assignments.set(group.groupId, cellId);
    const load = loads.get(cellId);
    load.groups += 1;
    load.weight += group.weight;
  }

  const rows = Array.from(assignments.entries())
    .map(([groupId, cellId]) => ({
      groupId,
      cellId,
      memberCount: groupById.get(groupId).memberCount,
      weight: groupById.get(groupId).weight
    }))
    .sort((left, right) => textCompare(left.groupId, right.groupId));
  const countRows = cells.map((cellId) => ({
    cellId,
    groups: loads.get(cellId).groups,
    weight: loads.get(cellId).weight
  }));
  const groupValues = countRows.map((row) => row.groups);
  const weightValues = countRows.map((row) => row.weight);
  const skew = Math.max(...groupValues) - Math.min(...groupValues);
  const totalWeight = weightValues.reduce((sum, value) => sum + value, 0);
  const idealWeight = totalWeight / cells.length;
  const maxWeightDeviation = Math.max(
    ...weightValues.map((value) => Math.abs(value - idealWeight))
  );
  const body = {
    version: 1,
    strategy: 'incremental-hash-balanced',
    cellIds: cells,
    assignments: rows,
    counts: countRows,
    groupCount: rows.length,
    totalWeight,
    idealWeight,
    maxSkew: skew,
    maxWeightDeviation,
    preservedAssignments: groups.length - pending.length,
    newAssignments: pending.length
  };
  return Object.assign(body, { assignmentHash: hash(body) });
}

module.exports = {
  planGroupCells,
  normalizeCells,
  normalizeGroups
};
