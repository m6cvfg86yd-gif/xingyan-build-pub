'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const SERVER_DIR = path.resolve(__dirname, '..');
const PASSWORD = 'VirtualCard1027!';
const SERVER_SECRET = 'virtual-card-system-secret';
const ID_CARD = '11010519491231002X';

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

function luhn(value) {
  let sum = 0;
  for (let i = 0; i < value.length; i += 1) {
    let n = Number(value[value.length - 1 - i]);
    if (i % 2 === 1) {
      n *= 2;
      if (n > 9) n -= 9;
    }
    sum += n;
  }
  return sum % 10 === 0;
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
    envelope,
    headers: response.headers
  };
}

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'chris-virtual-card-'));
  const port = await freePort();
  const turnPort = await freePort();
  const base = 'http://127.0.0.1:' + port;
  const logs = [];
  let child;
  try {
    const salt = crypto.randomBytes(16).toString('hex');
    const user = {
      id: 'u_virtual_card',
      username: 'virtual_card',
      nickname: '虚拟卡测试',
      realName: 'Virtual Card',
      realNameVerified: true,
      idCardHash: crypto.createHmac('sha256', SERVER_SECRET)
        .update('idcard:' + ID_CARD).digest('hex'),
      idCardMask: '110105********002X',
      avatar: '',
      bio: '',
      phone: '',
      gender: 'secret',
      balance: 100,
      transferLimit: 20000,
      salt,
      passwordHash: crypto.scryptSync(PASSWORD, salt, 64).toString('hex'),
      createdAt: new Date().toISOString(),
      tokenVersion: 0,
      phoneSession: 0
    };
    fs.writeFileSync(path.join(dataDir, 'secret.key'), SERVER_SECRET);
    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({ users: [user] }));
    fs.writeFileSync(path.join(dataDir, 'security.json'), JSON.stringify({ sliderLogin: 0 }));
    fs.writeFileSync(path.join(dataDir, 'ui.json'), JSON.stringify({ multiDevice: 1 }));

    child = spawn(process.execPath, ['server.js'], {
      cwd: SERVER_DIR,
      env: Object.assign({}, process.env, {
        DATA_DIR: dataDir,
        PORT: String(port),
        TURN_PORT: String(turnPort),
        CHRIS_LOCAL_ONLY: '1'
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
      } catch (_) {}
      await new Promise((resolve) => setTimeout(resolve, 100));
    }

    let response = await call(base, 'POST', '/api/login', {
      username: 'virtual_card',
      password: PASSWORD
    });
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const rawCookie = response.headers.getSetCookie
      ? response.headers.getSetCookie()[0]
      : response.headers.get('set-cookie') || '';
    const cookie = rawCookie.split(';')[0];

    response = await call(base, 'GET', '/api/wallet/virtual-card', undefined, cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(response.data.exists, false);
    assert.strictEqual(response.data.issuerConnected, false);

    response = await call(base, 'POST', '/api/wallet/virtual-card', {
      action: 'issue',
      verified: true
    }, cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(response.data.exists, true);
    assert.match(response.data.number, /^•••• •••• •••• \d{4}$/);
    assert.strictEqual(response.data.cvv, '');
    assert.strictEqual(response.data.scope, 'internal-test');

    response = await call(base, 'POST', '/api/wallet/virtual-card', {
      action: 'reveal',
      verified: true
    }, cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const pan = String(response.data.number || '').replace(/\s/g, '');
    assert.match(pan, /^9999\d{12}$/);
    assert.strictEqual(pan.length, 16);
    assert.strictEqual(luhn(pan), true, 'internal virtual PAN must pass Luhn');
    assert.strictEqual(pan.slice(-4), response.data.last4);
    assert.match(response.data.cvv, /^\d{3}$/);

    const disk = fs.readFileSync(path.join(dataDir, 'users.json'), 'utf8');
    assert.strictEqual(disk.includes(pan), false, 'full PAN must never be stored as plaintext');
    const stored = JSON.parse(disk).users[0];
    assert.match(stored.virtualCard.panEnc, /^enc1:/);

    response = await call(base, 'POST', '/api/wallet/virtual-card', {
      action: 'freeze',
      verified: true
    }, cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(response.data.status, 'frozen');
    assert.ok(response.data.frozenAt);

    response = await call(base, 'POST', '/api/wallet/virtual-card', {
      action: 'unfreeze',
      verified: true
    }, cookie);
    assert.strictEqual(response.data.status, 'active');

    response = await call(base, 'POST', '/api/wallet/virtual-card', {
      action: 'rotate',
      verified: true
    }, cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(response.data.generation, 2);

    response = await call(base, 'POST', '/api/wallet/virtual-card', {
      action: 'reveal',
      verified: true
    }, cookie);
    const newPan = String(response.data.number || '').replace(/\s/g, '');
    assert.notStrictEqual(newPan, pan);
    assert.strictEqual(luhn(newPan), true);

    response = await call(base, 'POST', '/api/wallet/virtual-card', {
      action: 'reveal',
      verified: false
    }, cookie);
    assert.strictEqual(response.status, 428);

    console.log('virtual-card: passed');
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
