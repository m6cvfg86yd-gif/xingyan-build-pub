'use strict';

const fs = require('fs');
const path = require('path');
const { DatabaseSync } = require('node:sqlite');

class GroupRouteStore {
  constructor(options) {
    const opts = options || {};
    this.file = String(opts.databaseFile || opts.file || '');
    if (!this.file) throw new Error('route database file is required');
    this.readOnly = opts.readOnly === true;
    if (this.readOnly && !fs.existsSync(this.file)) {
      throw new Error('route database file does not exist');
    }
    this.now = typeof opts.now === 'function'
      ? opts.now
      : () => new Date().toISOString();
    if (!this.readOnly) fs.mkdirSync(path.dirname(this.file), { recursive: true });
    this.db = this.readOnly
      ? new DatabaseSync(this.file, { readOnly: true })
      : new DatabaseSync(this.file);
    if (!this.readOnly) {
      this.db.exec(`
        PRAGMA busy_timeout = 10000;
        PRAGMA journal_mode = WAL;
        PRAGMA synchronous = FULL;
        CREATE TABLE IF NOT EXISTS group_cell_routes (
          group_id TEXT PRIMARY KEY,
          cell_id TEXT NOT NULL,
          epoch INTEGER NOT NULL,
          status TEXT NOT NULL,
          source_cell TEXT NOT NULL DEFAULT '',
          target_cell TEXT NOT NULL DEFAULT '',
          updated_at TEXT NOT NULL
        );
      `);
    }
  }

  get(groupId) {
    const row = this.db.prepare(`
      SELECT * FROM group_cell_routes WHERE group_id = ?
    `).get(String(groupId || ''));
    return row ? this.row(row) : null;
  }

  set(route) {
    if (this.readOnly) throw new Error('route store is read-only');
    const value = route || {};
    const groupId = String(value.groupId || '');
    const cellId = String(value.cellId || '');
    const epoch = Math.floor(Number(value.epoch) || 0);
    if (!groupId || !cellId || epoch <= 0) {
      throw new Error('groupId, cellId and positive epoch are required');
    }
    this.db.exec('BEGIN IMMEDIATE');
    try {
      const current = this.get(groupId);
      if (current && epoch < current.epoch) {
        this.db.exec('ROLLBACK');
        return { ok: false, stale: true, route: current };
      }
      const completesMigration = current
        && current.status === 'migrating'
        && String(value.status || '') === 'active'
        && cellId === current.targetCellId;
      if (current && epoch === current.epoch
          && !completesMigration
          && (current.cellId !== cellId
            || current.status !== String(value.status || 'active'))) {
        this.db.exec('ROLLBACK');
        return { ok: false, stale: true, route: current };
      }
      const next = {
        groupId,
        cellId,
        epoch,
        status: String(value.status || 'active'),
        sourceCellId: String(value.sourceCellId || ''),
        targetCellId: String(value.targetCellId || ''),
        updatedAt: this.now()
      };
      this.db.prepare(`
        INSERT INTO group_cell_routes
          (group_id, cell_id, epoch, status, source_cell, target_cell, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(group_id) DO UPDATE SET
          cell_id = excluded.cell_id,
          epoch = excluded.epoch,
          status = excluded.status,
          source_cell = excluded.source_cell,
          target_cell = excluded.target_cell,
          updated_at = excluded.updated_at
      `).run(
        groupId,
        cellId,
        epoch,
        next.status,
        next.sourceCellId,
        next.targetCellId,
        next.updatedAt
      );
      this.db.exec('COMMIT');
      return { ok: true, route: next };
    } catch (error) {
      try { this.db.exec('ROLLBACK'); } catch (_) { }
      throw error;
    }
  }

  setInitialMany(routes) {
    if (this.readOnly) throw new Error('route store is read-only');
    const values = (routes || []).map((route) => {
      const value = route || {};
      const groupId = String(value.groupId || '');
      const cellId = String(value.cellId || '');
      const epoch = Math.floor(Number(value.epoch) || 0);
      if (!groupId || !cellId || epoch <= 0) {
        throw new Error('groupId, cellId and positive epoch are required');
      }
      return {
        groupId,
        cellId,
        epoch,
        status: String(value.status || 'active'),
        sourceCellId: String(value.sourceCellId || ''),
        targetCellId: String(value.targetCellId || '')
      };
    });
    const groupIds = new Set();
    for (const route of values) {
      if (groupIds.has(route.groupId)) {
        throw new Error('duplicate route for group ' + route.groupId);
      }
      groupIds.add(route.groupId);
    }

    this.db.exec('BEGIN IMMEDIATE');
    try {
      const unchanged = [];
      const conflicts = [];
      for (const route of values) {
        const current = this.get(route.groupId);
        if (!current) continue;
        if (current.cellId === route.cellId
            && current.status === route.status
            && current.epoch === route.epoch
            && !current.sourceCellId
            && !current.targetCellId) {
          unchanged.push(current);
        } else {
          conflicts.push({ expected: route, current });
        }
      }
      if (conflicts.length) {
        this.db.exec('ROLLBACK');
        return { ok: false, conflicts, unchanged, inserted: [] };
      }

      const timestamp = this.now();
      const insert = this.db.prepare(`
        INSERT INTO group_cell_routes
          (group_id, cell_id, epoch, status, source_cell, target_cell, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      `);
      const inserted = [];
      const unchangedIds = new Set(unchanged.map((route) => route.groupId));
      for (const route of values) {
        if (unchangedIds.has(route.groupId)) continue;
        insert.run(
          route.groupId,
          route.cellId,
          route.epoch,
          route.status,
          route.sourceCellId,
          route.targetCellId,
          timestamp
        );
        inserted.push(Object.assign({ updatedAt: timestamp }, route));
      }
      this.db.exec('COMMIT');
      return { ok: true, inserted, unchanged, conflicts: [] };
    } catch (error) {
      try { this.db.exec('ROLLBACK'); } catch (_) { }
      throw error;
    }
  }

  row(value) {
    return {
      groupId: String(value.group_id || ''),
      cellId: String(value.cell_id || ''),
      epoch: Number(value.epoch) || 0,
      status: String(value.status || ''),
      sourceCellId: String(value.source_cell || ''),
      targetCellId: String(value.target_cell || ''),
      updatedAt: String(value.updated_at || '')
    };
  }

  close() {
    if (!this.db) return;
    this.db.close();
    this.db = null;
  }
}

module.exports = { GroupRouteStore };
