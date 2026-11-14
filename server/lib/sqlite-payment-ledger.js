'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { DatabaseSync } = require('node:sqlite');

function cents(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) return NaN;
  return Math.round(number * 100);
}

function money(value) {
  return Math.round(Number(value) || 0) / 100;
}

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

class SqlitePaymentLedger {
  constructor(options) {
    const opts = options || {};
    this.file = String(opts.databaseFile || opts.file || '');
    if (!this.file) throw new Error('payment database file is required');
    this.now = typeof opts.now === 'function' ? opts.now : () => new Date().toISOString();
    this.uid = typeof opts.uid === 'function'
      ? opts.uid
      : (prefix) => prefix + '_' + crypto.randomUUID();
    this.hmac = typeof opts.hmac === 'function' ? opts.hmac : null;
    if (!this.hmac) throw new Error('payment database HMAC signer is required');
    fs.mkdirSync(path.dirname(this.file), { recursive: true });
    this.db = new DatabaseSync(this.file);
    try { fs.chmodSync(this.file, 0o600); } catch (_) { /* Windows / mounted volume */ }
    this.closed = false;
    this.db.exec(`
      PRAGMA journal_mode = WAL;
      PRAGMA synchronous = FULL;
      PRAGMA foreign_keys = ON;
      PRAGMA busy_timeout = 10000;
      PRAGMA trusted_schema = OFF;

      CREATE TABLE IF NOT EXISTS payment_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS payment_accounts (
        account TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        currency TEXT NOT NULL DEFAULT 'CNY',
        balance_cents INTEGER NOT NULL DEFAULT 0,
        version INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL
      );

      CREATE INDEX IF NOT EXISTS payment_accounts_user
        ON payment_accounts(user_id, currency);

      CREATE TABLE IF NOT EXISTS payment_ledger (
        sequence INTEGER PRIMARY KEY AUTOINCREMENT,
        id TEXT NOT NULL UNIQUE,
        at TEXT NOT NULL,
        user_id TEXT NOT NULL,
        delta_cents INTEGER NOT NULL,
        before_cents INTEGER NOT NULL,
        after_cents INTEGER NOT NULL,
        reason TEXT NOT NULL DEFAULT '',
        ref TEXT NOT NULL DEFAULT '',
        idempotency_key TEXT UNIQUE,
        postings_json TEXT NOT NULL,
        prev_hash TEXT NOT NULL,
        hash TEXT NOT NULL
      );

      CREATE INDEX IF NOT EXISTS payment_ledger_user_time
        ON payment_ledger(user_id, at, sequence);

      CREATE INDEX IF NOT EXISTS payment_ledger_ref
        ON payment_ledger(ref);
    `);
    this.ensureMeta('ledger_sequence', '0');
    this.ensureMeta('ledger_last_hash', '');
    this.ensureMeta('schema_version', '1');
  }

  ensureMeta(key, value) {
    this.db.prepare(`
      INSERT INTO payment_meta(key, value) VALUES(?, ?)
      ON CONFLICT(key) DO NOTHING
    `).run(String(key), String(value));
  }

  getMeta(key) {
    const row = this.db.prepare('SELECT value FROM payment_meta WHERE key = ?').get(String(key));
    return row ? String(row.value) : '';
  }

  setMeta(key, value) {
    this.db.prepare(`
      INSERT INTO payment_meta(key, value) VALUES(?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value
    `).run(String(key), String(value));
  }

  close() {
    if (this.closed) return;
    this.closed = true;
    this.db.close();
  }

  backupTo(targetFile) {
    const target = String(targetFile || '');
    if (!target) throw new Error('payment backup target is required');
    fs.mkdirSync(path.dirname(target), { recursive: true });
    this.db.prepare('VACUUM INTO ?').run(target);
    return {
      file: target,
      size: fs.statSync(target).size,
      at: this.now()
    };
  }

  transaction(work) {
    this.db.exec('BEGIN IMMEDIATE');
    try {
      const value = work();
      this.db.exec('COMMIT');
      return value;
    } catch (error) {
      try { this.db.exec('ROLLBACK'); } catch (_) { /* preserve original error */ }
      throw error;
    }
  }

  normalizePostings(postings) {
    if (!Array.isArray(postings) || postings.length < 2) {
      throw new Error('账本分录至少需要借贷两个账户');
    }
    const merged = new Map();
    for (const posting of postings) {
      const account = String(posting && posting.account || '').trim();
      const delta = posting && posting.deltaCents !== undefined
        ? Number(posting.deltaCents)
        : cents(posting && posting.delta);
      if (!account || !Number.isSafeInteger(delta)) {
        throw new Error('账本分录账户或金额不合法');
      }
      merged.set(account, (merged.get(account) || 0) + delta);
    }
    const lines = Array.from(merged.entries())
      .filter(([, delta]) => delta !== 0)
      .map(([account, deltaCents]) => ({ account, deltaCents }));
    if (lines.length < 2) throw new Error('账本分录不能只有单边');
    const total = lines.reduce((sum, line) => sum + line.deltaCents, 0);
    if (total !== 0) throw new Error('账本借贷不平：' + total + ' 分');
    return lines;
  }

  ensureAccount(account, userId, currency) {
    this.db.prepare(`
      INSERT INTO payment_accounts(account, user_id, currency, balance_cents, version, updated_at)
      VALUES(?, ?, ?, 0, 0, ?)
      ON CONFLICT(account) DO NOTHING
    `).run(String(account), String(userId || account), String(currency || 'CNY'), this.now());
  }

  accountRow(account) {
    return this.db.prepare(`
      SELECT account, user_id, currency, balance_cents, version, updated_at
      FROM payment_accounts WHERE account = ?
    `).get(String(account)) || null;
  }

  accountBalance(account, currency) {
    const row = this.accountRow(account);
    if (!row || (currency && row.currency !== currency)) return 0;
    return money(row.balance_cents);
  }

  accountBalanceCents(account, currency) {
    const row = this.accountRow(account);
    if (!row || (currency && row.currency !== currency)) return 0;
    return Number(row.balance_cents);
  }

  hashRecord(record) {
    return this.hmac(stableJson({
      id: record.id,
      sequence: record.sequence,
      at: record.at,
      userId: record.userId,
      deltaCents: record.deltaCents,
      beforeCents: record.beforeCents,
      afterCents: record.afterCents,
      reason: record.reason,
      ref: record.ref,
      idempotencyKey: record.idempotencyKey || '',
      postings: record.postings,
      prevHash: record.prevHash
    }));
  }

  recordForRef(ref) {
    if (!ref) return null;
    const row = this.db.prepare(`
      SELECT * FROM payment_ledger WHERE idempotency_key = ?
    `).get(String(ref));
    return row ? this.publicRecord(row) : null;
  }

  publicRecord(row) {
    if (!row) return null;
    return {
      id: String(row.id),
      sequence: Number(row.sequence),
      at: String(row.at),
      userId: String(row.user_id),
      delta: money(row.delta_cents),
      before: money(row.before_cents),
      after: money(row.after_cents),
      reason: String(row.reason || ''),
      ref: String(row.ref || ''),
      idempotencyKey: String(row.idempotency_key || ''),
      postings: JSON.parse(String(row.postings_json || '[]')),
      prevHash: String(row.prev_hash || ''),
      hash: String(row.hash || '')
    };
  }

  recordLocked(meta, postings, idempotencyKey) {
    const row = meta || {};
    const lines = this.normalizePostings(postings);
    const userId = String(row.userId || 'system');
    const currency = String(row.currency || 'CNY');
    const userAccount = lines.find((line) =>
      line.account === 'user:' + userId
      || line.account === 'user:biz:' + userId
    );
    const primaryAccount = userAccount || lines[0];
    this.ensureAccount(primaryAccount.account, userId, currency);
    const before = this.accountBalanceCents(primaryAccount.account, currency);

    const sequence = Number(this.getMeta('ledger_sequence') || 0) + 1;
    const record = {
      id: this.uid('led'),
      sequence,
      at: String(row.at || this.now()),
      userId,
      deltaCents: primaryAccount.deltaCents,
      beforeCents: before,
      afterCents: before + primaryAccount.deltaCents,
      reason: String(row.reason || ''),
      ref: String(row.ref || ''),
      idempotencyKey: idempotencyKey ? String(idempotencyKey) : '',
      postings: lines,
      prevHash: String(this.getMeta('ledger_last_hash') || '')
    };
    record.hash = this.hashRecord(record);

    const updateAccount = this.db.prepare(`
      UPDATE payment_accounts
      SET balance_cents = balance_cents + ?, version = version + 1, updated_at = ?
      WHERE account = ?
    `);
    for (const line of lines) {
      this.ensureAccount(line.account, this.accountOwner(line.account), currency);
      const current = this.accountBalanceCents(line.account, currency);
      const next = current + line.deltaCents;
      if (line.account.startsWith('user:') && next < 0) {
        throw new Error('余额不足或账本账户不能为负数：' + line.account);
      }
      updateAccount.run(line.deltaCents, record.at, line.account);
    }

    this.db.prepare(`
      INSERT INTO payment_ledger(
        id, at, user_id, delta_cents, before_cents, after_cents, reason, ref,
        idempotency_key, postings_json, prev_hash, hash
      ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      record.id,
      record.at,
      record.userId,
      record.deltaCents,
      record.beforeCents,
      record.afterCents,
      record.reason,
      record.ref,
      record.idempotencyKey || null,
      stableJson(record.postings),
      record.prevHash,
      record.hash
    );
    this.setMeta('ledger_sequence', String(record.sequence));
    this.setMeta('ledger_last_hash', record.hash);
    return record;
  }

  accountOwner(account) {
    if (account.startsWith('user:biz:')) return 'biz:' + account.slice('user:biz:'.length);
    if (account.startsWith('user:')) return account.slice('user:'.length);
    return account;
  }

  record(meta, postings) {
    return this.transaction(() => this.recordLocked(meta, postings, ''));
  }

  recordOnce(meta, postings) {
    const ref = String(meta && meta.ref || '');
    if (!ref) throw new Error('idempotent ledger record requires ref');
    try {
      return this.transaction(() => {
        const existing = this.recordForRef(ref);
        if (existing) return { duplicate: true, record: existing };
        return {
          duplicate: false,
          record: this.recordLocked(meta, postings, ref)
        };
      });
    } catch (error) {
      if (/UNIQUE constraint failed/i.test(String(error && error.message || error))) {
        const existing = this.recordForRef(ref);
        if (existing) return { duplicate: true, record: existing };
      }
      throw error;
    }
  }

  apply(entry, delta, reason, ref) {
    const row = entry || {};
    const deltaCents = cents(delta);
    if (!row.userId || !Number.isSafeInteger(deltaCents) || deltaCents === 0) {
      throw new Error('账本记账参数不合法');
    }
    const counterAccount = String(row.counterAccount || 'system:unclassified');
    return this.record({
      at: row.at,
      userId: row.userId,
      reason,
      ref
    }, [
      { account: 'user:' + row.userId, deltaCents },
      { account: counterAccount, deltaCents: -deltaCents }
    ]);
  }

  applyDelta(input) {
    const row = input || {};
    const account = String(row.account || ('user:' + String(row.userId || '')));
    const deltaCents = Number.isSafeInteger(Number(row.deltaCents))
      ? Number(row.deltaCents)
      : cents(row.delta);
    if (!row.userId || !account || !Number.isSafeInteger(deltaCents) || deltaCents === 0) {
      throw new Error('账本记账参数不合法');
    }
    const counterAccount = String(row.counterAccount || 'system:unclassified');
    const postings = [
      { account, deltaCents },
      { account: counterAccount, deltaCents: -deltaCents }
    ];
    const opts = {
      at: row.at,
      userId: String(row.userId),
      currency: String(row.currency || 'CNY'),
      reason: String(row.reason || ''),
      ref: String(row.ref || '')
    };
    if (row.idempotent) {
      const result = this.recordOnce(opts, postings);
      const stored = result.record;
      return {
        duplicate: result.duplicate,
        record: stored,
        balance: this.accountBalance(account, opts.currency),
        before: stored.before === undefined ? money(stored.beforeCents) : stored.before,
        delta: stored.delta === undefined ? money(stored.deltaCents) : stored.delta,
        after: stored.after === undefined ? money(stored.afterCents) : stored.after
      };
    }
    const record = this.record(opts, postings);
    return {
      duplicate: false,
      record,
      balance: this.accountBalance(account, opts.currency),
      before: money(record.beforeCents),
      delta: money(record.deltaCents),
      after: money(record.afterCents)
    };
  }

  entriesForUser(userId, limit) {
    const id = String(userId || '');
    if (!id) return [];
    const max = Math.min(500, Math.max(1, Number(limit) || 100));
    const rows = this.db.prepare(`
      SELECT * FROM payment_ledger
      WHERE user_id = ? OR user_id = ?
      ORDER BY sequence DESC
      LIMIT ?
    `).all(id, 'biz:' + id, max);
    const accounts = new Set(['user:' + id, 'user:biz:' + id]);
    return rows.map((row) => this.publicRecord(row))
      .map((record) => {
        const posting = record.postings.find((line) => accounts.has(line.account));
        if (!posting) return null;
        return {
          id: record.id,
          at: record.at,
          delta: money(posting.deltaCents),
          direction: posting.deltaCents >= 0 ? 'in' : 'out',
          before: record.before,
          after: record.after,
          reason: record.reason,
          ref: record.ref
        };
      })
      .filter(Boolean);
  }

  verifyIntegrity() {
    const failures = [];
    let expectedPrev = '';
    let checked = 0;
    const rows = this.db.prepare('SELECT * FROM payment_ledger ORDER BY sequence ASC').all();
    for (const row of rows) {
      const record = this.publicRecord(row);
      record.deltaCents = cents(record.delta);
      record.beforeCents = cents(record.before);
      record.afterCents = cents(record.after);
      checked += 1;
      if (record.prevHash !== expectedPrev) {
        failures.push({ id: record.id, code: 'broken-chain', at: record.at });
      }
      if (this.hashRecord(record) !== record.hash) {
        failures.push({ id: record.id, code: 'bad-hmac', at: record.at });
      }
      expectedPrev = record.hash;
    }
    if (expectedPrev !== String(this.getMeta('ledger_last_hash') || '')) {
      failures.push({ id: 'meta', code: 'tail-mismatch', at: this.now() });
    }
    return { ok: failures.length === 0, checked, failures };
  }

  reconcile(users, bizBalanceOf) {
    const differences = [];
    for (const user of users || []) {
      if (!user || !user.id) continue;
      const actual = cents(user.balance);
      const expected = this.accountBalanceCents('user:' + user.id);
      if (actual !== expected) {
        differences.push({
          kind: 'wallet',
          userId: user.id,
          username: user.username || '',
          balance: money(actual),
          ledger: money(expected),
          difference: money(actual - expected)
        });
      }
      if (typeof bizBalanceOf === 'function') {
        const biz = bizBalanceOf(user.id);
        if (biz && biz.enabled) {
          const bizActual = cents(biz.balance);
          const bizExpected = this.accountBalanceCents('user:biz:' + user.id);
          if (bizActual !== bizExpected) {
            differences.push({
              kind: 'business',
              userId: user.id,
              username: user.username || '',
              balance: money(bizActual),
              ledger: money(bizExpected),
              difference: money(bizActual - bizExpected)
            });
          }
        }
      }
    }
    const totals = this.db.prepare(`
      SELECT COALESCE(SUM(balance_cents), 0) AS total FROM payment_accounts
    `).get();
    const integrity = this.verifyIntegrity();
    const ledgerTotalCents = Number(totals && totals.total) || 0;
    return {
      ok: differences.length === 0 && ledgerTotalCents === 0 && integrity.ok,
      checkedAt: this.now(),
      entries: Number(this.getMeta('ledger_sequence') || 0),
      differences,
      integrity,
      ledgerTotalCents
    };
  }

  rebuild() {
    const result = this.verifyIntegrity();
    if (!result.ok) {
      throw new Error('SQLite 支付账本完整性校验失败：'
        + result.failures.map((row) => row.code).join(','));
    }
    return this.balanceSnapshot();
  }

  balanceSnapshot() {
    const accounts = {};
    for (const row of this.db.prepare('SELECT account, balance_cents FROM payment_accounts').all()) {
      accounts[String(row.account)] = money(row.balance_cents);
    }
    return {
      accounts,
      entries: Number(this.getMeta('ledger_sequence') || 0),
      lastHash: String(this.getMeta('ledger_last_hash') || '')
    };
  }

  seedOpeningBalances(users, bizBalanceOf, options) {
    const opts = options || {};
    return this.transaction(() => {
      if (this.getMeta('opening_balances_v1') === 'done') {
        return { duplicate: true, recorded: 0, duplicates: 0 };
      }
      let recorded = 0;
      for (const user of users || []) {
        if (!user || !user.id) continue;
        const wallet = cents(user.balance);
        if (wallet > 0) {
          this.recordLocked({
            at: opts.at,
            userId: String(user.id),
            reason: '支付数据库首次启用：历史零钱迁移',
            ref: 'opening-v1:wallet:' + user.id
          }, [
            { account: 'user:' + user.id, deltaCents: wallet },
            { account: 'system:legacy-opening', deltaCents: -wallet }
          ], 'opening-v1:wallet:' + user.id);
          recorded += 1;
        }
        if (typeof bizBalanceOf === 'function') {
          const biz = bizBalanceOf(user.id);
          const business = biz && biz.enabled ? cents(biz.balance) : 0;
          if (business > 0) {
            this.recordLocked({
              at: opts.at,
              userId: 'biz:' + user.id,
              reason: '支付数据库首次启用：历史经营账户迁移',
              ref: 'opening-v1:business:' + user.id
            }, [
              { account: 'user:biz:' + user.id, deltaCents: business },
              { account: 'system:legacy-business-opening', deltaCents: -business }
            ], 'opening-v1:business:' + user.id);
            recorded += 1;
          }
        }
      }
      this.setMeta('opening_balances_v1', 'done');
      return { duplicate: false, recorded, duplicates: 0 };
    });
  }
}

module.exports = {
  SqlitePaymentLedger,
  cents,
  money,
  stableJson
};
