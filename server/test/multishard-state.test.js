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
const PAY_PASSWORD = '123456';

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

function makeUser(id, username, nickname, balance) {
  const salt = crypto.randomBytes(16).toString('hex');
  const paySalt = crypto.randomBytes(16).toString('hex');
  return {
    id,
    username,
    nickname,
    avatar: 'https://example.invalid/' + username + '.png',
    bio: '',
    phone: '',
    gender: 'secret',
    balance,
    salt,
    passwordHash: crypto.scryptSync(PASSWORD, salt, 64).toString('hex'),
    paySalt,
    payPasswordHash: crypto.scryptSync(PAY_PASSWORD, paySalt, 64).toString('hex'),
    realName: nickname,
    realNameVerified: true,
    idCardHash: crypto.createHash('sha256').update('multishard:' + id).digest('hex'),
    idCardMask: '110105********' + id.slice(-4).padStart(4, '0'),
    idCardVerifiedAt: new Date(Date.now() - 86400000).toISOString(),
    createdAt: new Date(Date.now() - 86400000).toISOString(),
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
  return {
    status: response.status,
    data: envelope && envelope.data !== undefined ? envelope.data : envelope,
    headers: response.headers
  };
}

function cookieOf(response) {
  const raw = response.headers.getSetCookie
    ? response.headers.getSetCookie()[0]
    : response.headers.get('set-cookie') || '';
  return raw.split(';')[0];
}

async function login(base, username) {
  const response = await call(base, 'POST', '/api/login', { username, password: PASSWORD });
  assert.strictEqual(response.status, 200, JSON.stringify(response.data));
  const cookie = cookieOf(response);
  assert.ok(cookie);
  return { cookie, user: response.data.user };
}

async function waitForHealth(base, child, logs) {
  for (let i = 0; i < 160; i += 1) {
    if (child.exitCode !== null) throw new Error('测试服务提前退出：\n' + logs.join(''));
    try {
      if ((await fetch(base + '/api/health')).ok) return;
    } catch (_) { /* starting */ }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('测试服务启动超时：\n' + logs.join(''));
}

async function startServer(dataDir, port, turnPort) {
  const logs = [];
  const child = spawn(process.execPath, ['server.js'], {
    cwd: SERVER_DIR,
    env: Object.assign({}, process.env, {
      DATA_DIR: dataDir,
      PORT: String(port),
      TURN_PORT: String(turnPort),
      CHRIS_LOCAL_ONLY: '1',
      AML_RUNTIME_ENABLED: '0',
      ADMIN_PASSWORD: 'multishard-test-admin'
    }),
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true
  });
  child.stdout.on('data', (chunk) => logs.push(chunk.toString()));
  child.stderr.on('data', (chunk) => logs.push(chunk.toString()));
  const base = 'http://127.0.0.1:' + port;
  await waitForHealth(base, child, logs);
  return { child, logs, base };
}

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'chris-multishard-state-'));
  const portA = await freePort();
  const portB = await freePort();
  const turnA = await freePort();
  const turnB = await freePort();
  let a;
  let b;

  try {
    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({
      users: [
        makeUser('u_shard_alice', 'shard_alice', 'Alice', 1000),
        makeUser('u_shard_bob', 'shard_bob', 'Bob', 0)
      ]
    }));
    fs.writeFileSync(path.join(dataDir, 'security.json'), JSON.stringify({ sliderLogin: 0 }));
    fs.writeFileSync(path.join(dataDir, 'ui.json'), JSON.stringify({ multiDevice: 1 }));

    a = await startServer(dataDir, portA, turnA);
    b = await startServer(dataDir, portB, turnB);

    const alice = await login(a.base, 'shard_alice');
    const bob = await login(b.base, 'shard_bob');

    let response = await call(a.base, 'POST', '/api/friends/request', {
      username: 'shard_bob'
    }, alice.cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    response = await call(b.base, 'GET', '/api/contacts', undefined, bob.cookie);
    const request = (response.data.incoming || [])[0];
    assert.ok(request && request.requestId);
    response = await call(b.base, 'POST', '/api/friends/respond', {
      requestId: request.requestId,
      accept: true
    }, bob.cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));

    response = await call(a.base, 'GET', '/api/contacts', undefined, alice.cookie);
    assert.ok((response.data.friends || []).some((u) => u.id === bob.user.id));

    response = await call(a.base, 'POST', '/api/friends/remove', {
      userId: bob.user.id
    }, alice.cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    response = await call(b.base, 'GET', '/api/contacts', undefined, bob.cookie);
    assert.ok(!(response.data.friends || []).some((u) => u.id === alice.user.id),
      'deleted friend must disappear on another shard');

    response = await call(a.base, 'POST', '/api/friends/request', {
      username: 'shard_bob'
    }, alice.cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    response = await call(b.base, 'GET', '/api/contacts', undefined, bob.cookie);
    const readdRequest = (response.data.incoming || [])[0];
    assert.ok(readdRequest && readdRequest.requestId);
    response = await call(b.base, 'POST', '/api/friends/respond', {
      requestId: readdRequest.requestId,
      accept: true
    }, bob.cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));

    response = await call(a.base, 'POST', '/api/chats/direct', { userId: bob.user.id }, alice.cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const directId = response.data.chat.id;

    response = await call(a.base, 'DELETE', '/api/chats/' + directId, undefined, alice.cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    response = await call(b.base, 'GET', '/api/chats', undefined, alice.cookie);
    assert.ok(!(response.data.chats || []).some((chat) => chat.id === directId),
      'hidden chat must stay hidden on another shard');

    response = await call(a.base, 'POST', '/api/chats/group', {
      name: '跨分片解散群',
      memberIds: [bob.user.id]
    }, alice.cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const groupId = response.data.chat.id;
    response = await call(a.base, 'POST', '/api/chats/' + groupId + '/kick', {
      userId: bob.user.id
    }, alice.cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    response = await call(b.base, 'GET', '/api/chats', undefined, bob.cookie);
    assert.ok(!(response.data.chats || []).some((chat) => chat.id === groupId),
      'kicked member must lose the group on another shard');

    response = await call(a.base, 'POST', '/api/chats/group', {
      name: '跨分片解散群二',
      memberIds: [bob.user.id]
    }, alice.cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const dismissId = response.data.chat.id;
    response = await call(a.base, 'POST', '/api/chats/' + dismissId + '/dismiss', {}, alice.cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    response = await call(b.base, 'GET', '/api/chats', undefined, bob.cookie);
    assert.ok(!(response.data.chats || []).some((chat) => chat.id === dismissId),
      'dismissed group must disappear on another shard');

    response = await call(a.base, 'POST', '/api/moments', {
      content: '跨分片生活圈测试',
      images: []
    }, alice.cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const momentId = response.data.moment.id;
    response = await call(b.base, 'GET', '/api/moments?limit=20', undefined, bob.cookie);
    assert.ok((response.data.moments || []).some((m) => m.id === momentId),
      'new moment must be visible on another shard');
    response = await call(b.base, 'POST', '/api/moments/' + momentId + '/comments', {
      content: '跨分片评论'
    }, bob.cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    response = await call(a.base, 'GET', '/api/moments?limit=20', undefined, alice.cookie);
    const moment = (response.data.moments || []).find((m) => m.id === momentId);
    assert.ok((moment.comments || []).some((c) => c.content === '跨分片评论'),
      'comment must be visible on another shard: ' + JSON.stringify(moment));

    response = await call(b.base, 'POST', '/api/moments/' + momentId + '/like', {}, bob.cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    response = await call(a.base, 'GET', '/api/moments?limit=20', undefined, alice.cookie);
    const liked = (response.data.moments || []).find((m) => m.id === momentId);
    const like = (liked.likes || []).find((row) => row.userId === bob.user.id);
    assert.ok(like && like.avatar, 'like response must include the liker avatar');

    response = await call(a.base, 'POST', '/api/pay/transfer', {
      chatId: directId,
      amount: 10,
      password: PAY_PASSWORD,
      requestId: 'multishard_claim_1',
      note: '跨分片收款'
    }, alice.cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const transferId = response.data.transfer.id;
    response = await call(b.base, 'POST', '/api/transfers/' + transferId + '/claim', {}, bob.cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const firstBalance = Number(response.data.balance);
    response = await call(b.base, 'POST', '/api/transfers/' + transferId + '/claim', {}, bob.cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(response.data.alreadyReceived, true);
    assert.strictEqual(Number(response.data.balance), firstBalance);

    console.log('multishard-state: passed');
  } finally {
    if (a && a.child.exitCode === null) a.child.kill();
    if (b && b.child.exitCode === null) b.child.kill();
    await new Promise((resolve) => setTimeout(resolve, 200));
    fs.rmSync(dataDir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
