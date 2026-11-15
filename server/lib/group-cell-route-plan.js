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
    groups.set(id, {
      groupId: id,
      memberCount: Math.max(0, Math.floor(Number(row.memberCount) || 0))
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
  const counts = new Map(cells.map((cellId) => [cellId, 0]));
  const assignments = new Map();

  for (const group of groups) {
    const previousCell = previous.get(group.groupId);
    if (!previousCell || !cellSet.has(previousCell)) continue;
    assignments.set(group.groupId, previousCell);
    counts.set(previousCell, counts.get(previousCell) + 1);
  }

  const pending = groups
    .filter((group) => !assignments.has(group.groupId))
    .sort((left, right) =>
      textCompare(digest(left.groupId), digest(right.groupId))
      || textCompare(left.groupId, right.groupId)
    );

  for (const group of pending) {
    const minimum = Math.min(...counts.values());
    const candidates = cells
      .filter((cellId) => counts.get(cellId) === minimum)
      .sort((left, right) =>
        textCompare(digest(group.groupId + '\0' + left),
          digest(group.groupId + '\0' + right))
        || textCompare(left, right)
      );
    const cellId = candidates[0];
    assignments.set(group.groupId, cellId);
    counts.set(cellId, counts.get(cellId) + 1);
  }

  const groupById = new Map(groups.map((group) => [group.groupId, group]));
  const rows = Array.from(assignments.entries())
    .map(([groupId, cellId]) => ({
      groupId,
      cellId,
      memberCount: groupById.get(groupId).memberCount
    }))
    .sort((left, right) => textCompare(left.groupId, right.groupId));
  const countRows = cells.map((cellId) => ({
    cellId,
    groups: counts.get(cellId)
  }));
  const values = countRows.map((row) => row.groups);
  const skew = Math.max(...values) - Math.min(...values);
  const body = {
    version: 1,
    strategy: 'incremental-hash-balanced',
    cellIds: cells,
    assignments: rows,
    counts: countRows,
    groupCount: rows.length,
    maxSkew: skew,
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
