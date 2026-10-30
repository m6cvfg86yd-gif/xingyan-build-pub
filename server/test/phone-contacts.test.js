'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const SERVER_DIR = path.resolve(__dirname, '..');
const PASSWORD = 'test123456';

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

function user(id, username, phone, privacy) {
  const salt = crypto.randomBytes(16).toString('hex');
  return {
    id, username, nickname: username, phone, avatar: '', bio: '', gender: 'secret',
    balance: 0, transferLimit: 20000, salt,
    passwordHash: crypto.scryptSync(PASSWORD, salt, 64).toString('hex'),
    createdAt: new Date().toISOString(), tokenVersion: 0, phoneSession: 0,
    privacy: privacy || {}
  };
}

async function call(base, cookie, method, url, body) {
  const headers = { 'x-device-kind': 'desktop' };
  if (cookie) headers.Cookie = cookie;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const response = await fetch(base + url, {
    method, headers, body: body === undefined ? undefined : JSON.stringify(body)
  });
  const text = await response.text();
  let envelope = {};
  try { envelope = text ? JSON.parse(text) : {}; } catch (_) { envelope = { raw: text }; }
  return {
    status: response.status,
    data: envelope && envelope.data !== undefined ? envelope.data : envelope,
    headers: response.headers
  };
}

async function login(base, username) {
  const response = await call(base, '', 'POST', '/api/login', { username, password: PASSWORD });
  assert.equal(response.status, 200, JSON.stringify(response.data));
  const raw = response.headers.getSetCookie
    ? response.headers.getSetCookie()[0]
    : response.headers.get('set-cookie') || '';
  return raw.split(';')[0];
}

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'chris-phone-contacts-'));
  const port = await freePort();
  const turnPort = await freePort();
  const base = 'http://127.0.0.1:' + port;
  const logs = [];
  let child;

  try {
    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({
      users: [
        user('u_phone_alice', 'phone_alice', '+8613800000001'),
        user('u_phone_bob', 'phone_bob', '+8613800000002'),
        user('u_phone_hidden', 'phone_hidden', '+8613800000003', { addByPhone: false })
      ]
    }, null, 2));
    fs.writeFileSync(path.join(dataDir, 'security.json'), JSON.stringify({ sliderLogin: 0 }));
    fs.writeFileSync(path.join(dataDir, 'ui.json'), JSON.stringify({ multiDevice: 1 }));

    child = spawn(process.execPath, ['server.js'], {
      cwd: SERVER_DIR,
      env: Object.assign({}, process.env, {
        DATA_DIR: dataDir,
        PORT: String(port),
        TURN_PORT: String(turnPort),
        ADMIN_PASSWORD: 'test-admin-password',
        CHRIS_LOCAL_ONLY: '1'
      }),
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true
    });
    child.stdout.on('data', (chunk) => logs.push(chunk.toString()));
    child.stderr.on('data', (chunk) => logs.push(chunk.toString()));
    for (let i = 0; i < 100; i++) {
      if (child.exitCode !== null) throw new Error('测试服务提前退出：\n' + logs.join(''));
      try {
        if ((await fetch(base + '/api/health')).ok) break;
      } catch (_) {
        // 等待服务启动。
      }
      await new Promise((resolve) => setTimeout(resolve, 100));
    }

    const cookie = await login(base, 'phone_alice');
    const salt = crypto.randomBytes(32);
    const hashes = ['13800000002', '13800000003'].map((phone) =>
      crypto.createHmac('sha256', salt).update(phone).digest('hex'));
    const response = await call(base, cookie, 'POST', '/api/contacts/phone-match', {
      salt: salt.toString('base64'), hashes
    });
    assert.equal(response.status, 200, JSON.stringify(response.data));
    const ids = (response.data.users || []).map((row) => row.id);
    assert.deepStrictEqual(ids, ['u_phone_bob'],
      '手机联系人匹配结果错误，或忽略了 addByPhone 隐私开关');
    assert.ok(!(response.data.users || []).some((row) => row.phone),
      '匹配响应不能返回对方手机号原文');

    const diskText = fs.readdirSync(dataDir)
      .filter((name) => fs.statSync(path.join(dataDir, name)).isFile())
      .map((name) => fs.readFileSync(path.join(dataDir, name), 'utf8'))
      .join('\n');
    assert.ok(!diskText.includes(salt.toString('base64')),
      '临时匹配盐被落盘');
    assert.ok(!diskText.includes(hashes[0]),
      '联系人匹配哈希被落盘');

    console.log('phone-contacts: passed');
  } finally {
    if (child && child.exitCode === null) child.kill();
    await new Promise((resolve) => setTimeout(resolve, 150));
    fs.rmSync(dataDir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
