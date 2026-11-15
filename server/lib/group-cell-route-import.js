'use strict';

function planRows(plan) {
  const rows = plan && plan.assignments;
  if (!Array.isArray(rows) || !rows.length) {
    throw new Error('route plan must contain assignments');
  }
  const seen = new Set();
  return rows.map((row) => {
    const groupId = String(row && row.groupId || '').trim();
    const cellId = String(row && row.cellId || '').trim();
    if (!groupId || !cellId) throw new Error('every assignment requires groupId and cellId');
    if (seen.has(groupId)) throw new Error('duplicate group assignment: ' + groupId);
    seen.add(groupId);
    return {
      groupId,
      cellId,
      epoch: 1,
      status: 'active',
      sourceCellId: '',
      targetCellId: ''
    };
  }).sort((left, right) => left.groupId < right.groupId ? -1
    : (left.groupId > right.groupId ? 1 : 0));
}

function previewGroupCellRouteImport(plan, routeStore) {
  if (!routeStore) throw new Error('routeStore is required');
  const rows = planRows(plan);
  const inserted = [];
  const unchanged = [];
  const conflicts = [];
  for (const route of rows) {
    const current = routeStore.get(route.groupId);
    if (!current) {
      inserted.push(route);
    } else if (current.cellId === route.cellId
        && current.status === 'active'
        && current.epoch === 1
        && !current.sourceCellId
        && !current.targetCellId) {
      unchanged.push(current);
    } else {
      conflicts.push({ expected: route, current });
    }
  }
  return {
    ok: conflicts.length === 0,
    assignmentHash: String(plan.assignmentHash || ''),
    inserted,
    unchanged,
    conflicts
  };
}

function applyGroupCellRouteImport(plan, routeStore) {
  const preview = previewGroupCellRouteImport(plan, routeStore);
  if (!preview.ok) return preview;
  const result = routeStore.setInitialMany(preview.inserted);
  return {
    ok: result.ok,
    assignmentHash: preview.assignmentHash,
    inserted: result.inserted,
    unchanged: preview.unchanged.concat(result.unchanged),
    conflicts: result.conflicts
  };
}

module.exports = {
  previewGroupCellRouteImport,
  applyGroupCellRouteImport
};
