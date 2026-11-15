'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { DatabaseSync } = require('node:sqlite');
const { canonical } = require('./shard-snapshot');

class DurableGroupQueue {
  constructor(options) {
    const opts = options || {};
    this.file = String(opts.databaseFile || opts.file || '');
    if (!this.file) throw new Error('queue database file is required');
    this.now = typeof opts.now === 'function' ? opts.now : () => Date.now();
    this.leaseMs = Math.max(1000, Number(opts.leaseMs) || 30000);
    fs.mkdirSync(path.dirname(this.file), { recursive: true });
    this.db = new DatabaseSync(this.file);
    this.db.exec(`
      PRAGMA busy_timeout = 10000;
      PRAGMA journal_mode = WAL;
      PRAGMA synchronous = FULL;
      CREATE TABLE IF NOT EXISTS group_notification_queue (
        id TEXT PRIMARY KEY,
        dedupe_key TEXT NOT NULL UNIQUE,
        kind TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        status TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        available_at INTEGER NOT NULL,
        lease_until INTEGER NOT NULL DEFAULT 0,
        worker_id TEXT NOT NULL DEFAULT '',
        last_error TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE INDEX IF NOT EXISTS group_notification_ready
        ON group_notification_queue(status, available_at, lease_until, created_at);
    `);
  }

  enqueue(kind, payload, dedupeKey) {
    const type = String(kind || '');
    if (!type) throw new Error('queue kind is required');
    const key = String(dedupeKey || crypto.createHash('sha256')
      .update(type + '|' + canonical(payload || {}))
      .digest('hex'));
    const at = this.now();
    const id = crypto.randomUUID();
    const result = this.db.prepare(`
      INSERT OR IGNORE INTO group_notification_queue
        (id, dedupe_key, kind, payload_json, status, attempts,
         available_at, lease_until, worker_id, last_error, created_at, updated_at)
      VALUES (?, ?, ?, ?, 'pending', 0, ?, 0, '', '', ?, ?)
    `).run(id, key, type, canonical(payload || {}), at, at, at);
    const row = this.db.prepare(`
      SELECT * FROM group_notification_queue WHERE dedupe_key = ?
    `).get(key);
    return { created: Number(result.changes) > 0, job: row ? this.row(row) : null };
  }

  enqueueUser(userId, event) {
    const value = event || {};
    const key = ['user', String(userId || ''), String(value.groupId || ''),
      Number(value.seq) || 0, String(value.type || '')].join(':');
    return this.enqueue('user-push', { userId: String(userId || ''), event: value }, key);
  }

  enqueuePartition(job) {
    const value = job || {};
    const key = ['partition', String(value.groupId || ''), Number(value.seq) || 0,
      Number(value.partition) || 0].join(':');
    return this.enqueue('group-partition', value, key);
  }

  claim(workerId, limit) {
    const worker = String(workerId || '');
    if (!worker) throw new Error('workerId is required');
    const count = Math.max(1, Math.min(1000, Math.floor(Number(limit) || 50)));
    const at = this.now();
    this.db.exec('BEGIN IMMEDIATE');
    try {
      const rows = this.db.prepare(`
        SELECT * FROM group_notification_queue
        WHERE status = 'pending' AND available_at <= ?
           OR status = 'inflight' AND lease_until <= ?
        ORDER BY available_at, created_at
        LIMIT ?
      `).all(at, at, count);
      const update = this.db.prepare(`
        UPDATE group_notification_queue
        SET status = 'inflight',
            attempts = attempts + 1,
            lease_until = ?,
            worker_id = ?,
            updated_at = ?
        WHERE id = ?
      `);
      for (const row of rows) update.run(at + this.leaseMs, worker, at, row.id);
      this.db.exec('COMMIT');
      return rows.map((row) => Object.assign(this.row(row), {
        status: 'inflight',
        attempts: Number(row.attempts) + 1,
        leaseUntil: at + this.leaseMs,
        workerId: worker
      }));
    } catch (error) {
      try { this.db.exec('ROLLBACK'); } catch (_) { }
      throw error;
    }
  }

  acknowledge(id) {
    return this.db.prepare(`
      UPDATE group_notification_queue
      SET status = 'done', lease_until = 0, worker_id = '', updated_at = ?
      WHERE id = ?
    `).run(this.now(), String(id || '')).changes > 0;
  }

  retry(id, delayMs, error) {
    const at = this.now();
    return this.db.prepare(`
      UPDATE group_notification_queue
      SET status = 'pending',
          available_at = ?,
          lease_until = 0,
          worker_id = '',
          last_error = ?,
          updated_at = ?
      WHERE id = ?
    `).run(at + Math.max(0, Number(delayMs) || 0),
      String(error || '').slice(0, 1000), at, String(id || '')).changes > 0;
  }

  recoverExpired() {
    const at = this.now();
    return this.db.prepare(`
      UPDATE group_notification_queue
      SET status = 'pending',
          lease_until = 0,
          worker_id = '',
          updated_at = ?
      WHERE status = 'inflight' AND lease_until <= ?
    `).run(at, at).changes;
  }

  stats() {
    const rows = this.db.prepare(`
      SELECT status, COUNT(*) AS count
      FROM group_notification_queue
      GROUP BY status
    `).all();
    const byStatus = {};
    for (const row of rows) byStatus[String(row.status)] = Number(row.count) || 0;
    return {
      pending: byStatus.pending || 0,
      inflight: byStatus.inflight || 0,
      done: byStatus.done || 0,
      total: Object.values(byStatus).reduce((sum, value) => sum + value, 0)
    };
  }

  row(value) {
    return {
      id: String(value.id || ''),
      dedupeKey: String(value.dedupe_key || ''),
      kind: String(value.kind || ''),
      payload: JSON.parse(String(value.payload_json || '{}')),
      status: String(value.status || ''),
      attempts: Number(value.attempts) || 0,
      availableAt: Number(value.available_at) || 0,
      leaseUntil: Number(value.lease_until) || 0,
      workerId: String(value.worker_id || ''),
      lastError: String(value.last_error || ''),
      createdAt: Number(value.created_at) || 0,
      updatedAt: Number(value.updated_at) || 0
    };
  }

  close() {
    if (!this.db) return;
    this.db.close();
    this.db = null;
  }
}

module.exports = { DurableGroupQueue };
