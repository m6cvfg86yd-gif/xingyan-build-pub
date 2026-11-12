'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const SERVER_DIR = path.resolve(__dirname, '..');
const LOGIN_PASSWORD = 'FailClosed1027!';
const PAY_PASSWORD = '123456';
const ADMIN_PASSWORD = 'aml-failclosed-admin';
const SERVER_SECRET = 'aml-failclosed-secret';

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

function scrypt(value, salt) {
  return crypto.scryptSync(value, salt, 64).toString('hex');
}

function makeUser(id, username, nickname, balance, realName) {
  const salt = crypto.randomBytes(16).toString('hex');
  const paySalt = crypto.randomBytes(16).toString('hex');
  return {
    id,
    username,
    nickname,
    avatar: '',
    bio: '',
    phone: '',
    gender: 'secret',
    realName,
    realNameVerified: true,
    idCardHash: crypto.createHmac('sha256', SERVER_SECRET)
      .update('idcard:' + id).digest('hex'),
    balance,
    transferLimit: 20000,
    salt,
    passwordHash: scrypt(LOGIN_PASSWORD, salt),
    paySalt,
    payPasswordHash: scrypt(PAY_PASSWORD, paySalt),
    createdAt: new Date(Date.now() - 30 * 86400000).toISOString(),
    tokenVersion: 0,
    phoneSession: 0
  };
}

async function call(base, method, endpoint, body, cookie) {
  const headers = { 'x-device-kind': 'desktop' };
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
  return { status: response.status, data: envelope, headers: response.headers };
}

function cookieOf(response) {
  const raw = response.headers.getSetCookie
    ? response.headers.getSetCookie()[0]
    : response.headers.get('set-cookie') || '';
  return raw.split(';')[0];
}

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'chris-aml-failclosed-'));
  const port = await freePort();
  const turnPort = await freePort();
  const base = 'http://127.0.0.1:' + port;
  const logs = [];
  let child;
  try {
    const users = [
      makeUser('u_fc_payer', 'fc_payer', '付款人', 1000, '付款人'),
      makeUser('u_fc_recipient', 'fc_recipient', '收款人', 0, '收款人')
    ];
    fs.writeFileSync(path.join(dataDir, 'secret.key'), SERVER_SECRET);
    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({ users }));
    fs.writeFileSync(path.join(dataDir, 'chats.json'), JSON.stringify({
      chats: [{
        id: 'c_fc',
        type: 'direct',
        memberIds: ['u_fc_payer', 'u_fc_recipient'],
        ownerId: 'u_fc_payer',
        seq: 0,
        createdAt: users[0].createdAt
      }]
    }));
    fs.writeFileSync(path.join(dataDir, 'security.json'), JSON.stringify({ sliderLogin: 0 }));
    fs.writeFileSync(path.join(dataDir, 'ui.json'), JSON.stringify({ multiDevice: 1 }));
    fs.writeFileSync(path.join(dataDir, 'aml.json'), JSON.stringify({
      enc: 1,
      iv: 'invalid',
      tag: 'invalid',
      ct: 'invalid'
    }));

    child = spawn(process.execPath, ['server.js'], {
      cwd: SERVER_DIR,
      env: Object.assign({}, process.env, {
        DATA_DIR: dataDir,
        PORT: String(port),
        TURN_PORT: String(turnPort),
        ADMIN_PASSWORD,
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
      } catch (_) {
        // 启动中。
      }
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    assert.ok(logs.join('').indexOf('运行失败') >= 0
      || logs.join('').indexOf('初始化失败') >= 0,
    'server should report AML initialization failure');

    let response = await call(base, 'POST', '/api/login', {
      username: 'fc_payer',
      password: LOGIN_PASSWORD
    });
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const payerCookie = cookieOf(response);

    response = await call(base, 'POST', '/api/pay/transfer', {
      chatId: 'c_fc',
      amount: 100,
      password: PAY_PASSWORD,
      requestId: 'failclosed_transfer_001'
    }, payerCookie);
    assert.strictEqual(response.status, 503, JSON.stringify(response.data));
    assert.strictEqual(response.data.details.amlPaused, true);

    response = await call(base, 'GET', '/api/me', undefined, payerCookie);
    assert.strictEqual(response.status, 200);
    assert.strictEqual(Number(response.data.data.user.balance), 1000,
      'AML outage must not debit the wallet');

    response = await call(base, 'POST', '/api/ops/login', {
      username: 'admin',
      password: ADMIN_PASSWORD
    });
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const adminCookie = cookieOf(response);
    response = await call(base, 'GET', '/api/ops/aml', undefined, adminCookie);
    assert.strictEqual(response.status, 503, JSON.stringify(response.data));

    console.log('aml-failclosed: passed');
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
