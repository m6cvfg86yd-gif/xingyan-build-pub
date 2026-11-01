'use strict';

const assert = require('assert');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const SERVER_DIR = path.resolve(__dirname, '..');

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

async function call(base, method, url, body, cookie = '') {
  const headers = { 'x-device-kind': 'phone' };
  if (cookie) headers.Cookie = cookie;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const response = await fetch(base + url, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body)
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

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'chris-phone-register-'));
  const port = await freePort();
  const turnPort = await freePort();
  const base = 'http://127.0.0.1:' + port;
  const logs = [];
  let child;

  try {
    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({ users: [] }));
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

    const phone = '13800000001';
    let response = await call(base, 'POST', '/api/login/phone-code', { phone });
    assert.equal(response.status, 404, '普通登录不能给未绑定号码自动建号');

    response = await call(base, 'POST', '/api/login/phone-code', { phone, register: true });
    assert.equal(response.status, 200, JSON.stringify(response.data));
    const code = String(response.data.devCode || '');
    assert.match(code, /^\d{6}$/);

    response = await call(base, 'POST', '/api/login/phone',
      { phone, code, register: true });
    assert.equal(response.status, 200, JSON.stringify(response.data));
    assert.equal(response.data.created, true);
    assert.match(response.data.user.username, /^xy\d{9}/);
    const username = response.data.user.username;
    const rawCookie = response.headers.getSetCookie
      ? response.headers.getSetCookie()[0]
      : response.headers.get('set-cookie') || '';
    const cookie = rawCookie.split(';')[0];

    response = await call(base, 'GET', '/api/me', undefined, cookie);
    assert.equal(response.status, 200, JSON.stringify(response.data));
    assert.equal(response.data.user.username, username);

    const secondPhone = '13800000002';
    response = await call(base, 'POST', '/api/login/phone-code',
      { phone: secondPhone, register: true });
    assert.equal(response.status, 200, JSON.stringify(response.data));
    const secondCode = String(response.data.devCode || '');
    response = await call(base, 'POST', '/api/login/phone',
      { phone: secondPhone, code: secondCode, register: true });
    assert.equal(response.status, 200, JSON.stringify(response.data));
    const secondUsername = response.data.user.username;

    response = await call(base, 'GET', '/api/users?q=' + secondPhone, undefined, cookie);
    assert.equal(response.status, 200, JSON.stringify(response.data));
    assert.ok((response.data.users || []).some((row) => row.username === secondUsername),
      '注册即绑定后应能用手机号精确找到账号');

    response = await call(base, 'POST', '/api/login/phone-code', { phone });
    assert.equal(response.status, 200, '注册后手机号应立即成为可登录绑定号');
    assert.equal(response.data.nickname, '星言用户0001');

    console.log('phone-registration: passed');
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
