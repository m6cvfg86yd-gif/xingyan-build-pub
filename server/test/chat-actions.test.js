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
    if (child.exitCode !== null) {
      throw new Error('测试服务器提前退出：\n' + logs.join(''));
    }
    try {
      const response = await fetch(base + '/api/health');
      if (response.ok) return;
    } catch (_) {
      // 服务器还在启动。
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
  const data = envelope && envelope.data !== undefined ? envelope.data : envelope;
  return { status: response.status, data, headers: response.headers };
}

async function login(base, username) {
  const response = await call(base, '', 'POST', '/api/login', {
    username,
    password: PASSWORD
  });
  assert.equal(response.status, 200, JSON.stringify(response.data));
  const cookie = (response.headers.getSetCookie
    ? response.headers.getSetCookie()[0]
    : response.headers.get('set-cookie') || '').split(';')[0];
  assert.ok(cookie, '登录响应缺少会话 Cookie');
  return { cookie, user: response.data.user };
}

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'chris-chat-actions-'));
  const port = await freePort();
  const turnPort = await freePort();
  const base = 'http://127.0.0.1:' + port;
  const logs = [];
  let child;

  try {
    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({
      users: [
        user('u_alice_smoke', 'alice_smoke', 'Alice'),
        user('u_bob_smoke', 'bob_smoke', 'Bob')
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

    const alice = await login(base, 'alice_smoke');
    const bob = await login(base, 'bob_smoke');

    let response = await call(base, alice.cookie, 'PATCH', '/api/me', {
      username: 'alice_renamed'
    });
    assert.equal(response.status, 200, JSON.stringify(response.data));
    assert.equal(response.data.user.username, 'alice_renamed');
    response = await call(base, '', 'POST', '/api/login', {
      username: 'alice_smoke',
      password: PASSWORD
    });
    assert.equal(response.status, 401, '旧星言号仍然可以登录');
    const aliceRenamed = await login(base, 'alice_renamed');
    assert.equal(aliceRenamed.user.username, 'alice_renamed');

    response = await call(base, alice.cookie, 'POST', '/api/friends/request', {
      username: 'bob_smoke',
      message: '接口烟测'
    });
    assert.equal(response.status, 200, JSON.stringify(response.data));

    response = await call(base, bob.cookie, 'GET', '/api/contacts');
    assert.equal(response.status, 200, JSON.stringify(response.data));
    const request = (response.data.incoming || [])[0];
    assert.ok(request && request.requestId,
      'Bob 没收到好友申请：' + JSON.stringify(response.data));

    response = await call(base, bob.cookie, 'POST', '/api/friends/respond', {
      requestId: request.requestId,
      accept: true
    });
    assert.equal(response.status, 200, JSON.stringify(response.data));
    assert.ok(response.data.chat && response.data.chat.id, '同意好友后未返回会话');
    assert.equal(response.data.chat.title, 'Alice');
    const directId = response.data.chat.id;

    response = await call(base, bob.cookie, 'POST',
      '/api/chats/' + directId + '/messages',
      { kind: 'text', content: '拉黑前消息' });
    assert.equal(response.status, 200, JSON.stringify(response.data));

    response = await call(base, alice.cookie, 'POST', '/api/friends/meta', {
      userId: bob.user.id,
      block: true
    });
    assert.equal(response.status, 200, JSON.stringify(response.data));
    assert.equal(response.data.meta.block, true);

    response = await call(base, bob.cookie, 'POST',
      '/api/chats/' + directId + '/messages',
      { kind: 'text', content: '拉黑后消息' });
    assert.equal(response.status, 422, JSON.stringify(response.data));
    assert.match(response.data.error || '', /拒收/);

    response = await call(base, alice.cookie, 'POST', '/api/friends/meta', {
      userId: bob.user.id,
      block: false
    });
    assert.equal(response.status, 200, JSON.stringify(response.data));

    response = await call(base, bob.cookie, 'DELETE',
      '/api/chats/' + directId + '?clear=1');
    assert.equal(response.status, 200, JSON.stringify(response.data));
    assert.equal(response.data.hidden, true);
    response = await call(base, bob.cookie, 'GET', '/api/chats');
    assert.equal(response.status, 200, JSON.stringify(response.data));
    assert.ok(!(response.data.chats || []).some((chat) => chat.id === directId),
      '删除后会话仍立即出现在列表里');
    for (let i = 0; i < 6; i++) {
      await new Promise((resolve) => setTimeout(resolve, 250));
      response = await call(base, bob.cookie, 'GET', '/api/chats');
      assert.ok(!(response.data.chats || []).some((chat) => chat.id === directId),
        '删除后会话在刷新周期内回流');
    }

    response = await call(base, alice.cookie, 'POST', '/api/chats/group', {
      name: '接口烟测群',
      memberIds: [bob.user.id]
    });
    assert.equal(response.status, 200, JSON.stringify(response.data));
    const groupId = response.data.chat.id;

    response = await call(base, alice.cookie, 'POST',
      '/api/chats/' + groupId + '/dismiss', {});
    assert.equal(response.status, 200, JSON.stringify(response.data));
    assert.equal(response.data.dismissed, true);

    for (const account of [alice, bob]) {
      for (let i = 0; i < 6; i++) {
        response = await call(base, account.cookie, 'GET', '/api/chats');
        assert.equal(response.status, 200, JSON.stringify(response.data));
        assert.ok(!(response.data.chats || []).some((chat) => chat.id === groupId),
          '解散后群会话在刷新周期内回流');
        await new Promise((resolve) => setTimeout(resolve, 250));
      }
    }

    response = await call(base, alice.cookie, 'POST', '/api/friends/remove', {
      userId: bob.user.id
    });
    assert.equal(response.status, 200, JSON.stringify(response.data));
    response = await call(base, alice.cookie, 'GET', '/api/contacts');
    assert.equal(response.status, 200, JSON.stringify(response.data));
    assert.ok(!(response.data.friends || []).some((friend) => friend.id === bob.user.id),
      '删除好友后联系人仍立即存在');

    response = await call(base, alice.cookie, 'POST', '/api/friends/request', {
      username: 'bob_smoke',
      message: '一键清除回归'
    });
    assert.equal(response.status, 200, JSON.stringify(response.data));
    response = await call(base, bob.cookie, 'GET', '/api/contacts');
    const clearRequest = (response.data.incoming || []).find((item) => item.requestId);
    assert.ok(clearRequest && clearRequest.requestId, '一键清除前置好友申请缺失');
    response = await call(base, bob.cookie, 'POST', '/api/friends/respond', {
      requestId: clearRequest.requestId,
      accept: true
    });
    assert.equal(response.status, 200, JSON.stringify(response.data));

    response = await call(base, alice.cookie, 'POST', '/api/friends/clear', {});
    assert.equal(response.status, 200, JSON.stringify(response.data));
    assert.ok(response.data.removed >= 1, '一键清除没有删除好友关系');
    for (const account of [alice, bob]) {
      response = await call(base, account.cookie, 'GET', '/api/contacts');
      assert.equal(response.status, 200, JSON.stringify(response.data));
      const absentId = account === alice ? bob.user.id : alice.user.id;
      assert.ok(!(response.data.friends || []).some((friend) => friend.id === absentId),
        '一键清除后双方通讯录仍保留好友');
    }

    console.log('chat-actions: passed');
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
