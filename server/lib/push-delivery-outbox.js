'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { DatabaseSync } = require('node:sqlite');

function idFor(value) {
  return crypto.createHash('sha256').update(String(value)).digest('hex');
}

class PushDeliveryOutbox {
  constructor(options) {
    const opts = options || {};
    this.file = String(opts.databaseFile || '');
    if (!this.file) throw new Error('push outbox databaseFile is required');
    this.maxAttempts = Math.max(1, Number(opts.maxAttempts) || 8);
    this.now = typeof opts.now === 'function'
      ? opts.now
      : () => new Date().toISOString();
    this.nowMs = typeof opts.nowMs === 'function'
      ? opts.nowMs
      : () => Date.now();
    fs.mkdirSync(path.dirname(this.file), { recursive: true });
    this.db = new DatabaseSync(this.file);
    this.db.exec(`
      PRAGMA busy_timeout = 10000;
      PRAGMA journal_mode = WAL;
      PRAGMA synchronous = NORMAL;
      PRAGMA wal_autocheckpoint = 1000;
      CREATE TABLE IF NOT EXISTS push_deliveries (
        id TEXT PRIMARY KEY,
        dedupe_key TEXT NOT NULL UNIQUE,
        user_id TEXT NOT NULL,
        device_token TEXT NOT NULL,
        env TEXT NOT NULL,
        kind TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        status TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        next_attempt_at INTEGER NOT NULL,
        lease_until INTEGER NOT NULL DEFAULT 0,
        last_error TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS push_delivery_due
        ON push_deliveries(status, next_attempt_at);
    `);
  }

  enqueue(options) {
    return this.enqueueMany([options])[0];
  }

  enqueueMany(optionsList) {
    const rows = (optionsList || []).map((options) => {
      const opts = options || {};
      const dedupeKey = String(opts.dedupeKey || '').trim();
      const userId = String(opts.userId || '').trim();
      const deviceToken = String(opts.deviceToken || '').trim();
      const env = String(opts.env || 'prod') === 'sandbox' ? 'sandbox' : 'prod';
      const kind = String(opts.kind || 'message');
      if (!dedupeKey || !userId || !deviceToken || !opts.payload) {
        throw new Error('dedupeKey, userId, deviceToken and payload are required');
      }
      return {
        id: idFor(dedupeKey),
        dedupeKey,
        userId,
        deviceToken,
        env,
        kind,
        payload: JSON.stringify(opts.payload)
      };
    });
    if (!rows.length) return [];
    const at = this.now();
    const due = this.nowMs();
    const statement = this.db.prepare(`
      INSERT INTO push_deliveries
        (id, dedupe_key, user_id, device_token, env, kind, payload_json,
         status, attempts, next_attempt_at, lease_until, last_error,
         created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', 0, ?, 0, '', ?, ?)
      ON CONFLICT(dedupe_key) DO NOTHING
    `);
    this.db.exec('BEGIN IMMEDIATE');
    try {
      const results = rows.map((row) => {
        const result = statement.run(
          row.id,
          row.dedupeKey,
          row.userId,
          row.deviceToken,
          row.env,
          row.kind,
          row.payload,
          due,
          at,
          at
        );
        return {
          inserted: Number(result.changes) === 1,
          duplicate: Number(result.changes) === 0,
          id: row.id
        };
      });
      this.db.exec('COMMIT');
      return results;
    } catch (error) {
      try { this.db.exec('ROLLBACK'); } catch (_) { }
      throw error;
    }
  }

  claim(limit, leaseMs) {
    const cap = Math.max(1, Math.min(500, Number(limit) || 50));
    const lease = Math.max(1000, Number(leaseMs) || 30000);
    const now = this.nowMs();
    const at = this.now();
    this.db.exec('BEGIN IMMEDIATE');
    try {
      const rows = this.db.prepare(`
        SELECT * FROM push_deliveries
        WHERE (status = 'pending' AND next_attempt_at <= ?)
           OR (status = 'sending' AND lease_until <= ?)
        ORDER BY created_at ASC
        LIMIT ?
      `).all(now, now, cap);
      const update = this.db.prepare(`
        UPDATE push_deliveries
        SET status = 'sending', lease_until = ?, updated_at = ?
        WHERE id = ?
      `);
      rows.forEach((row) => update.run(now + lease, at, row.id));
      this.db.exec('COMMIT');
      return rows.map((row) => ({
        id: String(row.id),
        dedupeKey: String(row.dedupe_key),
        userId: String(row.user_id),
        deviceToken: String(row.device_token),
        env: String(row.env),
        kind: String(row.kind),
        payload: JSON.parse(String(row.payload_json)),
        attempts: Number(row.attempts) || 0
      }));
    } catch (error) {
      try { this.db.exec('ROLLBACK'); } catch (_) { }
      throw error;
    }
  }

  complete(id) {
    return this.db.prepare(`
      UPDATE push_deliveries
      SET status = 'sent', attempts = attempts + 1, lease_until = 0,
          last_error = '', updated_at = ?
      WHERE id = ?
    `).run(this.now(), String(id || '')).changes;
  }

  retry(id, error, delayMs) {
    const attempts = Number(this.db.prepare(`
      SELECT attempts FROM push_deliveries WHERE id = ?
    `).get(String(id || ''))?.attempts) || 0;
    const nextAttempts = attempts + 1;
    const failed = nextAttempts >= this.maxAttempts;
    const nextAt = this.nowMs() + Math.max(500, Number(delayMs) || 5000);
    return this.db.prepare(`
      UPDATE push_deliveries
      SET status = ?, attempts = ?, next_attempt_at = ?, lease_until = 0,
          last_error = ?, updated_at = ?
      WHERE id = ?
    `).run(
      failed ? 'failed' : 'pending',
      nextAttempts,
      nextAt,
      String(error || '').slice(0, 500),
      this.now(),
      String(id || '')
    ).changes;
  }

  cleanup(beforeIso) {
    const before = String(beforeIso || '');
    if (!before) return 0;
    return this.db.prepare(`
      DELETE FROM push_deliveries
      WHERE status IN ('sent', 'failed') AND updated_at < ?
    `).run(before).changes;
  }

  snapshot() {
    const rows = this.db.prepare(`
      SELECT status, COUNT(*) AS count
      FROM push_deliveries
      GROUP BY status
    `).all();
    const counts = {};
    rows.forEach((row) => {
      counts[String(row.status)] = Number(row.count) || 0;
    });
    return { counts };
  }

  close() {
    if (!this.db) return;
    this.db.close();
    this.db = null;
  }
}

module.exports = { PushDeliveryOutbox };
