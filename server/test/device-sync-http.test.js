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

async function startServer(dataDir, port) {
  const base = 'http://127.0.0.1:' + port;
  const logs = [];
  const child = spawn(process.execPath, ['server.js'], {
    cwd: SERVER_DIR,
    env: Object.assign({}, process.env, {
      DATA_DIR: dataDir,
      PORT: String(port),
      TURN_PORT: String(await freePort()),
      CHRIS_LOCAL_ONLY: '1',
      MESSAGE_RELIABILITY_ENABLED: '1'
    }),
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true
  });
  child.stdout.on('data', (chunk) => logs.push(chunk.toString()));
  child.stderr.on('data', (chunk) => logs.push(chunk.toString()));
  for (let index = 0; index < 120; index += 1) {
    if (child.exitCode !== null) throw new Error(logs.join(''));
    try {
      if ((await fetch(base + '/api/health')).ok) return { child, base, logs };
    } catch (_) { }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('server start timeout\n' + logs.join(''));
}

async function call(base, cookie, method, route, body, deviceId) {
  const headers = {
    'x-device-kind': 'desktop',
    'x-device-id': deviceId
  };
  if (cookie) headers.Cookie = cookie;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const response = await fetch(base + route, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const text = await response.text();
  let data = {};
  try { data = text ? JSON.parse(text) : {}; } catch (_) { data = { raw: text }; }
  return {
    status: response.status,
    data: data && data.data !== undefined ? data.data : data,
    headers: response.headers
  };
}

async function login(base, username, deviceId) {
  const response = await call(base, '', 'POST', '/api/login', {
    username,
    password: PASSWORD
  }, deviceId);
  assert.strictEqual(response.status, 200, JSON.stringify(response.data));
  const cookie = (response.headers.getSetCookie
    ? response.headers.getSetCookie()[0]
    : response.headers.get('set-cookie') || '').split(';')[0];
  return { cookie, user: response.data.user };
}

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'chris-device-sync-http-'));
  let child = null;
  try {
    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({
      users: [
        user('u_sync_alice', 'sync_alice', 'Alice'),
        user('u_sync_bob', 'sync_bob', 'Bob')
      ]
    }, null, 2));
    fs.writeFileSync(path.join(dataDir, 'security.json'),
      JSON.stringify({ sliderLogin: 0 }, null, 2));
    fs.writeFileSync(path.join(dataDir, 'ui.json'),
      JSON.stringify({ multiDevice: 1 }, null, 2));
    fs.writeFileSync(path.join(dataDir, 'im.json'),
      JSON.stringify({ allowStranger: true }, null, 2));

    let running = await startServer(dataDir, await freePort());
    child = running.child;
    let base = running.base;
    const alice = await login(base, 'sync_alice', 'alice-phone');
    const phone = await login(base, 'sync_bob', 'bob-phone');
    const desktop = await login(base, 'sync_bob', 'bob-desktop');

    let response = await call(base, alice.cookie, 'POST', '/api/chats/direct', {
      userId: phone.user.id
    }, 'alice-phone');
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const chatId = response.data.chat.id;
    for (let seq = 1; seq <= 5; seq += 1) {
      response = await call(base, alice.cookie, 'POST',
        `/api/chats/${chatId}/messages`, {
          kind: 'text',
          content: 'message ' + seq,
          clientId: 'sync-' + seq
        }, 'alice-phone');
      assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    }

    response = await call(base, phone.cookie, 'GET',
      '/api/sync/state?limit=20', undefined, 'bob-phone');
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(response.data.enabled, true);
    let item = response.data.items.find((row) => row.chatId === chatId);
    assert.deepStrictEqual({
      lastSeq: item.lastSeq,
      deliveredSeq: item.deliveredSeq,
      readSeq: item.readSeq,
      hasDelta: item.hasDelta
    }, { lastSeq: 5, deliveredSeq: 0, readSeq: 0, hasDelta: true });

    response = await call(base, phone.cookie, 'POST', '/api/sync/ack', {
      items: [{ chatId, seq: 5 }]
    }, 'bob-phone');
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(response.data.acknowledged, 1);

    response = await call(base, desktop.cookie, 'GET',
      '/api/sync/state?limit=20', undefined, 'bob-desktop');
    item = response.data.items.find((row) => row.chatId === chatId);
    assert.strictEqual(item.deliveredSeq, 0);
    assert.strictEqual(item.hasDelta, true);

    child.kill();
    await new Promise((resolve) => child.once('exit', resolve));
    running = await startServer(dataDir, await freePort());
    child = running.child;
    base = running.base;

    response = await call(base, phone.cookie, 'GET',
      '/api/sync/state?limit=20', undefined, 'bob-phone');
    item = response.data.items.find((row) => row.chatId === chatId);
    assert.strictEqual(item.deliveredSeq, 5);
    assert.strictEqual(item.hasDelta, false);

    response = await call(base, alice.cookie, 'POST',
      `/api/chats/${chatId}/messages`, {
        kind: 'text',
        content: 'after restart',
        clientId: 'sync-6'
      }, 'alice-phone');
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    response = await call(base, phone.cookie, 'GET',
      '/api/sync/state?limit=20', undefined, 'bob-phone');
    item = response.data.items.find((row) => row.chatId === chatId);
    assert.strictEqual(item.lastSeq, 6);
    assert.strictEqual(item.deliveredSeq, 5);
    assert.strictEqual(item.hasDelta, true);
    console.log('device-sync-http: passed');
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
