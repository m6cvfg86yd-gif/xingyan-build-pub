'use strict';

const fs = require('fs');
const path = require('path');
const { DatabaseSync } = require('node:sqlite');

function placeholders(count) {
  return Array.from({ length: count }, () => '?').join(',');
}

class GroupDeletionStore {
  constructor(options) {
    const opts = options || {};
    this.file = String(opts.databaseFile || opts.file || '');
    if (!this.file) throw new Error('group deletion database file is required');
    this.now = typeof opts.now === 'function'
      ? opts.now
      : () => new Date().toISOString();
    fs.mkdirSync(path.dirname(this.file), { recursive: true });
    this.db = new DatabaseSync(this.file);
    this.db.exec(`
      PRAGMA busy_timeout = 10000;
      PRAGMA journal_mode = WAL;
      PRAGMA synchronous = FULL;

      CREATE TABLE IF NOT EXISTS group_message_global_state (
        message_id TEXT PRIMARY KEY,
        group_id TEXT NOT NULL,
        seq INTEGER NOT NULL,
        action TEXT NOT NULL,
        actor_user_id TEXT NOT NULL DEFAULT '',
        reason TEXT NOT NULL DEFAULT '',
        version INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );

      CREATE INDEX IF NOT EXISTS group_message_global_by_group
        ON group_message_global_state(group_id, seq);

      CREATE TABLE IF NOT EXISTS group_user_message_tombstones (
        user_id TEXT NOT NULL,
        group_id TEXT NOT NULL,
        message_id TEXT NOT NULL,
        action TEXT NOT NULL,
        version INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY(user_id, group_id, message_id)
      );

      CREATE INDEX IF NOT EXISTS group_user_tombstones_by_chat
        ON group_user_message_tombstones(user_id, group_id);

      CREATE TABLE IF NOT EXISTS group_user_chat_cursors (
        user_id TEXT NOT NULL,
        group_id TEXT NOT NULL,
        cleared_seq INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        PRIMARY KEY(user_id, group_id)
      );
    `);
  }

  setGlobal(groupId, messageId, seq, action, options) {
    const opts = options || {};
    const group = String(groupId || '');
    const id = String(messageId || '');
    if (!group || !id) throw new Error('groupId and messageId are required');
    const version = Math.max(2, Math.floor(Number(opts.version) || 2));
    const at = String(opts.at || this.now());
    const current = this.globalState(id);
    if (current && current.version > version) {
      return { updated: false, duplicate: true, state: current };
    }
    this.db.prepare(`
      INSERT INTO group_message_global_state
        (message_id, group_id, seq, action, actor_user_id, reason,
         version, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(message_id) DO UPDATE SET
        group_id = excluded.group_id,
        seq = excluded.seq,
        action = excluded.action,
        actor_user_id = excluded.actor_user_id,
        reason = excluded.reason,
        version = excluded.version,
        updated_at = excluded.updated_at
    `).run(
      id,
      group,
      Math.max(0, Math.floor(Number(seq) || 0)),
      String(action || 'recall'),
      String(opts.actorUserId || ''),
      String(opts.reason || ''),
      version,
      current ? current.createdAt : at,
      at
    );
    return {
      updated: true,
      duplicate: false,
      state: this.globalState(id)
    };
  }

  recall(groupId, messageId, seq, actorUserId) {
    return this.setGlobal(groupId, messageId, seq, 'recall', {
      actorUserId,
      version: 2
    });
  }

  takedown(groupId, messageId, seq, actorUserId, reason) {
    return this.setGlobal(groupId, messageId, seq, 'takedown', {
      actorUserId,
      reason,
      version: 3
    });
  }

  hideForUser(groupId, userId, messageId) {
    const group = String(groupId || '');
    const user = String(userId || '');
    const id = String(messageId || '');
    if (!group || !user || !id) throw new Error('group, user and message are required');
    const at = this.now();
    this.db.prepare(`
      INSERT INTO group_user_message_tombstones
        (user_id, group_id, message_id, action, version, created_at, updated_at)
      VALUES (?, ?, ?, 'hide', 1, ?, ?)
      ON CONFLICT(user_id, group_id, message_id) DO UPDATE SET
        version = excluded.version,
        updated_at = excluded.updated_at
    `).run(user, group, id, at, at);
    return true;
  }

  clearForUser(groupId, userId, seq) {
    const group = String(groupId || '');
    const user = String(userId || '');
    const value = Math.max(0, Math.floor(Number(seq) || 0));
    if (!group || !user) throw new Error('group and user are required');
    this.db.prepare(`
      INSERT INTO group_user_chat_cursors
        (user_id, group_id, cleared_seq, updated_at)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(user_id, group_id) DO UPDATE SET
        cleared_seq = MAX(group_user_chat_cursors.cleared_seq, excluded.cleared_seq),
        updated_at = excluded.updated_at
    `).run(user, group, value, this.now());
    return value;
  }

  clearance(groupId, userId) {
    const row = this.db.prepare(`
      SELECT cleared_seq FROM group_user_chat_cursors
      WHERE user_id = ? AND group_id = ?
    `).get(String(userId || ''), String(groupId || ''));
    return Number(row && row.cleared_seq) || 0;
  }

  globalState(messageId) {
    const row = this.db.prepare(`
      SELECT * FROM group_message_global_state WHERE message_id = ?
    `).get(String(messageId || ''));
    if (!row) return null;
    return {
      messageId: String(row.message_id),
      groupId: String(row.group_id),
      seq: Number(row.seq) || 0,
      action: String(row.action),
      actorUserId: String(row.actor_user_id || ''),
      reason: String(row.reason || ''),
      version: Number(row.version) || 0,
      createdAt: String(row.created_at || ''),
      updatedAt: String(row.updated_at || '')
    };
  }

  apply(groupId, userId, messages) {
    const rows = Array.isArray(messages) ? messages : [];
    if (!rows.length) return [];
    const ids = rows.map((row) => String(row.id || '')).filter(Boolean);
    if (!ids.length) return rows;
    const marks = placeholders(ids.length);
    const hidden = new Set(this.db.prepare(`
      SELECT message_id FROM group_user_message_tombstones
      WHERE user_id = ? AND group_id = ? AND message_id IN (${marks})
    `).all(String(userId || ''), String(groupId || ''), ...ids)
      .map((row) => String(row.message_id)));
    const global = new Map(this.db.prepare(`
      SELECT * FROM group_message_global_state
      WHERE message_id IN (${marks})
    `).all(...ids).map((row) => [String(row.message_id), row]));
    const output = [];
    for (const message of rows) {
      const id = String(message.id || '');
      if (hidden.has(id)) continue;
      const state = global.get(id);
      if (!state) {
        output.push(message);
        continue;
      }
      output.push(Object.assign({}, message, {
        recalled: true,
        content: '',
        deletedForEveryone: true,
        deletionAction: String(state.action || 'recall'),
        deletionVersion: Number(state.version) || 0,
        deletionReason: String(state.reason || '')
      }));
    }
    return output;
  }

  close() {
    if (!this.db) return;
    this.db.close();
    this.db = null;
  }
}

module.exports = { GroupDeletionStore };
