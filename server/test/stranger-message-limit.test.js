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

function user(id, username, nickname) {
  const salt = crypto.randomBytes(16).toString('hex');
  return {
    id, username, nickname, avatar: '', bio: '', phone: '', gender: 'secret',
    balance: 0, transferLimit: 20000, salt,
    passwordHash: crypto.scryptSync(PASSWORD, salt, 64).toString('hex'),
    createdAt: new Date().toISOString(), tokenVersion: 0, phoneSession: 0
  };
}

async function waitForHealth(base, child, logs) {
  for (let i = 0; i < 120; i++) {
    if (child.exitCode !== null) throw new Error('测试服务器提前退出：\n' + logs.join(''));
    try {
      if ((await fetch(base + '/api/health')).ok) return;
    } catch (_) {}
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('测试服务器启动超时：\n' + logs.join(''));
}

async function call(base, cookie, method, url, body) {
  const headers = { 'x-device-kind': 'desktop' };
  if (cookie) headers.Cookie = cookie;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const response = await fetch(base + url, {
    method, headers, body: body === undefined ? undefined : JSON.stringify(body)
  });
  const text = await response.text();
  let json = {};
  try { json = text ? JSON.parse(text) : {}; } catch (_) { json = { raw: text }; }
  return {
    status: response.status,
    data: json && json.data !== undefined ? json.data : json,
    headers: response.headers
  };
}

async function login(base, username) {
  const response = await call(base, '', 'POST', '/api/login', { username, password: PASSWORD });
  assert.equal(response.status, 200, JSON.stringify(response.data));
  const cookie = (response.headers.getSetCookie
    ? response.headers.getSetCookie()[0]
    : response.headers.get('set-cookie') || '').split(';')[0];
  return { cookie, user: response.data.user };
}

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'chris-stranger-limit-'));
  const port = await freePort();
  const base = 'http://127.0.0.1:' + port;
  const logs = [];
  let child;
  try {
    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({
      users: [
        user('u_stranger_alice', 'stranger_alice', 'Alice'),
        user('u_stranger_bob', 'stranger_bob', 'Bob')
      ]
    }, null, 2));
    fs.writeFileSync(path.join(dataDir, 'security.json'), JSON.stringify({ sliderLogin: 0 }, null, 2));
    fs.writeFileSync(path.join(dataDir, 'ui.json'), JSON.stringify({ multiDevice: 1 }, null, 2));

    child = spawn(process.execPath, ['server.js'], {
      cwd: SERVER_DIR,
      env: Object.assign({}, process.env, {
        DATA_DIR: dataDir,
        PORT: String(port),
        TURN_PORT: String(await freePort()),
        CHRIS_LOCAL_ONLY: '1'
      }),
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true
    });
    child.stdout.on('data', (chunk) => logs.push(chunk.toString()));
    child.stderr.on('data', (chunk) => logs.push(chunk.toString()));
    await waitForHealth(base, child, logs);

    const alice = await login(base, 'stranger_alice');
    const bob = await login(base, 'stranger_bob');

    let response = await call(base, alice.cookie, 'POST', '/api/chats/direct', {
      userId: bob.user.id
    });
    assert.equal(response.status, 200, JSON.stringify(response.data));
    const chatId = response.data.chat.id;

    for (let i = 1; i <= 5; i++) {
      response = await call(base, alice.cookie, 'POST',
        '/api/chats/' + chatId + '/messages',
        { kind: 'text', content: '陌生消息 ' + i, clientId: 'limit-' + i });
      assert.equal(response.status, 200, '第 ' + i + ' 条应允许：' + JSON.stringify(response.data));
    }
    response = await call(base, alice.cookie, 'POST',
      '/api/chats/' + chatId + '/messages',
      { kind: 'text', content: '第 6 条', clientId: 'limit-6' });
    assert.equal(response.status, 403, JSON.stringify(response.data));
    assert.match(response.data.error || '', /最多发送 5 条/);

    response = await call(base, alice.cookie, 'DELETE',
      '/api/chats/' + chatId + '?clear=1');
    assert.equal(response.status, 200, JSON.stringify(response.data));
    response = await call(base, alice.cookie, 'POST',
      '/api/chats/' + chatId + '/messages',
      { kind: 'text', content: '清空后仍不能发', clientId: 'limit-after-clear' });
    assert.equal(response.status, 403, '清空聊天不应重置陌生人额度');

    response = await call(base, alice.cookie, 'POST', '/api/friends/request', {
      username: 'stranger_bob', message: '通过后继续聊'
    });
    assert.equal(response.status, 200, JSON.stringify(response.data));
    response = await call(base, bob.cookie, 'POST', '/api/friends/respond', {
      userId: alice.user.id, accept: true
    });
    assert.equal(response.status, 200, JSON.stringify(response.data));

    response = await call(base, alice.cookie, 'POST',
      '/api/chats/' + chatId + '/messages',
      { kind: 'text', content: '成为好友后恢复', clientId: 'friend-ok' });
    assert.equal(response.status, 200, JSON.stringify(response.data));

    response = await call(base, alice.cookie, 'POST',
      '/api/chats/' + chatId + '/burn', { on: true });
    assert.equal(response.status, 200, JSON.stringify(response.data));
    assert.equal(response.data.burn, false, '服务端仍允许开启阅后即焚');
    assert.equal(response.data.disabled, true);
    response = await call(base, alice.cookie, 'POST',
      '/api/chats/' + chatId + '/messages',
      { kind: 'text', content: '不应带阅后即焚标记', clientId: 'burn-off' });
    assert.equal(response.status, 200, JSON.stringify(response.data));
    assert.notEqual(response.data.message.burn, true);

    console.log('stranger-message-limit: passed');
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
