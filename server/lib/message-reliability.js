'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { DatabaseSync } = require('node:sqlite');

function stableJson(value) {
    if (Array.isArray(value)) return '[' + value.map(stableJson).join(',') + ']';
    if (value && typeof value === 'object') {
        return '{' + Object.keys(value).sort().map((key) =>
            JSON.stringify(key) + ':' + stableJson(value[key])
        ).join(',') + '}';
    }
    const encoded = JSON.stringify(value);
    return encoded === undefined ? 'null' : encoded;
}

class MessageReliabilityStore {
    constructor(options) {
        const opts = options || {};
        this.file = String(opts.databaseFile || opts.file || '');
        if (!this.file) throw new Error('message reliability database file is required');
        this.now = typeof opts.now === 'function'
            ? opts.now
            : () => new Date().toISOString();
        this.uid = typeof opts.uid === 'function'
            ? opts.uid
            : (prefix) => prefix + '_' + crypto.randomUUID();
        fs.mkdirSync(path.dirname(this.file), { recursive: true });
        this.db = new DatabaseSync(this.file);
        try { fs.chmodSync(this.file, 0o600); } catch (_) { /* Windows / mounted volume */ }
        this.closed = false;
        this.execBusy('PRAGMA busy_timeout = 10000;');
        this.execBusy(`
            PRAGMA journal_mode = WAL;
            PRAGMA synchronous = FULL;
            PRAGMA foreign_keys = ON;
            PRAGMA trusted_schema = OFF;
        `);

        /*
         * client_id 必须允许 NULL。SQLite 的唯一索引会把多个空字符串视为同一个值，
         * 如果系统消息也落成 ''，每个会话最多只能存一条无 clientId 的消息。
         * 旧版开发库曾在字段上声明 NOT NULL；这里做一次原位迁移。
         */
        const existing = this.db.prepare(`
            SELECT sql FROM sqlite_master
            WHERE type = 'table' AND name = 'reliable_messages'
        `).get();
        if (existing && /client_id\s+TEXT\s+NOT\s+NULL/i.test(String(existing.sql || ''))) {
            this.transaction(() => {
                this.db.exec('ALTER TABLE reliable_messages RENAME TO reliable_messages_legacy');
                this.db.exec(`
                    CREATE TABLE reliable_messages (
                        message_id TEXT PRIMARY KEY,
                        chat_id TEXT NOT NULL,
                        sender_id TEXT NOT NULL,
                        client_id TEXT,
                        seq INTEGER NOT NULL,
                        payload_json TEXT NOT NULL,
                        created_at TEXT NOT NULL,
                        UNIQUE(chat_id, seq),
                        UNIQUE(chat_id, sender_id, client_id)
                    )
                `);
                this.db.exec(`
                    INSERT INTO reliable_messages
                        (message_id, chat_id, sender_id, client_id, seq, payload_json, created_at)
                    SELECT message_id, chat_id, sender_id, NULLIF(client_id, ''),
                           seq, payload_json, created_at
                    FROM reliable_messages_legacy
                `);
                this.db.exec('DROP TABLE reliable_messages_legacy');
            });
        }

        this.execBusy(`
            CREATE TABLE IF NOT EXISTS chat_sequence (
                chat_id TEXT PRIMARY KEY,
                last_seq INTEGER NOT NULL,
                updated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS reliable_messages (
                message_id TEXT PRIMARY KEY,
                chat_id TEXT NOT NULL,
                sender_id TEXT NOT NULL,
                client_id TEXT,
                seq INTEGER NOT NULL,
                payload_json TEXT NOT NULL,
                created_at TEXT NOT NULL,
                UNIQUE(chat_id, seq),
                UNIQUE(chat_id, sender_id, client_id)
            );

            CREATE INDEX IF NOT EXISTS reliable_messages_sync
                ON reliable_messages(chat_id, seq);

            CREATE TABLE IF NOT EXISTS device_cursors (
                user_id TEXT NOT NULL,
                device_id TEXT NOT NULL,
                chat_id TEXT NOT NULL,
                delivered_seq INTEGER NOT NULL DEFAULT 0,
                read_seq INTEGER NOT NULL DEFAULT 0,
                updated_at TEXT NOT NULL,
                PRIMARY KEY(user_id, device_id, chat_id)
            );

            CREATE TABLE IF NOT EXISTS message_events (
                sequence INTEGER PRIMARY KEY AUTOINCREMENT,
                event_id TEXT NOT NULL UNIQUE,
                type TEXT NOT NULL,
                entity_id TEXT NOT NULL,
                version INTEGER NOT NULL,
                payload_json TEXT NOT NULL,
                created_at TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS message_events_sync
                ON message_events(sequence);
        `);
    }

    execBusy(sql, attempts) {
        const max = Math.max(1, Number(attempts) || 120);
        for (let attempt = 0; attempt < max; attempt += 1) {
            try {
                this.db.exec(String(sql || ''));
                return;
            } catch (error) {
                const code = Number(error && error.errcode);
                if ((code !== 5 && code !== 6) || attempt + 1 >= max) throw error;
                Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 100);
            }
        }
    }

    transaction(work) {
        this.execBusy('BEGIN IMMEDIATE;');
        try {
            const result = work();
            this.execBusy('COMMIT;');
            return result;
        } catch (error) {
            try { this.execBusy('ROLLBACK;'); } catch (_) { /* preserve original error */ }
            throw error;
        }
    }

    appendEvent(type, entityId, version, payload, createdAt) {
        const eventId = this.uid('evt');
        const at = String(createdAt || this.now());
        this.db.prepare(`
            INSERT INTO message_events
                (event_id, type, entity_id, version, payload_json, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
        `).run(eventId, String(type || ''), String(entityId || ''),
            Number(version) || 0, stableJson(payload || {}), at);
        return eventId;
    }

    recordEvent(type, entityId, version, payload, createdAt) {
        return this.transaction(() =>
            this.appendEvent(type, entityId, version, payload, createdAt)
        );
    }

    ensureChatSequence(chatId, lastSeq) {
        const chat = String(chatId || '');
        const seq = Math.max(0, Math.floor(Number(lastSeq) || 0));
        if (!chat) return 0;
        const at = this.now();
        this.db.prepare(`
            INSERT INTO chat_sequence(chat_id, last_seq, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(chat_id) DO UPDATE SET
                last_seq = MAX(chat_sequence.last_seq, excluded.last_seq),
                updated_at = excluded.updated_at
        `).run(chat, seq, at);
        const row = this.db.prepare(
            'SELECT last_seq FROM chat_sequence WHERE chat_id = ?'
        ).get(chat);
        return row ? Number(row.last_seq) || 0 : 0;
    }

    reserveMessage(input) {
        const message = Object.assign({}, input || {});
        const chatId = String(message.chatId || '');
        const senderId = String(message.senderId || '');
        const clientId = String(message.clientId || '').slice(0, 80);
        const messageId = String(message.id || this.uid('m'));
        if (!chatId || !senderId) throw new Error('chatId and senderId are required');

        return this.transaction(() => {
            if (clientId) {
                const duplicate = this.db.prepare(`
                    SELECT * FROM reliable_messages
                    WHERE chat_id = ? AND sender_id = ? AND client_id = ?
                `).get(chatId, senderId, clientId);
                if (duplicate) {
                    return {
                        duplicate: true,
                        message: JSON.parse(duplicate.payload_json),
                        seq: Number(duplicate.seq),
                        eventId: ''
                    };
                }
            }

            const sameId = this.db.prepare(
                'SELECT * FROM reliable_messages WHERE message_id = ?'
            ).get(messageId);
            if (sameId) {
                return {
                    duplicate: true,
                    message: JSON.parse(sameId.payload_json),
                    seq: Number(sameId.seq),
                    eventId: ''
                };
            }

            const row = this.db.prepare(
                'SELECT last_seq FROM chat_sequence WHERE chat_id = ?'
            ).get(chatId);
            const seq = (row ? Number(row.last_seq) : 0) + 1;
            const createdAt = String(message.createdAt || this.now());
            const persisted = Object.assign({}, message, {
                id: messageId,
                chatId,
                senderId,
                seq,
                createdAt
            });
            if (clientId) persisted.clientId = clientId;

            this.db.prepare(`
                INSERT INTO chat_sequence(chat_id, last_seq, updated_at)
                VALUES (?, ?, ?)
                ON CONFLICT(chat_id) DO UPDATE SET
                    last_seq = excluded.last_seq,
                    updated_at = excluded.updated_at
            `).run(chatId, seq, createdAt);
            this.db.prepare(`
                INSERT INTO reliable_messages
                    (message_id, chat_id, sender_id, client_id, seq, payload_json, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            `).run(messageId, chatId, senderId, clientId || null, seq,
                stableJson(persisted), createdAt);
            const eventId = this.appendEvent(
                'message.created',
                messageId,
                seq,
                persisted,
                createdAt
            );
            return { duplicate: false, message: persisted, seq, eventId };
        });
    }

    messagesAfter(chatId, afterSeq, limit) {
        const cap = Math.min(500, Math.max(1, Number(limit) || 200));
        return this.db.prepare(`
            SELECT payload_json FROM reliable_messages
            WHERE chat_id = ? AND seq > ?
            ORDER BY seq ASC
            LIMIT ?
        `).all(String(chatId || ''), Math.max(0, Number(afterSeq) || 0), cap)
            .map((row) => JSON.parse(row.payload_json));
    }

    messagesBefore(chatId, beforeSeq, limit) {
        const cap = Math.min(500, Math.max(1, Number(limit) || 200));
        const before = Number(beforeSeq) > 0 ? Number(beforeSeq) : Number.MAX_SAFE_INTEGER;
        return this.db.prepare(`
            SELECT payload_json FROM reliable_messages
            WHERE chat_id = ? AND seq < ?
            ORDER BY seq DESC
            LIMIT ?
        `).all(String(chatId || ''), before, cap)
            .reverse()
            .map((row) => JSON.parse(row.payload_json));
    }

    lastSequence(chatId) {
        const row = this.db.prepare(
            'SELECT last_seq FROM chat_sequence WHERE chat_id = ?'
        ).get(String(chatId || ''));
        return row ? Number(row.last_seq) || 0 : 0;
    }

    deleteChatMessages(chatId) {
        return this.db.prepare(
            'DELETE FROM reliable_messages WHERE chat_id = ?'
        ).run(String(chatId || '')).changes;
    }

    ackDevice(userId, deviceId, chatId, seq) {
        const user = String(userId || '');
        const device = String(deviceId || '');
        const chat = String(chatId || '');
        const value = Math.max(0, Math.floor(Number(seq) || 0));
        if (!user || !device || !chat || !value) return false;
        const at = this.now();
        this.db.prepare(`
            INSERT INTO device_cursors
                (user_id, device_id, chat_id, delivered_seq, read_seq, updated_at)
            VALUES (?, ?, ?, ?, 0, ?)
            ON CONFLICT(user_id, device_id, chat_id) DO UPDATE SET
                delivered_seq = MAX(device_cursors.delivered_seq, excluded.delivered_seq),
                updated_at = excluded.updated_at
        `).run(user, device, chat, value, at);
        return true;
    }

    markDeviceRead(userId, deviceId, chatId, seq) {
        const user = String(userId || '');
        const device = String(deviceId || '');
        const chat = String(chatId || '');
        const value = Math.max(0, Math.floor(Number(seq) || 0));
        if (!user || !device || !chat || !value) return false;
        const at = this.now();
        this.db.prepare(`
            INSERT INTO device_cursors
                (user_id, device_id, chat_id, delivered_seq, read_seq, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(user_id, device_id, chat_id) DO UPDATE SET
                delivered_seq = MAX(device_cursors.delivered_seq, excluded.delivered_seq),
                read_seq = MAX(device_cursors.read_seq, excluded.read_seq),
                updated_at = excluded.updated_at
        `).run(user, device, chat, value, value, at);
        return true;
    }

    deviceCursor(userId, deviceId, chatId) {
        const row = this.db.prepare(`
            SELECT delivered_seq, read_seq, updated_at
            FROM device_cursors
            WHERE user_id = ? AND device_id = ? AND chat_id = ?
        `).get(String(userId || ''), String(deviceId || ''), String(chatId || ''));
        return row
            ? {
                deliveredSeq: Number(row.delivered_seq) || 0,
                readSeq: Number(row.read_seq) || 0,
                updatedAt: String(row.updated_at || '')
            }
            : { deliveredSeq: 0, readSeq: 0, updatedAt: '' };
    }

    eventsAfter(sequence, limit) {
        const cap = Math.min(1000, Math.max(1, Number(limit) || 200));
        return this.db.prepare(`
            SELECT sequence, event_id, type, entity_id, version, payload_json, created_at
            FROM message_events
            WHERE sequence > ?
            ORDER BY sequence ASC
            LIMIT ?
        `).all(Math.max(0, Number(sequence) || 0), cap).map((row) => ({
            sequence: Number(row.sequence),
            eventId: String(row.event_id),
            type: String(row.type),
            entityId: String(row.entity_id),
            version: Number(row.version),
            payload: JSON.parse(row.payload_json),
            createdAt: String(row.created_at)
        }));
    }

    close() {
        if (this.closed) return;
        this.closed = true;
        this.db.close();
    }
}

module.exports = { MessageReliabilityStore };
