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
    id, username, nickname, avatar: '', bio: '', phone: '', gender: 'secret',
    balance: 0, transferLimit: 20000, salt,
    passwordHash: crypto.scryptSync(PASSWORD, salt, 64).toString('hex'),
    createdAt: new Date().toISOString(), tokenVersion: 0, phoneSession: 0
  };
}

async function startServer(dataDir, port, turnPort, logs) {
  const child = spawn(process.execPath, ['server.js'], {
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
  const base = 'http://127.0.0.1:' + port;
  for (let i = 0; i < 100; i++) {
    if (child.exitCode !== null) throw new Error('分片提前退出：\n' + logs.join(''));
    try {
      if ((await fetch(base + '/api/health')).ok) return { child, base };
    } catch (_) {
      // 等待分片启动。
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('分片启动超时：\n' + logs.join(''));
}

async function stopServer(child) {
  if (child && child.exitCode === null) child.kill();
  await new Promise((resolve) => setTimeout(resolve, 250));
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
  assert.ok(cookie);
  return { cookie, user: response.data.user };
}

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'chris-delete-shards-'));
  const logs = [];
  let setup;
  let shardA;
  let shardB;

  try {
    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({
      users: [
        user('u_shard_alice', 'shard_alice', 'Alice'),
        user('u_shard_bob', 'shard_bob', 'Bob')
      ]
    }, null, 2));
    fs.writeFileSync(path.join(dataDir, 'security.json'), JSON.stringify({ sliderLogin: 0 }));
    fs.writeFileSync(path.join(dataDir, 'ui.json'), JSON.stringify({ multiDevice: 1 }));

    const setupPort = await freePort();
    setup = await startServer(dataDir, setupPort, await freePort(), logs);
    const seedAlice = await login(setup.base, 'shard_alice');
    const seedBob = await login(setup.base, 'shard_bob');

    let response = await call(setup.base, seedAlice.cookie, 'POST', '/api/friends/request', {
      username: 'shard_bob', message: '分片注销回归'
    });
    assert.equal(response.status, 200, JSON.stringify(response.data));
    response = await call(setup.base, seedBob.cookie, 'GET', '/api/contacts');
    const request = (response.data.incoming || [])[0];
    assert.ok(request && request.requestId);
    response = await call(setup.base, seedBob.cookie, 'POST', '/api/friends/respond', {
      requestId: request.requestId, accept: true
    });
    assert.equal(response.status, 200, JSON.stringify(response.data));
    const chatId = response.data.chat.id;

    response = await call(setup.base, seedAlice.cookie, 'POST', '/api/upload', {
      name: 'shard-delete.png', dataUrl: TINY_PNG
    });
    assert.equal(response.status, 200, JSON.stringify(response.data));
    const uploadName = path.basename(String(response.data.url).split('?')[0]);
    response = await call(setup.base, seedAlice.cookie, 'POST',
      '/api/chats/' + chatId + '/messages', { kind: 'image', content: response.data.url });
    assert.equal(response.status, 200, JSON.stringify(response.data));
    await stopServer(setup.child);
    setup = null;

    shardA = await startServer(dataDir, await freePort(), await freePort(), logs);
    shardB = await startServer(dataDir, await freePort(), await freePort(), logs);
    const alice = await login(shardA.base, 'shard_alice');
    const bob = await login(shardB.base, 'shard_bob');

    response = await call(shardB.base, bob.cookie, 'GET',
      '/api/chats/' + chatId + '/messages?limit=50');
    assert.equal(response.status, 200, JSON.stringify(response.data));
    response = await call(shardA.base, alice.cookie, 'POST',
      '/api/chats/' + chatId + '/messages',
      { kind: 'text', content: '跨分片新消息', clientId: 'shard-new-message' });
    assert.equal(response.status, 200, JSON.stringify(response.data));
    const sentId = response.data.message.id;
    await new Promise((resolve) => setTimeout(resolve, 400));
    response = await call(shardB.base, bob.cookie, 'GET',
      '/api/chats/' + chatId + '/messages?limit=50');
    assert.equal(response.status, 200, JSON.stringify(response.data));
    assert.ok((response.data.messages || []).some((message) => message.id === sentId),
      '其他分片没有刷新到新消息');

    response = await call(shardA.base, alice.cookie, 'POST',
      '/api/messages/' + sentId + '/recall', { chatId });
    assert.equal(response.status, 200, JSON.stringify(response.data));
    await new Promise((resolve) => setTimeout(resolve, 400));
    response = await call(shardB.base, bob.cookie, 'GET',
      '/api/chats/' + chatId + '/messages?limit=50');
    const recalled = (response.data.messages || []).find((message) => message.id === sentId);
    assert.ok(recalled && recalled.recalled === true,
      '其他分片仍返回撤回前的消息');

    response = await call(shardA.base, alice.cookie, 'POST', '/api/me/delete', { confirm: '注销' });
    assert.equal(response.status, 200, JSON.stringify(response.data));
    assert.equal(response.data.deleted, true);
    await new Promise((resolve) => setTimeout(resolve, 1500));

    response = await call(shardB.base, alice.cookie, 'GET', '/api/session');
    assert.equal(response.status, 200);
    assert.equal(response.data.authenticated, false, '其他分片仍接受注销账号令牌');

    response = await call(shardB.base, bob.cookie, 'GET', '/api/contacts');
    assert.equal(response.status, 200);
    assert.ok(!(response.data.friends || []).some((friend) => friend.id === alice.user.id),
      '其他分片仍返回已注销好友');

    response = await call(shardB.base, bob.cookie, 'GET', '/api/chats');
    assert.equal(response.status, 200);
    assert.ok(!(response.data.chats || []).some((chat) => chat.id === chatId),
      '其他分片仍返回已注销会话');
    assert.ok(!fs.existsSync(path.join(dataDir, 'uploads', uploadName)));
    assert.ok(!fs.existsSync(path.join(dataDir, 'messages', chatId + '.jsonl')));

    response = await call(shardB.base, bob.cookie, 'POST', '/api/me/delete', { confirm: '注销' });
    assert.equal(response.status, 200, JSON.stringify(response.data));
    const deletionRows = fs.readFileSync(path.join(dataDir, 'account-deletions.jsonl'), 'utf8')
      .split('\n').filter(Boolean).map((line) => JSON.parse(line));
    assert.equal(new Set(deletionRows.map((row) => row.key)).size, 2,
      '并发注销墓碑互相覆盖');
    assert.ok(deletionRows.every((row) => !row.userId),
      '注销墓碑不能保存原始用户 ID');

    console.log('account-deletion-shards: passed');
  } finally {
    await stopServer(shardA && shardA.child);
    await stopServer(shardB && shardB.child);
    await stopServer(setup && setup.child);
    fs.rmSync(dataDir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
