'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { PaymentLedger, cents, money } = require('../payment-ledger');

function storeKey(secret, name) {
  return crypto.createHmac('sha256', String(secret || '')).update('store:' + name).digest();
}

function openSecureValue(secret, name, value) {
  if (!value || typeof value !== 'object' || value.enc !== 1) return value;
  const decipher = crypto.createDecipheriv(
    'aes-256-gcm',
    storeKey(secret, name),
    Buffer.from(String(value.iv || ''), 'base64')
  );
  decipher.setAAD(Buffer.from('store:' + name, 'utf8'));
  decipher.setAuthTag(Buffer.from(String(value.tag || ''), 'base64'));
  return JSON.parse(Buffer.concat([
    decipher.update(Buffer.from(String(value.ct || ''), 'base64')),
    decipher.final()
  ]).toString('utf8'));
}

function sealSecureValue(secret, name, value) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', storeKey(secret, name), iv);
  cipher.setAAD(Buffer.from('store:' + name, 'utf8'));
  const ciphertext = Buffer.concat([
    cipher.update(Buffer.from(JSON.stringify(value), 'utf8')),
    cipher.final()
  ]);
  return {
    enc: 1,
    iv: iv.toString('base64'),
    tag: cipher.getAuthTag().toString('base64'),
    ct: ciphertext.toString('base64')
  };
}

function readJson(file, fallback) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (_) {
    return fallback;
  }
}

function writeJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temporary = file + '.' + process.pid + '.tmp';
  fs.writeFileSync(temporary, JSON.stringify(value), 'utf8');
  fs.renameSync(temporary, file);
}

function readSecureJson(dataDir, secret, name, fallback) {
  const stored = readJson(path.join(dataDir, name), null);
  if (stored == null) return fallback;
  return openSecureValue(secret, name, stored);
}

function writeSecureJson(dataDir, secret, name, value) {
  writeJson(path.join(dataDir, name), sealSecureValue(secret, name, value));
}

function acquireLock(dataDir) {
  const file = path.join(dataDir, 'payment-opening-balance.lock');
  let fd;
  try {
    fd = fs.openSync(file, 'wx');
  } catch (error) {
    if (error && error.code === 'EEXIST') {
      throw new Error('another payment opening-balance migration is active');
    }
    throw error;
  }
  fs.writeFileSync(fd, JSON.stringify({
    pid: process.pid,
    startedAt: new Date().toISOString()
  }));
  fs.fsyncSync(fd);
  fs.closeSync(fd);
  return () => {
    try {
      fs.unlinkSync(file);
    } catch (_) {
      /* already released */
    }
  };
}

function backupFiles(dataDir, names, backupDir) {
  if (!backupDir) return [];
  fs.mkdirSync(backupDir, { recursive: true });
  const copied = [];
  for (const name of names) {
    const source = path.join(dataDir, name);
    if (!fs.existsSync(source)) continue;
    const target = path.join(backupDir, name);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.copyFileSync(source, target);
    copied.push(name);
  }
  return copied;
}

function bizBalanceOf(biz, userId) {
  const row = biz && biz.accounts && biz.accounts[userId];
  if (!row || row.enabled !== true) return { enabled: false, balance: 0 };
  return { enabled: true, balance: money(cents(row.balance)) };
}

function walletDifference(ledger, user) {
  const ledgerBalance = ledger.accountBalance('user:' + user.id);
  const walletBalance = money(cents(user.balance));
  return {
    kind: 'wallet',
    userId: String(user.id),
    account: 'user:' + user.id,
    ledger: ledgerBalance,
    actual: walletBalance,
    difference: money(cents(walletBalance) - cents(ledgerBalance))
  };
}

function businessDifference(ledger, biz, user) {
  const actual = bizBalanceOf(biz, user.id);
  if (!actual.enabled) return null;
  const ledgerBalance = ledger.accountBalance('user:biz:' + user.id);
  if (cents(actual.balance) === cents(ledgerBalance)) return null;
  return {
    kind: 'business',
    userId: String(user.id),
    account: 'user:biz:' + user.id,
    ledger: ledgerBalance,
    actual: actual.balance,
    difference: money(cents(actual.balance) - cents(ledgerBalance))
  };
}

function reconcileRows(ledger, users, biz) {
  const rows = [];
  for (const user of users) {
    if (!user || !user.id) continue;
    const wallet = walletDifference(ledger, user);
    if (cents(wallet.difference) !== 0) rows.push(wallet);
    const business = businessDifference(ledger, biz, user);
    if (business && cents(business.difference) !== 0) rows.push(business);
  }
  return rows;
}

function reconcileLegacyLedger(options) {
  const opts = options || {};
  const dataDir = path.resolve(String(opts.dataDir || ''));
  const secret = String(opts.secret || '');
  if (!dataDir) throw new Error('dataDir is required');
  if (!secret) throw new Error('secret is required');
  const apply = opts.apply === true;
  const at = String(opts.at || '2026-11-13T00:00:00.000Z');
  const usersFile = readJson(path.join(dataDir, 'users.json'), { users: [] });
  const users = Array.isArray(usersFile.users) ? usersFile.users : [];
  const biz = readSecureJson(dataDir, secret, 'biz.json', { accounts: {} });
  const release = apply ? acquireLock(dataDir) : () => {};
  let sequence = 0;
  const ledger = new PaymentLedger({
    dataDir,
    journalName: 'money-journal.jsonl',
    stateName: 'payment-ledger-state.json',
    openSealed: (name, value) => openSecureValue(secret, name, value),
    sealValue: (name, value) => sealSecureValue(secret, name, value),
    readState: (name, fallback) => readSecureJson(dataDir, secret, name, fallback),
    writeState: (name, value) => writeSecureJson(dataDir, secret, name, value),
    hmac: (payload) => crypto.createHmac('sha256', secret)
      .update('payment-ledger|' + payload).digest('hex'),
    uid: (prefix) => prefix + '_' + Date.now().toString(36) + '_' + (++sequence).toString(36),
    now: () => at
  });
  try {
    ledger.rebuild();
    const planned = reconcileRows(ledger, users, biz);
    const report = {
      version: 1,
      ok: true,
      apply,
      at,
      wallets: users.length,
      differences: planned.length,
      walletDifferences: planned.filter((row) => row.kind === 'wallet').length,
      businessDifferences: planned.filter((row) => row.kind === 'business').length,
      recorded: 0,
      duplicates: 0,
      backupDir: '',
      backupFiles: [],
      before: ledger.reconcile(users, (id) => bizBalanceOf(biz, id)),
      samples: planned.slice(0, 30)
    };
    if (!apply) return report;

    const stamp = new Date().toISOString().replace(/[^0-9]/g, '');
    const backupDir = path.resolve(String(opts.backupDir ||
      path.join(dataDir, 'payment-opening-backups', stamp)));
    report.backupFiles = backupFiles(dataDir,
      ['money-journal.jsonl', 'payment-ledger-state.json', 'money-state.json', 'biz.json'],
      backupDir);
    report.backupDir = backupDir;

    for (const row of planned) {
      const ref = 'opening-2026-11-12:' + row.kind + ':' + row.userId;
      const delta = money(cents(row.actual) - cents(row.ledger));
      const systemAccount = row.kind === 'business'
        ? 'system:legacy-business-opening'
        : 'system:legacy-wallet-opening';
      const result = ledger.recordOnce({
        at,
        userId: row.userId,
        delta,
        before: row.ledger,
        after: row.actual,
        reason: row.kind === 'business'
          ? '11/12 经营账户历史余额迁移'
          : '11/12 零钱历史余额迁移',
        ref
      }, [
        { account: row.account, delta },
        { account: systemAccount, delta: -delta }
      ]);
      if (result.duplicate) report.duplicates += 1;
      else report.recorded += 1;
    }

    ledger.rebuild();
    const moneyState = readSecureJson(dataDir, secret, 'money-state.json', { users: {} });
    if (!moneyState.users || typeof moneyState.users !== 'object') moneyState.users = {};
    for (const user of users) {
      if (!user || !user.id) continue;
      moneyState.users[user.id] = { balance: money(cents(user.balance)), at };
      const business = bizBalanceOf(biz, user.id);
      if (business.enabled) {
        moneyState.users['biz:' + user.id] = { balance: business.balance, at };
      }
    }
    writeSecureJson(dataDir, secret, 'money-state.json', moneyState);

    const after = ledger.reconcile(users, (id) => bizBalanceOf(biz, id));
    report.after = after;
    report.ok = after.ok && after.differences.length === 0;
    return report;
  } finally {
    release();
  }
}

module.exports = {
  reconcileLegacyLedger,
  openSecureValue,
  sealSecureValue
};
