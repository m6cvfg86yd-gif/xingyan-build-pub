'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');
const { ShardCluster } = require('../lib/shard-runtime');
const { compareLegacyState } = require('../lib/shard-shadow');

const SERVER_DIR = path.resolve(__dirname, '..');
const PASSWORD = 'shadow-test-password';
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

function makeUser(id, username, nickname) {
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
    balance: 100,
    salt,
    passwordHash: crypto.scryptSync(PASSWORD, salt, 64).toString('hex'),
    paySalt,
    payPasswordHash: crypto.scryptSync(PAY_PASSWORD, paySalt, 64).toString('hex'),
    realName: nickname,
    realNameVerified: true,
    idCardHash: crypto.createHash('sha256').update('shadow:' + id).digest('hex'),
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

async function currentBalance(base, cookie) {
  const response = await call(base, 'GET', '/api/me', undefined, cookie);
  assert.strictEqual(response.status, 200, JSON.stringify(response.data));
  return Number(response.data.user.balance) || 0;
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

async function stopServer(child) {
  if (!child || child.exitCode !== null) return;
  child.kill();
  await new Promise((resolve) => {
    const timer = setTimeout(resolve, 3000);
    child.once('exit', () => {
      clearTimeout(timer);
      resolve();
    });
  });
}

async function waitForCleanAudit(dataDir, timeoutMs) {
  const file = path.join(dataDir, 'shard-shadow', 'shadow-audit.json');
  const deadline = Date.now() + (timeoutMs || 5000);
  let last = null;
  while (Date.now() < deadline) {
    try {
      last = JSON.parse(fs.readFileSync(file, 'utf8'));
      if (last.ok === true) return last;
    } catch (_) { /* audit is still being written */ }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('shadow audit did not become clean: ' + JSON.stringify(last));
}

function readCollection(dataDir, name) {
  try {
    const row = JSON.parse(fs.readFileSync(path.join(dataDir, name + '.json'), 'utf8'));
    return Array.isArray(row && row[name]) ? row[name] : [];
  } catch (_) {
    return [];
  }
}

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-shard-shadow-server-'));
  const port = await freePort();
  const turnPort = await freePort();
  const base = 'http://127.0.0.1:' + port;
  const logs = [];
  let child;

  try {
    const aliceFixture = makeUser('shadow_alice', 'shadow_alice', 'Alice');
    const bobFixture = makeUser('shadow_bob', 'shadow_bob', 'Bob');
    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({
      users: [aliceFixture, bobFixture]
    }));
    fs.writeFileSync(path.join(dataDir, 'security.json'), JSON.stringify({
      sliderLogin: 0,
      allowRecharge: 0
    }));
    fs.writeFileSync(path.join(dataDir, 'ui.json'), JSON.stringify({ multiDevice: 1 }));

    child = spawn(process.execPath, ['server.js'], {
      cwd: SERVER_DIR,
      env: Object.assign({}, process.env, {
        DATA_DIR: dataDir,
        PORT: String(port),
        TURN_PORT: String(turnPort),
        CHRIS_LOCAL_ONLY: '1',
        AML_RUNTIME_ENABLED: '0',
        SHARD_SHADOW_ENABLED: '1',
        SHARD_SHADOW_AUDIT_MS: '1000',
        SHARD_COUNT: '6',
        SHARD_TOPOLOGY_ID: 'server-a-shards-6',
        ADMIN_PASSWORD: 'shadow-test-admin'
      }),
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true
    });
    child.stdout.on('data', (chunk) => logs.push(chunk.toString()));
    child.stderr.on('data', (chunk) => logs.push(chunk.toString()));
    await waitForHealth(base, child, logs);
    assert.ok(logs.join('').includes('[分片影子] 已启用'), logs.join(''));

    const alice = await login(base, 'shadow_alice');
    const bob = await login(base, 'shadow_bob');

    let response = await call(base, 'POST', '/api/friends/request', {
      username: 'shadow_bob'
    }, alice.cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    response = await call(base, 'GET', '/api/contacts', undefined, bob.cookie);
    const request = (response.data.incoming || [])[0];
    assert.ok(request && request.requestId);
    response = await call(base, 'POST', '/api/friends/respond', {
      requestId: request.requestId,
      accept: true
    }, bob.cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));

    response = await call(base, 'GET', '/api/users?q=shadow_bob', undefined, alice.cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    response = await call(base, 'POST', '/api/chats/direct', {
      userId: bob.user.id
    }, alice.cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const chatId = response.data.chat.id;

    response = await call(base, 'POST', '/api/chats/' + chatId + '/messages', {
      kind: 'text',
      content: 'shadow message',
      clientId: 'shadow-client-message-1'
    }, alice.cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    response = await call(base, 'POST', '/api/chats/' + chatId + '/unread', {}, bob.cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    response = await call(base, 'POST', '/api/chats/' + chatId + '/read', {}, bob.cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    for (const [endpoint, method] of [
      ['/api/chats', 'GET'],
      ['/api/moments', 'GET'],
      ['/api/moments/notices', 'GET']
    ]) {
      response = await call(base, method, endpoint, undefined, alice.cookie);
      assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    }

    response = await call(base, 'POST', '/api/chats/' + chatId + '/pin', {}, bob.cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    response = await call(base, 'POST', '/api/chats/' + chatId + '/pin', {}, bob.cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    response = await call(base, 'DELETE', '/api/chats/' + chatId, undefined, bob.cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    response = await call(base, 'POST', '/api/chats/' + chatId + '/messages', {
      kind: 'text',
      content: 'revive hidden chat',
      clientId: 'shadow-client-message-2'
    }, alice.cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));

    response = await call(base, 'POST', '/api/moments', {
      content: 'shadow moment',
      images: []
    }, alice.cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const momentId = response.data.moment.id;
    for (let i = 0; i < 3; i += 1) {
      response = await call(base, 'POST', '/api/moments/' + momentId + '/like', {}, bob.cookie);
      assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    }
    response = await call(base, 'POST', '/api/moments/' + momentId + '/comments', {
      content: 'shadow comment'
    }, bob.cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const comments = response.data.moment && response.data.moment.comments || [];
    const commentId = comments[comments.length - 1] && comments[comments.length - 1].id;
    assert.ok(commentId);
    for (let i = 0; i < 3; i += 1) {
      response = await call(
        base,
        'POST',
        '/api/moments/' + momentId + '/comments/' + commentId + '/like',
        {},
        alice.cookie
      );
      assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    }

    response = await call(base, 'POST', '/api/pay/transfer', {
      chatId,
      amount: 1,
      password: PAY_PASSWORD,
      requestId: 'shadow-transfer-request-1',
      note: 'shadow transfer'
    }, alice.cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const transferId = response.data.transfer.id;
    const beforeClaim = await currentBalance(base, bob.cookie);
    response = await call(base, 'POST', '/api/transfers/' + transferId + '/claim', {}, bob.cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const afterFirstClaim = Number(response.data.balance) || 0;
    assert.strictEqual(afterFirstClaim, beforeClaim + 1, 'first claim must credit exactly once');
    response = await call(base, 'POST', '/api/transfers/' + transferId + '/claim', {}, bob.cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(response.data.alreadyReceived, true);
    assert.strictEqual(Number(response.data.balance) || 0, afterFirstClaim,
      'repeated claim must not credit the wallet twice');
    assert.strictEqual(await currentBalance(base, bob.cookie), afterFirstClaim);
    response = await call(base, 'GET', '/api/bills/ledger?limit=100', undefined, bob.cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(response.data.verified, true, 'wallet and authoritative ledger must match');
    const transferEntries = (response.data.entries || [])
      .filter((entry) => entry.ref === transferId);
    assert.strictEqual(transferEntries.length, 1, 'one claim must create exactly one ledger fact');
    assert.strictEqual(transferEntries[0].direction, 'in');
    assert.strictEqual(Number(transferEntries[0].delta), 1);

    response = await call(base, 'POST', '/api/chats/group', {
      name: 'shadow group',
      memberIds: [bob.user.id]
    }, alice.cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const groupId = response.data.chat.id;
    response = await call(base, 'POST', '/api/chats/' + groupId + '/dismiss', {}, alice.cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));

    const audit = await waitForCleanAudit(dataDir, 8000);
    assert.strictEqual(audit.snapshotsEnabled, true);

    await stopServer(child);
    child = null;

    const legacy = {
      friendships: readCollection(dataDir, 'friendships'),
      chats: readCollection(dataDir, 'chats'),
      moments: readCollection(dataDir, 'moments'),
      transfers: readCollection(dataDir, 'transfers')
    };
    const cluster = new ShardCluster({
      dataDir: path.join(dataDir, 'shard-shadow'),
      shardCount: 6,
      topologyId: 'server-a-shards-6'
    });
    const comparison = compareLegacyState(cluster, legacy);
    assert.strictEqual(comparison.ok, true, JSON.stringify(comparison.diffs));
    assert.strictEqual(cluster.verify().ok, true);

    const likeRow = cluster.get('moment_like', momentId + '|' + bob.user.id);
    assert.ok(likeRow && !likeRow.deleted, 're-like must restore the shadow row');
    const commentLikeRow = cluster.get(
      'moment_comment_like',
      momentId + '|' + commentId + '|' + alice.user.id
    );
    assert.ok(commentLikeRow && !commentLikeRow.deleted, 'comment re-like must restore the shadow row');
    const transferRow = cluster.get('transfer', transferId);
    assert.strictEqual(transferRow && transferRow.payload.state, 'claimed');
    assert.strictEqual(transferRow.payload.authority, 'payment-ledger');
    assert.strictEqual(transferRow.payload.fromId, alice.user.id);
    assert.strictEqual(transferRow.payload.toId, bob.user.id);
    assert.strictEqual(Number(transferRow.payload.amount), 1);
    const groupRow = cluster.get('chat', groupId);
    assert.strictEqual(groupRow && groupRow.deleted, true);

    console.log('shard-shadow-server: passed');
  } finally {
    await stopServer(child);
    fs.rmSync(dataDir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
