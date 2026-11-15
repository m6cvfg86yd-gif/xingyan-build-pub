'use strict';

const fs = require('fs');
const path = require('path');
const { DatabaseSync } = require('node:sqlite');

class GroupMembershipStore {
  constructor(options) {
    const opts = options || {};
    this.file = String(opts.databaseFile || opts.file || '');
    if (!this.file) throw new Error('group membership database file is required');
    this.now = typeof opts.now === 'function'
      ? opts.now
      : () => new Date().toISOString();
    fs.mkdirSync(path.dirname(this.file), { recursive: true });
    this.db = new DatabaseSync(this.file);
    this.db.exec(`
      PRAGMA busy_timeout = 10000;
      PRAGMA journal_mode = WAL;
      PRAGMA synchronous = FULL;
      CREATE TABLE IF NOT EXISTS group_membership_periods (
        group_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        joined_seq INTEGER NOT NULL,
        left_seq INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        PRIMARY KEY(group_id, user_id, joined_seq)
      );
      CREATE INDEX IF NOT EXISTS group_membership_active
        ON group_membership_periods(group_id, joined_seq, left_seq, user_id);
    `);
  }

  join(groupId, userId, joinedSeq) {
    const group = String(groupId || '');
    const user = String(userId || '');
    const seq = Math.floor(Number(joinedSeq) || 0);
    if (!group || !user || seq <= 0) {
      throw new Error('groupId, userId and positive joinedSeq are required');
    }
    const at = this.now();
    const active = this.db.prepare(`
      SELECT * FROM group_membership_periods
      WHERE group_id = ? AND user_id = ?
        AND joined_seq <= ? AND (left_seq = 0 OR left_seq > ?)
      ORDER BY joined_seq DESC LIMIT 1
    `).get(group, user, seq, seq);
    if (active) {
      return {
        joined: false,
        alreadyActive: true,
        period: this.row(active)
      };
    }
    this.db.prepare(`
      INSERT INTO group_membership_periods
        (group_id, user_id, joined_seq, left_seq, updated_at)
      VALUES (?, ?, ?, 0, ?)
      ON CONFLICT(group_id, user_id, joined_seq) DO UPDATE SET
        left_seq = 0,
        updated_at = excluded.updated_at
    `).run(group, user, seq, at);
    return {
      joined: true,
      alreadyActive: false,
      period: {
        groupId: group,
        userId: user,
        joinedSeq: seq,
        leftSeq: 0,
        updatedAt: at
      }
    };
  }

  leave(groupId, userId, leftSeq) {
    const group = String(groupId || '');
    const user = String(userId || '');
    const seq = Math.floor(Number(leftSeq) || 0);
    if (!group || !user || seq <= 0) {
      throw new Error('groupId, userId and positive leftSeq are required');
    }
    const row = this.db.prepare(`
      SELECT * FROM group_membership_periods
      WHERE group_id = ? AND user_id = ?
        AND joined_seq <= ? AND left_seq = 0
      ORDER BY joined_seq DESC LIMIT 1
    `).get(group, user, seq);
    if (!row) return { left: false, period: null };
    const at = this.now();
    this.db.prepare(`
      UPDATE group_membership_periods
      SET left_seq = ?, updated_at = ?
      WHERE group_id = ? AND user_id = ? AND joined_seq = ?
    `).run(seq, at, group, user, row.joined_seq);
    return {
      left: true,
      period: Object.assign(this.row(row), {
        leftSeq: seq,
        updatedAt: at
      })
    };
  }

  get(groupId, userId, atSeq) {
    const seq = Math.floor(Number(atSeq) || Number.MAX_SAFE_INTEGER);
    const row = this.db.prepare(`
      SELECT * FROM group_membership_periods
      WHERE group_id = ? AND user_id = ?
        AND joined_seq <= ? AND (left_seq = 0 OR left_seq > ?)
      ORDER BY joined_seq DESC LIMIT 1
    `).get(String(groupId || ''), String(userId || ''), seq, seq);
    return row ? this.row(row) : null;
  }

  getSync(groupId, userId, atSeq) {
    return this.get(groupId, userId, atSeq);
  }

  getLatest(groupId, userId) {
    const row = this.db.prepare(`
      SELECT * FROM group_membership_periods
      WHERE group_id = ? AND user_id = ?
      ORDER BY joined_seq DESC LIMIT 1
    `).get(String(groupId || ''), String(userId || ''));
    return row ? this.row(row) : null;
  }

  canReadSync(groupId, userId, messageSeq) {
    return !!this.get(groupId, userId, messageSeq);
  }

  countActive(groupId, atSeq) {
    const seq = Math.floor(Number(atSeq) || Number.MAX_SAFE_INTEGER);
    const row = this.db.prepare(`
      SELECT COUNT(*) AS count FROM group_membership_periods
      WHERE group_id = ?
        AND joined_seq <= ? AND (left_seq = 0 OR left_seq > ?)
    `).get(String(groupId || ''), seq, seq);
    return Number(row && row.count) || 0;
  }

  activeMembers(groupId, atSeq, offset, limit) {
    const seq = Math.floor(Number(atSeq) || Number.MAX_SAFE_INTEGER);
    const start = Math.max(0, Math.floor(Number(offset) || 0));
    const count = Math.max(1, Math.min(5000, Math.floor(Number(limit) || 1000)));
    return this.db.prepare(`
      SELECT * FROM group_membership_periods
      WHERE group_id = ?
        AND joined_seq <= ? AND (left_seq = 0 OR left_seq > ?)
      ORDER BY user_id
      LIMIT ? OFFSET ?
    `).all(String(groupId || ''), seq, seq, count, start).map((row) => this.row(row));
  }

  listPeriods(groupId) {
    return this.db.prepare(`
      SELECT * FROM group_membership_periods
      WHERE group_id = ?
      ORDER BY user_id, joined_seq
    `).all(String(groupId || '')).map((row) => this.row(row));
  }

  importPeriod(period) {
    const group = String(period && period.groupId || '');
    const user = String(period && period.userId || '');
    const joinedSeq = Math.floor(Number(period && period.joinedSeq) || 0);
    if (!group || !user || joinedSeq <= 0) return false;
    this.db.prepare(`
      INSERT INTO group_membership_periods
        (group_id, user_id, joined_seq, left_seq, updated_at)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(group_id, user_id, joined_seq) DO UPDATE SET
        left_seq = excluded.left_seq,
        updated_at = excluded.updated_at
    `).run(
      group,
      user,
      joinedSeq,
      Math.max(0, Number(period.leftSeq) || 0),
      String(period.updatedAt || this.now())
    );
    return true;
  }

  row(value) {
    return {
      groupId: String(value.group_id || ''),
      userId: String(value.user_id || ''),
      joinedSeq: Number(value.joined_seq) || 0,
      leftSeq: Number(value.left_seq) || 0,
      updatedAt: String(value.updated_at || '')
    };
  }

  close() {
    if (!this.db) return;
    this.db.close();
    this.db = null;
  }
}

module.exports = { GroupMembershipStore };
