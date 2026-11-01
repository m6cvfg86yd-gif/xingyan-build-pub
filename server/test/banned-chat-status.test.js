'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const SERVER_DIR = path.resolve(__dirname, '..');
const PASSWORD = 'BannedChat1027!';

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

async function call(base, method, url, body, cookie = '') {
  const headers = { 'x-device-kind': 'phone' };
  if (cookie) headers.Cookie = cookie;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const response = await fetch(base + url, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const text = await response.text();
  const envelope = text ? JSON.parse(text) : {};
  return {
    status: response.status,
    data: envelope.data === undefined ? envelope : envelope.data,
    headers: response.headers
  };
}

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'chris-banned-chat-'));
  const port = await freePort();
  const turnPort = await freePort();
  const base = 'http://127.0.0.1:' + port;
  const logs = [];
  let child;
  const salt = crypto.randomBytes(16).toString('hex');
  const createdAt = new Date().toISOString();

  try {
    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({
      users: [
        {
          id: 'u_viewer',
          username: 'ban_viewer',
          nickname: '查看者',
          phone: '',
          realName: '',
          gender: 'secret',
          balance: 0,
          transferLimit: 20000,
          salt,
          passwordHash: crypto.scryptSync(PASSWORD, salt, 64).toString('hex'),
          createdAt,
          tokenVersion: 0,
          phoneSession: 0
        },
        {
          id: 'u_banned',
          username: 'ban_target',
          nickname: '封禁用户',
          phone: '',
          realName: '',
          gender: 'secret',
          balance: 0,
          transferLimit: 0,
          salt,
          passwordHash: crypto.scryptSync(PASSWORD, salt, 64).toString('hex'),
          banned: true,
          banReason: '发布违规内容',
          bannedAt: createdAt,
          createdAt,
          tokenVersion: 1,
          phoneSession: 0
        }
      ]
    }));
    fs.writeFileSync(path.join(dataDir, 'friendships.json'), JSON.stringify({
      friendships: [{
        id: 'f_ban_chat',
        fromId: 'u_viewer',
        toId: 'u_banned',
        status: 'accepted',
        createdAt,
        respondedAt: createdAt
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
        ADMIN_PASSWORD: 'test-admin-password',
        CHRIS_LOCAL_ONLY: '1'
      }),
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true
    });
    child.stdout.on('data', (chunk) => logs.push(chunk.toString()));
    child.stderr.on('data', (chunk) => logs.push(chunk.toString()));
    for (let i = 0; i < 160; i++) {
      if (child.exitCode !== null) throw new Error('测试服务提前退出：\n' + logs.join(''));
      try {
        if ((await fetch(base + '/api/health')).ok) break;
      } catch (_) {
        // 等待服务启动。
      }
      await new Promise((resolve) => setTimeout(resolve, 100));
    }

    let response = await call(base, 'POST', '/api/login',
      { username: 'ban_viewer', password: PASSWORD });
    assert.equal(response.status, 200, JSON.stringify(response.data));
    const rawCookie = response.headers.getSetCookie
      ? response.headers.getSetCookie()[0]
      : response.headers.get('set-cookie') || '';
    const cookie = rawCookie.split(';')[0];

    response = await call(base, 'GET', '/api/users/u_banned', undefined, cookie);
    assert.equal(response.status, 200, JSON.stringify(response.data));
    assert.equal(response.data.user.banned, true, '聊天对象封禁状态没有下发');
    assert.equal(response.data.user.banReason, '发布违规内容', '聊天对象封禁原因没有下发');

    console.log('banned-chat-status: passed');
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
