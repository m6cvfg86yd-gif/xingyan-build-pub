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
    if (child.exitCode !== null) throw new Error('server exited:\n' + logs.join(''));
    try {
      if ((await fetch(base + '/api/health')).ok) return;
    } catch (_) {}
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('server start timeout:\n' + logs.join(''));
}

async function call(base, cookie, method, url, body, deviceId = 'test-device') {
  const headers = { 'x-device-kind': 'desktop', 'x-device-id': deviceId };
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

async function login(base, username, deviceId) {
  const response = await call(base, '', 'POST', '/api/login', {
    username, password: PASSWORD
  }, deviceId);
  assert.strictEqual(response.status, 200, JSON.stringify(response.data));
  const cookie = (response.headers.getSetCookie
    ? response.headers.getSetCookie()[0]
    : response.headers.get('set-cookie') || '').split(';')[0];
  return { cookie, user: response.data.user };
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
  await waitForHealth(base, child, logs);
  return { child, base, logs };
}

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'chris-messages-since-'));
  let child;
  try {
    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({
      users: [
        user('u_since_alice', 'since_alice', 'Alice'),
        user('u_since_bob', 'since_bob', 'Bob')
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

    const alice = await login(base, 'since_alice', 'alice-phone');
    const bobPhone = await login(base, 'since_bob', 'bob-phone');
    const bobDesktop = await login(base, 'since_bob', 'bob-desktop');
    let response = await call(base, alice.cookie, 'POST', '/api/chats/direct', {
      userId: bobPhone.user.id
    }, 'alice-phone');
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const chatId = response.data.chat.id;

    for (let index = 1; index <= 5; index += 1) {
      response = await call(base, alice.cookie, 'POST',
        `/api/chats/${chatId}/messages`, {
          kind: 'text',
          content: `message ${index}`,
          clientId: `since-${index}`
        }, 'alice-phone');
      assert.strictEqual(response.status, 200, JSON.stringify(response.data));
      assert.strictEqual(response.data.message.seq, index);
    }

    response = await call(base, alice.cookie, 'POST',
      `/api/chats/${chatId}/messages`, {
        kind: 'text',
        content: 'message 3 retried',
        clientId: 'since-3'
      }, 'alice-phone');
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(response.data.message.seq, 3);

    response = await call(base, bobPhone.cookie, 'GET',
      `/api/chats/${chatId}/messages?since=0&limit=3`, undefined, 'bob-phone');
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.deepStrictEqual(response.data.messages.map((m) => m.seq), [1, 2, 3]);
    assert.strictEqual(response.data.hasMore, true);

    response = await call(base, bobPhone.cookie, 'GET',
      `/api/chats/${chatId}/messages?since=3&limit=3`, undefined, 'bob-phone');
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.deepStrictEqual(response.data.messages.map((m) => m.seq), [4, 5]);
    assert.strictEqual(response.data.hasMore, false);

    response = await call(base, bobPhone.cookie, 'POST',
      `/api/chats/${chatId}/read`, {}, 'bob-phone');
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));

    response = await call(base, bobPhone.cookie, 'GET',
      `/api/chats/${chatId}/cursor`, undefined, 'bob-phone');
    assert.strictEqual(response.data.cursor.readSeq, 5);
    assert.strictEqual(response.data.cursor.deliveredSeq, 5);

    response = await call(base, bobDesktop.cookie, 'GET',
      `/api/chats/${chatId}/cursor`, undefined, 'bob-desktop');
    assert.strictEqual(response.data.cursor.readSeq, 0);
    assert.strictEqual(response.data.cursor.deliveredSeq, 0);

    if (child.exitCode === null) child.kill();
    await new Promise((resolve) => setTimeout(resolve, 350));
    running = await startServer(dataDir, await freePort());
    child = running.child;
    base = running.base;

    response = await call(base, alice.cookie, 'POST',
      `/api/chats/${chatId}/messages`, {
        kind: 'text',
        content: 'after restart',
        clientId: 'since-6'
      }, 'alice-phone');
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(response.data.message.seq, 6);

    response = await call(base, bobDesktop.cookie, 'GET',
      `/api/chats/${chatId}/messages?since=5&limit=10`, undefined, 'bob-desktop');
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.deepStrictEqual(response.data.messages.map((m) => m.seq), [6]);

    response = await call(base, bobDesktop.cookie, 'GET',
      `/api/chats/${chatId}/messages?since=0&limit=100`, undefined, 'bob-desktop');
    assert.deepStrictEqual(response.data.messages.map((m) => m.seq), [1, 2, 3, 4, 5, 6]);

    const lastMessageId = response.data.messages[5].id;
    response = await call(base, alice.cookie, 'POST',
      `/api/messages/${lastMessageId}/recall`, { chatId }, 'alice-phone');
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));

    response = await call(base, bobDesktop.cookie, 'GET',
      '/api/message-events?after=0&limit=100', undefined, 'bob-desktop');
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.ok(response.data.events.some((event) =>
      event.type === 'message.recalled'
      && event.payload.messageId === lastMessageId));
    const eventCursor = response.data.sequence;

    response = await call(base, bobDesktop.cookie, 'POST',
      `/api/chats/${chatId}/clear`, {}, 'bob-desktop');
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));

    response = await call(base, bobDesktop.cookie, 'GET',
      `/api/message-events?after=${eventCursor}&limit=100`, undefined, 'bob-desktop');
    assert.ok(response.data.events.some((event) =>
      event.type === 'chat.cleared'
      && event.payload.chatId === chatId
      && event.payload.userId === bobDesktop.user.id));

    response = await call(base, bobDesktop.cookie, 'GET',
      `/api/chats/${chatId}/messages?since=0&limit=100`, undefined, 'bob-desktop');
    assert.deepStrictEqual(response.data.messages, []);

    console.log('messages-since: passed');
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
