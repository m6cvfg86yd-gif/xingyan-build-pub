'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const SERVER_DIR = path.resolve(__dirname, '..');
const PASSWORD = 'UploadIntegrity1027!';

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
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'chris-upload-integrity-'));
  const port = await freePort();
  const httpsPort = await freePort();
  const turnPort = await freePort();
  const base = 'http://127.0.0.1:' + port;
  const salt = crypto.randomBytes(16).toString('hex');
  const logs = [];
  let child;

  try {
    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({
      users: [{
        id: 'u_upload_integrity',
        username: 'upload_integrity',
        nickname: 'Upload integrity',
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
      }]
    }));
    fs.writeFileSync(path.join(dataDir, 'security.json'), JSON.stringify({ sliderLogin: 0 }));
    fs.writeFileSync(path.join(dataDir, 'ui.json'), JSON.stringify({ multiDevice: 1 }));

    child = spawn(process.execPath, ['server.js'], {
      cwd: SERVER_DIR,
      env: Object.assign({}, process.env, {
        DATA_DIR: dataDir,
        PORT: String(port),
        HTTPS_PORT: String(httpsPort),
        TURN_PORT: String(turnPort),
        ADMIN_PASSWORD: 'test-admin-password',
        CHRIS_LOCAL_ONLY: '1',
        SHARD_COUNT: '1'
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
      body: JSON.stringify({ username: 'upload_integrity', password: PASSWORD })
    });
    assert.equal(login.status, 200, await login.text());
    const rawCookie = login.headers.getSetCookie
      ? login.headers.getSetCookie()[0]
      : login.headers.get('set-cookie') || '';
    const cookie = rawCookie.split(';')[0];

    const payload = crypto.randomBytes(256 * 1024);
    const upload = await fetch(base + '/api/upload/raw', {
      method: 'POST',
      headers: {
        Cookie: cookie,
        'Content-Type': 'application/octet-stream',
        'x-chris-compressed': '1'
      },
      body: payload
    });
    const uploaded = await upload.json();
    assert.equal(upload.status, 200, JSON.stringify(uploaded));
    const url = uploaded.data && uploaded.data.url;
    assert.ok(url && url.startsWith('/uploads/'), JSON.stringify(uploaded));
    assert.equal(uploaded.data.bytes, payload.length);

    const download = await fetch(base + url, { headers: { Cookie: cookie } });
    assert.equal(download.status, 200);
    const downloaded = Buffer.from(await download.arrayBuffer());
    assert.equal(downloaded.length, payload.length);
    assert.ok(downloaded.equals(payload), '上传后下载内容不一致');

    const empty = await fetch(base + '/api/upload/raw', {
      method: 'POST',
      headers: { Cookie: cookie, 'Content-Type': 'application/octet-stream' },
      body: Buffer.alloc(0)
    });
    assert.equal(empty.status, 422, await empty.text());
    console.log('upload-raw-integrity: passed');
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
