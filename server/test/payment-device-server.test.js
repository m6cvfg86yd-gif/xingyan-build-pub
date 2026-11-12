'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');
const { canonical } = require('../lib/shard-snapshot');

const SERVER_DIR = path.resolve(__dirname, '..');
const PASSWORD = 'PaymentDevice123!';

function freePort() {
  return new Promise((resolve, reject) => {
    const socket = net.createServer();
    socket.once('error', reject);
    socket.listen(0, '127.0.0.1', () => {
      const port = socket.address().port;
      socket.close(() => resolve(port));
    });
  });
}

async function call(base, method, endpoint, body, cookie) {
  const headers = { 'x-device-kind': 'phone' };
  if (cookie) headers.Cookie = cookie;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const response = await fetch(base + endpoint, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const text = await response.text();
  let envelope = {};
  try { envelope = text ? JSON.parse(text) : {}; } catch (_) { envelope = { raw: text }; }
  return {
    status: response.status,
    data: envelope.data === undefined ? envelope : envelope.data,
    headers: response.headers
  };
}

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-payment-device-server-'));
  const port = await freePort();
  const turnPort = await freePort();
  const base = 'http://127.0.0.1:' + port;
  const logs = [];
  let child;
  try {
    const salt = crypto.randomBytes(16).toString('hex');
    const user = {
      id: 'payment-device-user',
      username: 'payment_device',
      nickname: 'Payment Device',
      avatar: '',
      bio: '',
      phone: '',
      gender: 'secret',
      balance: 0,
      salt,
      passwordHash: crypto.scryptSync(PASSWORD, salt, 64).toString('hex'),
      createdAt: new Date().toISOString(),
      tokenVersion: 0,
      phoneSession: 0
    };
    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({ users: [user] }));
    fs.writeFileSync(path.join(dataDir, 'security.json'), JSON.stringify({ sliderLogin: 0 }));
    fs.writeFileSync(path.join(dataDir, 'ui.json'), JSON.stringify({ multiDevice: 1 }));
    child = spawn(process.execPath, ['server.js'], {
      cwd: SERVER_DIR,
      env: Object.assign({}, process.env, {
        DATA_DIR: dataDir,
        PORT: String(port),
        TURN_PORT: String(turnPort),
        CHRIS_LOCAL_ONLY: '1',
        AML_RUNTIME_ENABLED: '0'
      }),
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true
    });
    child.stdout.on('data', (chunk) => logs.push(chunk.toString()));
    child.stderr.on('data', (chunk) => logs.push(chunk.toString()));
    for (let i = 0; i < 160; i += 1) {
      if (child.exitCode !== null) throw new Error('测试服务提前退出：\n' + logs.join(''));
      try {
        if ((await fetch(base + '/api/health')).ok) break;
      } catch (_) { /* starting */ }
      await new Promise((resolve) => setTimeout(resolve, 100));
    }

    let response = await call(base, 'POST', '/api/login', {
      username: 'payment_device',
      password: PASSWORD
    });
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const rawCookie = response.headers.getSetCookie
      ? response.headers.getSetCookie()[0]
      : response.headers.get('set-cookie') || '';
    const cookie = rawCookie.split(';')[0];

    const device = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
    const publicKey = device.publicKey.export({ format: 'pem', type: 'spki' })
      .toString().trim();
    response = await call(base, 'POST', '/api/payment/devices/challenge', {
      deviceId: 'iphone-payment-1',
      publicKey
    }, cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const challenge = response.data.challenge;
    const tokenId = response.data.tokenId;
    assert.ok(challenge);
    assert.ok(tokenId);

    const payload = {
      purpose: 'payment-device-enrollment',
      challenge,
      tokenId,
      userId: user.id,
      deviceId: 'iphone-payment-1',
      publicKey
    };
    const signature = crypto.sign(
      'sha256',
      Buffer.from(canonical(payload)),
      device.privateKey
    ).toString('base64');
    response = await call(base, 'POST', '/api/payment/devices/enroll', {
      challenge,
      signature,
      last4: '4242'
    }, cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(response.data.tokenId, tokenId);
    assert.strictEqual(response.data.deviceId, 'iphone-payment-1');
    assert.strictEqual(response.data.last4, '4242');

    const vaultText = fs.readFileSync(
      path.join(dataDir, 'payment-token-vault.json'),
      'utf8'
    );
    assert.ok(vaultText.includes('BEGIN PUBLIC KEY'));
    assert.strictEqual(vaultText.includes('BEGIN PRIVATE KEY'), false);

    response = await call(base, 'POST', '/api/payment/devices/enroll', {
      challenge,
      signature,
      last4: '4242'
    }, cookie);
    assert.strictEqual(response.status, 401);

    response = await call(base, 'POST', '/api/payment/devices/revoke', {
      tokenId
    }, cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(response.data.status, 'revoked');

    console.log('payment-device-server: passed');
  } finally {
    if (child && child.exitCode === null) child.kill();
    await new Promise((resolve) => setTimeout(resolve, 200));
    fs.rmSync(dataDir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
