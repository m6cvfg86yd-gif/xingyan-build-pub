'use strict';

const fs = require('fs');
const path = require('path');
const { DatabaseSync } = require('node:sqlite');

class GroupRouteStore {
  constructor(options) {
    const opts = options || {};
    this.file = String(opts.databaseFile || opts.file || '');
    if (!this.file) throw new Error('route database file is required');
    this.now = typeof opts.now === 'function'
      ? opts.now
      : () => new Date().toISOString();
    fs.mkdirSync(path.dirname(this.file), { recursive: true });
    this.db = new DatabaseSync(this.file);
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

  get(groupId) {
    const row = this.db.prepare(`
      SELECT * FROM group_cell_routes WHERE group_id = ?
    `).get(String(groupId || ''));
    return row ? this.row(row) : null;
  }

  set(route) {
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
