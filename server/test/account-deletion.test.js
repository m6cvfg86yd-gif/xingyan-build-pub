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
const TINY_PNG = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

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

function user(id, username, nickname) {
  const salt = crypto.randomBytes(16).toString('hex');
  return {
    id,
    username,
    nickname,
    avatar: '',
    bio: '',
    phone: '',
    gender: 'secret',
    balance: 0,
    transferLimit: 20000,
    salt,
    passwordHash: crypto.scryptSync(PASSWORD, salt, 64).toString('hex'),
    createdAt: new Date().toISOString(),
    tokenVersion: 0,
    phoneSession: 0
  };
}

async function waitForHealth(base, child, logs) {
  for (let i = 0; i < 100; i++) {
    if (child.exitCode !== null) throw new Error('测试服务器提前退出：\n' + logs.join(''));
    try {
      if ((await fetch(base + '/api/health')).ok) return;
    } catch (_) {
      // 服务器仍在启动。
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('测试服务器启动超时：\n' + logs.join(''));
}

async function call(base, cookie, method, url, body) {
  const headers = { 'x-device-kind': 'desktop' };
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

async function login(base, username) {
  const response = await call(base, '', 'POST', '/api/login', { username, password: PASSWORD });
  assert.equal(response.status, 200, JSON.stringify(response.data));
  const raw = response.headers.getSetCookie
    ? response.headers.getSetCookie()[0]
    : response.headers.get('set-cookie') || '';
  const cookie = raw.split(';')[0];
  assert.ok(cookie, '登录响应缺少会话 Cookie');
  return { cookie, user: response.data.user };
}

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'chris-account-delete-'));
  const port = await freePort();
  const turnPort = await freePort();
  const base = 'http://127.0.0.1:' + port;
  const logs = [];
  let child;

  try {
    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({
      users: [
        user('u_delete_alice', 'delete_alice', 'Alice'),
        user('u_delete_bob', 'delete_bob', 'Bob')
      ]
    }, null, 2));
    fs.writeFileSync(path.join(dataDir, 'security.json'),
      JSON.stringify({ sliderLogin: 0 }, null, 2));
    fs.writeFileSync(path.join(dataDir, 'ui.json'),
      JSON.stringify({ multiDevice: 1 }, null, 2));

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
    await waitForHealth(base, child, logs);

    const alice = await login(base, 'delete_alice');
    const bob = await login(base, 'delete_bob');

    let response = await call(base, alice.cookie, 'POST', '/api/friends/request', {
      username: 'delete_bob',
      message: '注销回归'
    });
    assert.equal(response.status, 200, JSON.stringify(response.data));
    response = await call(base, bob.cookie, 'GET', '/api/contacts');
    const request = (response.data.incoming || [])[0];
    assert.ok(request && request.requestId);
    response = await call(base, bob.cookie, 'POST', '/api/friends/respond', {
      requestId: request.requestId,
      accept: true
    });
    assert.equal(response.status, 200, JSON.stringify(response.data));
    const chatId = response.data.chat.id;

    response = await call(base, alice.cookie, 'POST', '/api/upload', {
      name: 'delete-me.png',
      dataUrl: TINY_PNG
    });
    assert.equal(response.status, 200, JSON.stringify(response.data));
    const uploadName = path.basename(String(response.data.url).split('?')[0]);
    assert.ok(fs.existsSync(path.join(dataDir, 'uploads', uploadName)));

    response = await call(base, alice.cookie, 'POST',
      '/api/chats/' + chatId + '/messages',
      { kind: 'image', content: response.data.url });
    assert.equal(response.status, 200, JSON.stringify(response.data));

    response = await call(base, alice.cookie, 'POST', '/api/favorites', {
      kind: 'text',
      content: '注销时必须删除的收藏'
    });
    assert.equal(response.status, 200, JSON.stringify(response.data));

    response = await call(base, alice.cookie, 'POST', '/api/me/delete', { confirm: '注销' });
    assert.equal(response.status, 200, JSON.stringify(response.data));
    assert.equal(response.data.deleted, true);

    response = await call(base, alice.cookie, 'GET', '/api/session');
    assert.equal(response.status, 200);
    assert.equal(response.data.authenticated, false);

    response = await call(base, bob.cookie, 'GET', '/api/contacts');
    assert.equal(response.status, 200);
    assert.ok(!(response.data.friends || []).some((friend) => friend.id === alice.user.id));

    response = await call(base, bob.cookie, 'GET', '/api/chats');
    assert.equal(response.status, 200);
    assert.ok(!(response.data.chats || []).some((chat) => chat.id === chatId));

    const users = JSON.parse(fs.readFileSync(path.join(dataDir, 'users.json'), 'utf8')).users;
    assert.ok(!users.some((row) => row.id === alice.user.id));
    assert.ok(users.some((row) => row.id === bob.user.id));
    assert.ok(!fs.existsSync(path.join(dataDir, 'uploads', uploadName)));
    assert.ok(!fs.existsSync(path.join(dataDir, 'messages', chatId + '.jsonl')));

    console.log('account-deletion: passed');
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
