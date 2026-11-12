'use strict';

const assert = require('assert');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const SERVER_DIR = path.resolve(__dirname, '..');

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

async function call(base, method, endpoint, body, cookie) {
  const headers = { 'x-device-kind': 'phone' };
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

function readUsers(dataDir) {
  return JSON.parse(fs.readFileSync(path.join(dataDir, 'users.json'), 'utf8')).users || [];
}

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'chris-legacy-aml-'));
  const port = await freePort();
  const turnPort = await freePort();
  const base = 'http://127.0.0.1:' + port;
  const logs = [];
  let child;

  try {
    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({
      users: [{
        id: 'legacy_user_1',
        username: 'legacy001',
        nickname: '老客户一号',
        avatar: '',
        bio: '',
        balance: 120,
        createdAt: '2026-01-01T00:00:00.000Z',
        tokenVersion: 0
      }]
    }));
    fs.writeFileSync(path.join(dataDir, 'security.json'), JSON.stringify({ sliderLogin: 0 }));
    fs.writeFileSync(path.join(dataDir, 'ui.json'), JSON.stringify({ multiDevice: 1 }));

    child = spawn(process.execPath, ['server.js'], {
      cwd: SERVER_DIR,
      env: Object.assign({}, process.env, {
        DATA_DIR: dataDir,
        PORT: String(port),
        TURN_PORT: String(turnPort),
        ADMIN_PASSWORD: 'legacy-aml-test-admin',
        CHRIS_LOCAL_ONLY: '1'
      }),
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true
    });
    child.stdout.on('data', (chunk) => logs.push(chunk.toString()));
    child.stderr.on('data', (chunk) => logs.push(chunk.toString()));
    for (let i = 0; i < 160; i += 1) {
      if (child.exitCode !== null) throw new Error('测试服务提前退出：\n' + logs.join(''));
      try {
        if ((await fetch(base + '/api/health')).ok) break;
      } catch (_) {
        // 启动中。
      }
      await new Promise((resolve) => setTimeout(resolve, 100));
    }

    const policy = JSON.parse(fs.readFileSync(path.join(dataDir, 'aml-legacy-policy.json'), 'utf8'));
    assert.ok(policy.cutoffAt);
    let users = readUsers(dataDir);
    const oldUser = users.find((user) => user.id === 'legacy_user_1');
    assert.strictEqual(oldUser.amlExempt, true);
    assert.strictEqual(oldUser.amlExemptReason, 'legacy-before-aml-rollout');

    const phone = '13800000777';
    let response = await call(base, 'POST', '/api/login/phone-code', { phone, register: true });
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const code = String(response.data.devCode || '');
    response = await call(base, 'POST', '/api/login/phone', { phone, code, register: true });
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const newId = response.data.user.id;
    assert.ok(newId);

    users = readUsers(dataDir);
    const newUser = users.find((user) => user.id === newId);
    assert.ok(newUser);
    assert.notStrictEqual(newUser.amlExempt, true);

    console.log('legacy-aml-exemption: passed');
  } finally {
    if (child && child.exitCode === null) child.kill();
    await new Promise((resolve) => setTimeout(resolve, 180));
    fs.rmSync(dataDir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
