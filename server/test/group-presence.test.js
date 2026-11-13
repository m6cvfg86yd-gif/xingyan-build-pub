'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const SERVER_DIR = path.resolve(__dirname, '..');
const PASSWORD = 'GroupPresence1027!';

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

function user(id, username, salt) {
  return {
    id,
    username,
    nickname: username,
    phone: '',
    realName: '',
    gender: 'secret',
    balance: 0,
    transferLimit: 20000,
    salt,
    passwordHash: crypto.scryptSync(PASSWORD, salt, 64).toString('hex'),
    favorites: [],
    createdAt: new Date().toISOString(),
    tokenVersion: 0,
    phoneSession: 0
  };
}

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'chris-group-presence-'));
  const port = await freePort();
  const httpsPort = await freePort();
  const turnPort = await freePort();
  const base = 'http://127.0.0.1:' + port;
  const logs = [];
  let child;

  try {
    const salt1 = crypto.randomBytes(16).toString('hex');
    const salt2 = crypto.randomBytes(16).toString('hex');
    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({
      users: [
        user('u_group_viewer', 'group_viewer', salt1),
        user('u_group_online', 'group_online', salt2)
      ]
    }));
    fs.writeFileSync(path.join(dataDir, 'friendships.json'), JSON.stringify({ friendships: [] }));
    fs.writeFileSync(path.join(dataDir, 'chats.json'), JSON.stringify({
      chats: [{
        id: 'c_group_presence',
        type: 'group',
        name: 'Presence group',
        avatar: '',
        memberIds: ['u_group_viewer', 'u_group_online'],
        ownerId: 'u_group_viewer',
        seq: 0,
        createdAt: new Date().toISOString(),
        pinnedFor: [],
        mutedFor: []
      }]
    }));
    fs.writeFileSync(path.join(dataDir, 'security.json'), JSON.stringify({ sliderLogin: 0 }));
    fs.writeFileSync(path.join(dataDir, 'ui.json'), JSON.stringify({ multiDevice: 1 }));
    const secret = crypto.randomBytes(32).toString('hex');
    fs.writeFileSync(path.join(dataDir, 'secret.key'), secret);

    child = spawn(process.execPath, ['server.js'], {
      cwd: SERVER_DIR,
      env: Object.assign({}, process.env, {
        DATA_DIR: dataDir,
        PORT: String(port),
        SHARD_BASE_PORT: String(port),
        SHARD_COUNT: '2',
        HTTPS_PORT: String(httpsPort),
        TURN_PORT: String(turnPort),
        ADMIN_PASSWORD: 'test-admin-password',
        CHRIS_LOCAL_ONLY: '1',
        DISABLE_STARTUP_BOT_BACKFILL: '1'
      }),
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true
    });
    child.stdout.on('data', (chunk) => logs.push(chunk.toString()));
    child.stderr.on('data', (chunk) => logs.push(chunk.toString()));
    for (let i = 0; i < 200; i += 1) {
      if (child.exitCode !== null) throw new Error('测试服务提前退出：\n' + logs.join(''));
      try {
        if ((await fetch(base + '/api/health')).ok) break;
      } catch (_) {
        // Wait for startup.
      }
      await new Promise((resolve) => setTimeout(resolve, 100));
    }

    const login = await fetch(base + '/api/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-device-kind': 'phone' },
      body: JSON.stringify({ username: 'group_viewer', password: PASSWORD })
    });
    assert.equal(login.status, 200, await login.text());
    const rawCookie = login.headers.getSetCookie
      ? login.headers.getSetCookie()[0]
      : login.headers.get('set-cookie') || '';
    const cookie = rawCookie.split(';')[0];

    const presence = await fetch(base + '/__shard/presence-event', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Shard-Relay': secret
      },
      body: JSON.stringify({
        userId: 'u_group_online',
        online: true,
        port: port + 100
      })
    });
    assert.equal(presence.status, 200, await presence.text());

    const chatsResponse = await fetch(base + '/api/chats', {
      headers: { Cookie: cookie, 'x-device-kind': 'phone' }
    });
    const chatsText = await chatsResponse.text();
    assert.equal(chatsResponse.status, 200, chatsText);
    const payload = JSON.parse(chatsText);
    const group = (payload.data && payload.data.chats || []).find((c) => c.id === 'c_group_presence');
    assert.ok(group, JSON.stringify(payload));
    assert.deepEqual(group.onlineMemberIds, ['u_group_online']);
    console.log('group-presence: passed');
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
