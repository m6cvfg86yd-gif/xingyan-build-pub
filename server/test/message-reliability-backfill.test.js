'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');
const { DatabaseSync } = require('node:sqlite');

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

async function call(base, cookie, method, url, body) {
  const headers = {
    'x-device-kind': 'desktop',
    'x-device-id': 'backfill-device'
  };
  if (cookie) headers.Cookie = cookie;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const response = await fetch(base + url, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body)
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
  const response = await call(base, '', 'POST', '/api/login', {
    username,
    password: PASSWORD
  });
  assert.strictEqual(response.status, 200, JSON.stringify(response.data));
  const cookie = (response.headers.getSetCookie
    ? response.headers.getSetCookie()[0]
    : response.headers.get('set-cookie') || '').split(';')[0];
  return { cookie, user: response.data.user };
}

async function startServer(dataDir, reliability, backfill) {
  const port = await freePort();
  const base = 'http://127.0.0.1:' + port;
  const logs = [];
  const child = spawn(process.execPath, ['server.js'], {
    cwd: SERVER_DIR,
    env: Object.assign({}, process.env, {
      DATA_DIR: dataDir,
      PORT: String(port),
      TURN_PORT: String(await freePort()),
      CHRIS_LOCAL_ONLY: '1',
      MESSAGE_RELIABILITY_ENABLED: reliability ? '1' : '0',
      MESSAGE_RELIABILITY_BACKFILL: backfill ? '1' : '0'
    }),
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true
  });
  child.stdout.on('data', (chunk) => logs.push(chunk.toString()));
  child.stderr.on('data', (chunk) => logs.push(chunk.toString()));
  for (let index = 0; index < 120; index += 1) {
    if (child.exitCode !== null) throw new Error('server exited:\n' + logs.join(''));
    try {
      if ((await fetch(base + '/api/health')).ok) return { child, base, logs };
    } catch (_) { /* retry */ }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('server start timeout:\n' + logs.join(''));
}

async function stopServer(child) {
  if (child && child.exitCode === null) child.kill();
  await new Promise((resolve) => setTimeout(resolve, 400));
}

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'chris-message-backfill-'));
  let child;
  try {
    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({
      users: [
        user('u_backfill_alice', 'backfill_alice', 'Alice'),
        user('u_backfill_bob', 'backfill_bob', 'Bob')
      ]
    }, null, 2));
    fs.writeFileSync(path.join(dataDir, 'security.json'),
      JSON.stringify({ sliderLogin: 0 }, null, 2));
    fs.writeFileSync(path.join(dataDir, 'ui.json'),
      JSON.stringify({ multiDevice: 1 }, null, 2));
    fs.writeFileSync(path.join(dataDir, 'im.json'),
      JSON.stringify({ allowStranger: true }, null, 2));

    let running = await startServer(dataDir, false, false);
    child = running.child;
    let base = running.base;

    const alice = await login(base, 'backfill_alice');
    const bob = await login(base, 'backfill_bob');
    let response = await call(base, alice.cookie, 'POST', '/api/chats/direct', {
      userId: bob.user.id
    });
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const chatId = response.data.chat.id;
    for (let index = 1; index <= 3; index += 1) {
      response = await call(base, alice.cookie, 'POST',
        `/api/chats/${chatId}/messages`, {
          kind: 'text',
          content: `legacy ${index}`,
          clientId: `legacy-${index}`
        });
      assert.strictEqual(response.status, 200, JSON.stringify(response.data));
      assert.strictEqual(response.data.message.seq, index);
    }
    await new Promise((resolve) => setTimeout(resolve, 1700));
    await stopServer(child);

    running = await startServer(dataDir, true, true);
    child = running.child;
    base = running.base;

    const databaseFile = path.join(dataDir, 'message-reliability.sqlite3');
    const database = new DatabaseSync(databaseFile, { readOnly: true });
    const count = database.prepare(
      'SELECT COUNT(*) AS count FROM reliable_messages WHERE chat_id = ?'
    ).get(chatId);
    const sequence = database.prepare(
      'SELECT last_seq FROM chat_sequence WHERE chat_id = ?'
    ).get(chatId);
    const marker = database.prepare(
      "SELECT value FROM reliability_metadata WHERE key = 'legacy-backfill-v1'"
    ).get();
    database.close();
    assert.strictEqual(Number(count.count), 3);
    assert.strictEqual(Number(sequence.last_seq), 3);
    assert.ok(marker && JSON.parse(marker.value).conflicts === 0);

    response = await call(base, alice.cookie, 'POST',
      `/api/chats/${chatId}/messages`, {
        kind: 'text',
        content: 'post backfill',
        clientId: 'post-backfill'
      });
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(response.data.message.seq, 4);

    console.log('message-reliability-backfill: passed');
  } finally {
    await stopServer(child);
    fs.rmSync(dataDir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
