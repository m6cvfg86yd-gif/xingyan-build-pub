'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const SERVER_DIR = path.resolve(__dirname, '..');
const PASSWORD = 'ProfileRefresh1027!';

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
  const envelope = text ? JSON.parse(text) : {};
  return {
    status: response.status,
    data: envelope.data === undefined ? envelope : envelope.data,
    headers: response.headers
  };
}

async function startServer(dataDir, label, logs) {
  const port = await freePort();
  const turnPort = await freePort();
  const httpsPort = await freePort();
  const child = spawn(process.execPath, ['server.js'], {
    cwd: SERVER_DIR,
    env: Object.assign({}, process.env, {
      DATA_DIR: dataDir,
      PORT: String(port),
      TURN_PORT: String(turnPort),
      HTTPS_PORT: String(httpsPort),
      ADMIN_PASSWORD: 'test-admin-password',
      CHRIS_LOCAL_ONLY: '1',
      SHARD_COUNT: '1'
    }),
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true
  });
  child.stdout.on('data', (chunk) => logs.push(label + ': ' + chunk.toString()));
  child.stderr.on('data', (chunk) => logs.push(label + ': ' + chunk.toString()));
  const base = 'http://127.0.0.1:' + port;
  for (let i = 0; i < 200; i += 1) {
    if (child.exitCode !== null) throw new Error(label + ' 提前退出：\n' + logs.join(''));
    try {
      if ((await fetch(base + '/api/health')).ok) return { child, base };
    } catch (_) {
      // Wait for startup.
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error(label + ' 启动超时：\n' + logs.join(''));
}

async function login(base) {
  const response = await call(base, 'POST', '/api/login', {
    username: 'profile_refresh',
    password: PASSWORD
  });
  assert.equal(response.status, 200, JSON.stringify(response.data));
  const raw = response.headers.getSetCookie
    ? response.headers.getSetCookie()[0]
    : response.headers.get('set-cookie') || '';
  return raw.split(';')[0];
}

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'chris-profile-refresh-'));
  const children = [];
  const logs = [];
  const salt = crypto.randomBytes(16).toString('hex');

  try {
    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({
      users: [{
        id: 'u_profile_refresh',
        username: 'profile_refresh',
        nickname: '旧资料',
        phone: '',
        realName: '',
        gender: 'secret',
        balance: 0,
        transferLimit: 20000,
        salt,
        passwordHash: crypto.scryptSync(PASSWORD, salt, 64).toString('hex'),
        favorites: [],
        createdAt: new Date().toISOString(),
        tokenVersion: 0,
        phoneSession: 0
      }]
    }));
    fs.writeFileSync(path.join(dataDir, 'security.json'), JSON.stringify({ sliderLogin: 0 }));
    fs.writeFileSync(path.join(dataDir, 'ui.json'), JSON.stringify({ multiDevice: 1 }));

    const first = await startServer(dataDir, 'first', logs);
    const second = await startServer(dataDir, 'second', logs);
    children.push(first.child, second.child);
    const firstCookie = await login(first.base);
    const secondCookie = await login(second.base);

    const expected = {
      nickname: '跨进程新资料',
      bio: '资料已同步',
      momentCover: '/uploads/synced-cover.jpg',
      chatBackground: '/bg/bw2.jpg'
    };
    const changed = await call(first.base, 'PATCH', '/api/me', expected, firstCookie);
    assert.equal(changed.status, 200, JSON.stringify(changed.data));

    const fresh = await call(second.base, 'GET', '/api/me', undefined, secondCookie);
    assert.equal(fresh.status, 200, JSON.stringify(fresh.data));
    for (const [key, value] of Object.entries(expected)) {
      if (String(value).startsWith('/uploads/')) {
        assert.ok(String(fresh.data.user[key] || '').startsWith(value),
          key + ' 没有跨进程刷新');
      } else {
        assert.equal(fresh.data.user[key], value, key + ' 没有跨进程刷新');
      }
    }
    console.log('profile-cross-process-refresh: passed');
  } finally {
    children.forEach((child) => {
      if (child && child.exitCode === null) child.kill();
    });
    await new Promise((resolve) => setTimeout(resolve, 150));
    fs.rmSync(dataDir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
