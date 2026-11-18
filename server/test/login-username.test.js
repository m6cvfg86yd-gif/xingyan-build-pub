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

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'chris-login-username-'));
  const port = await freePort();
  const turnPort = await freePort();
  const base = 'http://127.0.0.1:' + port;
  const logs = [];
  let child;

  try {
    const salt = crypto.randomBytes(16).toString('hex');
    const username = 'existing_star_id';
    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({
      users: [{
        id: 'u_existing_star_id',
        username,
        nickname: '老客户',
        phone: '',
        avatar: '',
        bio: '',
        gender: 'secret',
        balance: 0,
        transferLimit: 20000,
        salt,
        passwordHash: crypto.scryptSync(PASSWORD, salt, 64).toString('hex'),
        createdAt: new Date().toISOString(),
        tokenVersion: 0,
        phoneSession: 0
      }]
    }), 'utf8');
    fs.writeFileSync(path.join(dataDir, 'security.json'), '{}', 'utf8');
    fs.writeFileSync(path.join(dataDir, 'ui.json'), JSON.stringify({ multiDevice: 1 }), 'utf8');

    child = spawn(process.execPath, ['server.js'], {
      cwd: SERVER_DIR,
      env: Object.assign({}, process.env, {
        DATA_DIR: dataDir,
        PORT: String(port),
        TURN_PORT: String(turnPort),
        CHRIS_LOCAL_ONLY: '1',
        AML_RUNTIME_ENABLED: '0',
        DISABLE_STARTUP_BOT_BACKFILL: '1'
      }),
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true
    });
    child.stdout.on('data', (chunk) => logs.push(chunk.toString()));
    child.stderr.on('data', (chunk) => logs.push(chunk.toString()));

    let ready = false;
    for (let i = 0; i < 120; i += 1) {
      if (child.exitCode !== null) throw new Error(logs.join(''));
      try {
        if ((await fetch(base + '/api/health')).ok) { ready = true; break; }
      } catch (_) {}
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    assert.equal(ready, true, 'server start timeout');

    const response = await fetch(base + '/api/login', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-device-kind': 'phone',
        'x-device-id': 'fresh-reinstall-device-id'
      },
      body: JSON.stringify({ username, password: PASSWORD })
    });
    const payload = await response.json();
    assert.equal(response.status, 200, JSON.stringify(payload));
    assert.equal(payload.data.user.username, username);

    console.log('login-username: passed');
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
