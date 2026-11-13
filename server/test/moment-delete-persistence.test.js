'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const SERVER_DIR = path.resolve(__dirname, '..');
const PASSWORD = 'moment-delete-test';

function freePort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const port = server.address().port;
      server.close(() => resolve(port));
    });
  });
}

function makeUser() {
  const salt = crypto.randomBytes(16).toString('hex');
  return {
    id: 'u_moment_delete',
    username: 'moment_delete',
    nickname: 'Moment Delete',
    avatar: '',
    bio: '',
    phone: '',
    gender: 'secret',
    balance: 0,
    salt,
    passwordHash: crypto.scryptSync(PASSWORD, salt, 64).toString('hex'),
    createdAt: '2026-11-12T00:00:00.000Z',
    tokenVersion: 0,
    phoneSession: 0
  };
}

async function waitForHealth(base, child, logs) {
  for (let attempt = 0; attempt < 160; attempt += 1) {
    if (child.exitCode !== null) throw new Error('server exited:\n' + logs.join(''));
    try {
      if ((await fetch(base + '/api/health')).ok) return;
    } catch (_) {
      /* starting */
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('server startup timeout:\n' + logs.join(''));
}

async function start(dataDir, port, turnPort) {
  const logs = [];
  const child = spawn(process.execPath, ['server.js'], {
    cwd: SERVER_DIR,
    env: Object.assign({}, process.env, {
      DATA_DIR: dataDir,
      PORT: String(port),
      TURN_PORT: String(turnPort),
      CHRIS_LOCAL_ONLY: '1',
      SHARD_SHADOW_ENABLED: '0',
      DISABLE_STARTUP_BOT_BACKFILL: '1',
      DISABLE_MOMENT_LOG_REPLAY: '1',
      DISABLE_MONEY_EXPIRY: '1',
      ADMIN_PASSWORD: 'moment-delete-test-admin'
    }),
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true
  });
  child.stdout.on('data', (chunk) => logs.push(chunk.toString()));
  child.stderr.on('data', (chunk) => logs.push(chunk.toString()));
  const base = 'http://127.0.0.1:' + port;
  await waitForHealth(base, child, logs);
  return { child, base };
}

async function stop(child) {
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

async function call(base, method, endpoint, body, cookie) {
  const headers = { 'X-Device-Kind': 'desktop' };
  if (cookie) headers.Cookie = cookie;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const response = await fetch(base + endpoint, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const text = await response.text();
  const json = text ? JSON.parse(text) : {};
  assert.ok(response.ok, method + ' ' + endpoint + ': ' + text);
  return {
    data: json.data === undefined ? json : json.data,
    headers: response.headers
  };
}

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-moment-delete-'));
  const port = await freePort();
  const turnPort = await freePort();
  let server = null;
  try {
    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({ users: [makeUser()] }));
    fs.writeFileSync(path.join(dataDir, 'security.json'), JSON.stringify({
      sliderLogin: 0,
      allowRecharge: 0
    }));
    fs.writeFileSync(path.join(dataDir, 'ui.json'), JSON.stringify({ multiDevice: 1 }));
    fs.writeFileSync(path.join(dataDir, 'moment-notices.json'), JSON.stringify({
      items: [],
      seen: {}
    }));

    server = await start(dataDir, port, turnPort);
    const login = await call(server.base, 'POST', '/api/login', {
      username: 'moment_delete',
      password: PASSWORD
    });
    const rawCookie = login.headers.getSetCookie
      ? login.headers.getSetCookie()[0]
      : login.headers.get('set-cookie') || '';
    const cookie = rawCookie.split(';')[0];
    assert.ok(cookie);

    const marker = 'delete-persistence-marker';
    const created = await call(server.base, 'POST', '/api/moments', {
      content: marker,
      images: [],
      visibility: 'private'
    }, cookie);
    const momentId = created.data.moment.id;
    await call(server.base, 'DELETE', '/api/moments/' + momentId, undefined, cookie);
    assert.strictEqual(
      fs.readFileSync(path.join(dataDir, 'moments-log.jsonl'), 'utf8').trim(),
      ''
    );

    await stop(server.child);
    server = null;
    server = await start(dataDir, port, turnPort);
    const feed = await call(server.base, 'GET', '/api/moments?limit=100', undefined, cookie);
    assert.ok(!(feed.data.moments || []).some((row) => row.id === momentId));
  } finally {
    await stop(server && server.child);
    fs.rmSync(dataDir, { recursive: true, force: true });
  }
}

main().then(() => {
  console.log('moment-delete-persistence: passed');
}).catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
