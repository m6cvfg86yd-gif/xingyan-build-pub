'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');
const { PaymentLedger } = require('../payment-ledger');

const SERVER_DIR = path.resolve(__dirname, '..');

function freePort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const port = server.address().port;
      server.close(() => resolve(port));
    });
  });
}

function secureKey(secret, name) {
  return crypto.createHmac('sha256', secret).update('store:' + name).digest();
}

function sealValue(secret, name, value) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', secureKey(secret, name), iv);
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

function openSealed(secret, name, stored) {
  if (!stored || stored.enc !== 1) return stored;
  const decipher = crypto.createDecipheriv(
    'aes-256-gcm',
    secureKey(secret, name),
    Buffer.from(stored.iv, 'base64')
  );
  decipher.setAAD(Buffer.from('store:' + name, 'utf8'));
  decipher.setAuthTag(Buffer.from(stored.tag, 'base64'));
  return JSON.parse(Buffer.concat([
    decipher.update(Buffer.from(stored.ct, 'base64')),
    decipher.final()
  ]).toString('utf8'));
}

async function waitForHealth(base, child, logs) {
  for (let attempt = 0; attempt < 160; attempt += 1) {
    if (child.exitCode !== null) {
      throw new Error('server exited before health check:\n' + logs.join(''));
    }
    try {
      if ((await fetch(base + '/api/health')).ok) return;
    } catch (_) {
      /* server is still starting */
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('server health check timed out:\n' + logs.join(''));
}

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-ledger-startup-'));
  const port = await freePort();
  const turnPort = await freePort();
  const secret = crypto.randomBytes(32).toString('hex');
  const logs = [];
  let child = null;
  try {
    fs.writeFileSync(path.join(dataDir, 'secret.key'), secret);
    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({
      users: [{
        id: 'u_ledger_startup',
        username: 'ledger_startup',
        nickname: 'Ledger Startup',
        balance: 10,
        createdAt: '2026-11-12T00:00:00.000Z',
        tokenVersion: 0
      }]
    }));
    fs.writeFileSync(path.join(dataDir, 'security.json'), JSON.stringify({
      sliderLogin: 0,
      allowRecharge: 0
    }));
    fs.writeFileSync(path.join(dataDir, 'ui.json'), JSON.stringify({ multiDevice: 1 }));

    const state = {};
    let sequence = 0;
    const ledger = new PaymentLedger({
      dataDir,
      openSealed: (name, stored) => openSealed(secret, name, stored),
      sealValue: (name, value) => sealValue(secret, name, value),
      readState: (name, fallback) => state[name] || fallback,
      writeState: (name, value) => {
        state[name] = JSON.parse(JSON.stringify(value));
        fs.writeFileSync(path.join(dataDir, name), JSON.stringify(value));
      },
      hmac: (payload) => crypto.createHmac('sha256', secret)
        .update('payment-ledger|' + payload).digest('hex'),
      uid: (prefix) => prefix + '_' + (++sequence),
      now: () => '2026-11-12T01:00:00.000Z'
    });
    ledger.record({
      userId: 'u_ledger_startup',
      before: 0,
      after: 10,
      reason: 'startup fixture',
      ref: 'startup-funding'
    }, [
      { account: 'user:u_ledger_startup', delta: 1000 },
      { account: 'system:external-settlement', delta: -1000 }
    ]);

    child = spawn(process.execPath, ['server.js'], {
      cwd: SERVER_DIR,
      env: Object.assign({}, process.env, {
        DATA_DIR: dataDir,
        PORT: String(port),
        TURN_PORT: String(turnPort),
        CHRIS_LOCAL_ONLY: '1',
        SHARD_SHADOW_ENABLED: '0',
        ADMIN_PASSWORD: 'ledger-startup-test-admin'
      }),
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true
    });
    child.stdout.on('data', (chunk) => logs.push(chunk.toString()));
    child.stderr.on('data', (chunk) => logs.push(chunk.toString()));
    await waitForHealth('http://127.0.0.1:' + port, child, logs);
    assert.ok(logs.join('').includes('[支付账本] 启动校验通过'), logs.join(''));
  } finally {
    if (child && child.exitCode === null) {
      child.kill();
      await new Promise((resolve) => {
        const timer = setTimeout(resolve, 3000);
        child.once('exit', () => {
          clearTimeout(timer);
          resolve();
        });
      });
    }
    fs.rmSync(dataDir, { recursive: true, force: true });
  }
}

main().then(() => {
  console.log('payment-ledger-startup: passed');
}).catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
