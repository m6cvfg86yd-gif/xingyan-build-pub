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

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'chris-finance-support-'));
  const port = await freePort();
  const turnPort = await freePort();
  const base = 'http://127.0.0.1:' + port;
  const logs = [];
  let child;

  try {
    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({ users: [] }));
    fs.writeFileSync(path.join(dataDir, 'security.json'), JSON.stringify({ sliderLogin: 0 }));
    fs.writeFileSync(path.join(dataDir, 'ui.json'), JSON.stringify({ multiDevice: 1 }));

    child = spawn(process.execPath, ['server.js'], {
      cwd: SERVER_DIR,
      env: Object.assign({}, process.env, {
        DATA_DIR: dataDir,
        PORT: String(port),
        TURN_PORT: String(turnPort),
        ADMIN_PASSWORD: 'finance-support-test-admin',
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

    const phone = '13800000123';
    let response = await call(base, 'POST', '/api/login/phone-code', { phone, register: true });
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const code = String(response.data.devCode || '');
    response = await call(base, 'POST', '/api/login/phone', { phone, code, register: true });
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const rawCookie = response.headers.getSetCookie
      ? response.headers.getSetCookie()[0]
      : response.headers.get('set-cookie') || '';
    const cookie = rawCookie.split(';')[0];
    assert.ok(cookie);

    response = await call(base, 'GET', '/api/support/finance', undefined, cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(response.data.agent.nickname, '星言金融客服');
    assert.ok((response.data.categories || []).some((row) => row.id === 'deduction'));

    response = await call(base, 'POST', '/api/support/finance/human', {}, cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const chatId = response.data.chatId;
    assert.ok(chatId);

    response = await call(base, 'POST', '/api/chats/' + chatId + '/messages', {
      kind: 'text',
      content: '我转账 100 元一直没到账，交易单号 tr_finance_test01'
    }, cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));

    await new Promise((resolve) => setTimeout(resolve, 350));
    response = await call(base, 'GET', '/api/chats/' + chatId + '/messages?limit=30', undefined, cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const messages = response.data.messages || [];
    const reply = messages.find((row) => row.content && row.content.indexOf('ftk') >= 0);
    assert.ok(reply, 'financial issue must receive a professional agent reply: ' + JSON.stringify(messages));
    assert.match(reply.content, /ftk[A-Za-z0-9_-]+/);
    assert.match(reply.content, /人工/);
    assert.doesNotMatch(reply.content, /支付密码.*(发给我|告诉我)/);

    response = await call(base, 'GET', '/api/support/finance', undefined, cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const ticket = (response.data.tickets || []).find((row) => row.kind === 'finance');
    assert.ok(ticket, 'financial support case must be visible in the user case list');
    assert.strictEqual(ticket.priority, 'high');
    assert.strictEqual(ticket.humanRequested, true);
    assert.ok(ticket.dueAt);

    const encryptedLog = fs.readFileSync(path.join(dataDir, 'finance-support-events.jsonl'), 'utf8');
    assert.ok(encryptedLog.trim(), 'financial case evidence must be persisted');
    assert.ok(!encryptedLog.includes('一直没到账'), 'financial case content must not be stored in plaintext');

    response = await call(base, 'POST', '/api/support/finance/ticket', {
      category: '扣款与账单',
      content: '还有一笔扣款需要核对',
      reference: 'tr_finance_test01'
    }, cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.ok(response.data.ticket.id.startsWith('ftk'));

    console.log('finance-support: passed');
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
