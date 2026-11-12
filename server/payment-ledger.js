'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

function cents(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) return NaN;
  return Math.round(number * 100);
}

function money(value) {
  return Math.round(Number(value) || 0) / 100;
}

class PaymentLedger {
  constructor(options) {
    this.dataDir = options.dataDir;
    this.journalName = options.journalName || 'money-journal.jsonl';
    this.stateName = options.stateName || 'payment-ledger-state.json';
    this.openSealed = options.openSealed;
    this.sealValue = options.sealValue;
    this.readState = options.readState;
    this.writeState = options.writeState;
    this.hmac = options.hmac;
    this.uid = options.uid;
    this.now = options.now;
    this.state = this.loadState();
  }

  journalPath() {
    return path.join(this.dataDir, this.journalName);
  }

  emptyState() {
    return { version: 1, accounts: {}, entries: 0, lastAt: '', lastId: '', lastHash: '' };
  }

  normalizePostings(postings) {
    if (!Array.isArray(postings) || postings.length < 2) {
      throw new Error('账本分录至少需要借贷两个账户');
    }
    const merged = new Map();
    for (const posting of postings) {
      const account = String(posting && posting.account || '').trim();
      const delta = cents(posting && posting.delta);
      if (!account || !Number.isFinite(delta)) {
        throw new Error('账本分录账户或金额不合法');
      }
      merged.set(account, (merged.get(account) || 0) + delta);
    }
    const lines = Array.from(merged.entries())
      .filter(([, delta]) => delta !== 0)
      .map(([account, delta]) => ({ account, delta }));
    const total = lines.reduce((sum, line) => sum + line.delta, 0);
    if (total !== 0) throw new Error('账本借贷不平：' + total + ' 分');
    return lines;
  }

  loadState() {
    try {
      const state = this.readState(this.stateName, this.emptyState());
      if (!state || typeof state !== 'object') return this.emptyState();
      if (!state.accounts || typeof state.accounts !== 'object') state.accounts = {};
      state.version = 1;
      state.entries = Number(state.entries) || 0;
      return state;
    } catch (error) {
      return this.emptyState();
    }
  }

  appendLine(entry) {
    const file = this.journalPath();
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const line = JSON.stringify(this.sealValue(this.journalName, entry)) + '\n';
    const fd = fs.openSync(file, 'a');
    try {
      fs.writeSync(fd, line, null, 'utf8');
      fs.fsyncSync(fd);
    } finally {
      fs.closeSync(fd);
    }
  }

  apply(entry, delta, reason, ref) {
    const amountCents = cents(delta);
    if (!entry || !entry.userId || !Number.isFinite(amountCents) || amountCents === 0) {
      throw new Error('账本记账参数不合法');
    }
    const counterAccount = String(entry.counterAccount || 'system:unclassified');
    const postings = [
      { account: 'user:' + entry.userId, delta: money(amountCents) },
      { account: counterAccount, delta: -money(amountCents) }
    ];
    return this.record({
      at: entry.at,
      userId: entry.userId,
      delta: money(amountCents),
      before: entry.before,
      after: entry.after,
      reason,
      ref
    }, postings);
  }

  record(meta, postings) {
    const lines = this.normalizePostings(postings);
    const record = {
      id: this.uid('led'),
      at: meta.at || this.now(),
      userId: meta.userId || 'system',
      delta: Number(meta.delta) || 0,
      before: meta.before,
      after: meta.after,
      reason: meta.reason || '',
      ref: meta.ref || '',
      postings: lines
    };
    record.prevHash = String(this.state.lastHash || '');
    record.hash = this.hashRecord(record);
    this.appendLine(record);
    for (const posting of lines) {
      this.state.accounts[posting.account] =
        (Number(this.state.accounts[posting.account]) || 0) + posting.delta;
    }
    this.state.entries += 1;
    this.state.lastAt = record.at;
    this.state.lastId = record.id;
    this.state.lastHash = record.hash;
    try {
      this.writeState(this.stateName, this.state);
    } catch (error) {
      /* 日志已经 fsync 成功，状态只是索引；下次启动会从日志重建。 */
      this.lastStateError = String(error && error.message || error);
    }
    return record;
  }

  hashRecord(record) {
    if (typeof this.hmac !== 'function') return '';
    const payload = JSON.stringify({
      id: record.id,
      at: record.at,
      userId: record.userId,
      delta: record.delta,
      before: record.before,
      after: record.after,
      reason: record.reason,
      ref: record.ref,
      postings: record.postings,
      prevHash: record.prevHash || ''
    });
    return this.hmac(payload);
  }

  readEntries() {
    const file = this.journalPath();
    if (!fs.existsSync(file)) return [];
    const rows = [];
    for (const raw of fs.readFileSync(file, 'utf8').split('\n')) {
      if (!raw.trim()) continue;
      const stored = JSON.parse(raw);
      rows.push(this.openSealed(this.journalName, stored));
    }
    return rows;
  }

  entriesForUser(userId, limit) {
    const account = 'user:' + String(userId || '');
    if (!userId) return [];
    const max = Math.min(500, Math.max(1, Number(limit) || 100));
    const rows = [];
    for (const record of this.readEntries()) {
      const posting = this.postingsOf(record).find((line) => line.account === account);
      if (!posting) continue;
      rows.push({
        id: record.id || '',
        at: record.at || '',
        delta: money(posting.delta),
        direction: posting.delta >= 0 ? 'in' : 'out',
        before: Number(record.before || 0),
        after: Number(record.after || 0),
        reason: record.reason || '',
        ref: record.ref || ''
      });
    }
    return rows.sort((a, b) => String(b.at).localeCompare(String(a.at))).slice(0, max);
  }

  postingsOf(record) {
    if (record && Array.isArray(record.postings) && record.postings.length >= 2) {
      return this.normalizePostings(record.postings);
    }
    const amount = cents(record && record.delta);
    if (!record || !record.userId || !Number.isFinite(amount) || amount === 0) return [];
    return [
      { account: 'user:' + record.userId, delta: amount },
      { account: 'system:legacy', delta: -amount }
    ];
  }

  rebuild() {
    const state = this.emptyState();
    for (const record of this.readEntries()) {
      for (const posting of this.postingsOf(record)) {
        state.accounts[posting.account] =
          (Number(state.accounts[posting.account]) || 0) + posting.delta;
      }
      state.entries += 1;
      state.lastAt = record.at || state.lastAt;
      state.lastId = record.id || state.lastId;
      if (record && record.hash) state.lastHash = record.hash;
    }
    this.state = state;
    this.writeState(this.stateName, state);
    return state;
  }

  accountBalance(account) {
    /* 零钱和经营账户都是用户资产账户，统一采用「借增贷减」的正向余额。
       经营账户收入记正数，提到零钱时经营账户记负数、零钱记正数。 */
    return money(this.state.accounts[account] || 0);
  }

  verifyIntegrity() {
    let expectedPrev = '';
    const failures = [];
    let checked = 0;
    for (const record of this.readEntries()) {
      if (!record || !record.hash) continue;
      checked += 1;
      if (String(record.prevHash || '') !== expectedPrev) {
        failures.push({ id: record.id || '', code: 'broken-chain', at: record.at || '' });
      }
      const expectedHash = this.hashRecord(record);
      if (!expectedHash || expectedHash !== record.hash) {
        failures.push({ id: record.id || '', code: 'bad-hmac', at: record.at || '' });
      }
      expectedPrev = record.hash;
    }
    return { ok: failures.length === 0, checked, failures };
  }

  reconcile(users, bizBalanceOf) {
    const rows = [];
    for (const user of users || []) {
      if (!user || !user.id) continue;
      const walletExpected = this.accountBalance('user:' + user.id);
      const walletActual = money(cents(user.balance));
      if (walletExpected !== walletActual) {
        rows.push({
          kind: 'wallet',
          userId: user.id,
          username: user.username || '',
          balance: walletActual,
          ledger: walletExpected,
          difference: money(cents(walletActual) - cents(walletExpected))
        });
      }
      if (typeof bizBalanceOf === 'function') {
        const biz = bizBalanceOf(user.id);
        if (biz && biz.enabled) {
          const bizExpected = this.accountBalance('user:biz:' + user.id);
          const bizActual = money(cents(biz.balance));
          if (bizExpected !== bizActual) {
            rows.push({
              kind: 'business',
              userId: user.id,
              username: user.username || '',
              balance: bizActual,
              ledger: bizExpected,
              difference: money(cents(bizActual) - cents(bizExpected))
            });
          }
        }
      }
    }
    const total = Object.values(this.state.accounts).reduce((sum, value) => sum + (Number(value) || 0), 0);
    const integrity = this.verifyIntegrity();
    return {
      ok: rows.length === 0 && total === 0 && integrity.ok,
      checkedAt: this.now(),
      entries: this.state.entries,
      differences: rows,
      integrity,
      ledgerTotalCents: total
    };
  }
}

module.exports = { PaymentLedger, cents, money };
