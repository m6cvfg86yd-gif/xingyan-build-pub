'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { PaymentDatabase } = require('../lib/payment-database');
const { PaymentKeyRing } = require('../lib/payment-keyring');
const { openSecureValue } = require('../lib/payment-opening-balance');

const dataDir = path.resolve(process.argv[2] || process.env.DATA_DIR || path.join(__dirname, '..', 'data'));
const databaseFile = path.isAbsolute(process.argv[3] || '')
  ? path.resolve(process.argv[3])
  : path.join(dataDir, process.argv[3] || 'payments.sqlite3');

function readJson(file, fallback) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); }
  catch (_) { return fallback; }
}

function configuredKeyring() {
  let keys;
  if (process.env.PAYMENT_KEYS_JSON) {
    keys = JSON.parse(process.env.PAYMENT_KEYS_JSON);
  } else if (process.env.PAYMENT_KEYS_FILE) {
    keys = JSON.parse(fs.readFileSync(process.env.PAYMENT_KEYS_FILE, 'utf8'));
  } else {
    const secret = process.env.PAYMENT_KEY_BASE64
      || (process.env.PAYMENT_KEY_FILE
        ? fs.readFileSync(process.env.PAYMENT_KEY_FILE, 'utf8').trim()
        : '');
    keys = [{
      id: process.env.PAYMENT_KEY_ID || '',
      secret,
      active: true
    }];
  }
  if (!Array.isArray(keys) || !keys.length
      || !keys.every((row) => row && row.id && row.secret)) {
    throw new Error('PAYMENT_KEY_ID / PAYMENT_KEY_BASE64 (or PAYMENT_KEYS_JSON) is required');
  }
  return new PaymentKeyRing({
    activeKeyId: process.env.PAYMENT_ACTIVE_KEY_ID
      || keys.find((row) => row.active)?.id
      || keys[0].id,
    keys
  });
}

function bizBalanceOf(biz, userId) {
  const row = biz && biz.accounts && biz.accounts[userId];
  if (!row || row.enabled !== true) return { enabled: false, balance: 0 };
  return { enabled: true, balance: Number(row.balance) || 0 };
}

function main() {
  const secret = String(fs.readFileSync(path.join(dataDir, 'secret.key'), 'utf8')).trim();
  if (!secret) throw new Error('data/secret.key is empty');
  const usersFile = readJson(path.join(dataDir, 'users.json'), { users: [] });
  const users = Array.isArray(usersFile.users) ? usersFile.users : [];
  const sealedBiz = readJson(path.join(dataDir, 'biz.json'), { accounts: {} });
  const biz = openSecureValue(secret, 'biz.json', sealedBiz) || { accounts: {} };
  const existed = fs.existsSync(databaseFile);
  const database = new PaymentDatabase({
    databaseFile,
    keyring: configuredKeyring(),
    hmac: (payload) => crypto.createHmac('sha256', secret)
      .update('payment-ledger|' + payload).digest('hex'),
    uid: (prefix) => prefix + '_' + crypto.randomUUID(),
    now: () => new Date().toISOString()
  });
  try {
    const seeded = database.seedOpeningBalances(
      users,
      (id) => bizBalanceOf(biz, id),
      { at: new Date().toISOString() }
    );
    database.rebuild();
    const syncedUsers = users.map((user) => Object.assign({}, user, {
      balance: database.accountBalance('user:' + user.id)
    }));
    const reconciled = database.reconcile(
      syncedUsers,
      (id) => bizBalanceOf(biz, id)
    );
    console.log(JSON.stringify({
      ok: reconciled.ok,
      databaseFile,
      existed,
      seeded,
      users: users.length,
      ledgerEntries: reconciled.entries,
      integrity: reconciled.integrity,
      differences: reconciled.differences,
      ledgerTotalCents: reconciled.ledgerTotalCents
    }, null, 2));
    if (!reconciled.ok) process.exitCode = 2;
  } finally {
    database.close();
  }
}

try {
  main();
} catch (error) {
  console.error(String(error && error.stack || error));
  process.exitCode = 1;
}
