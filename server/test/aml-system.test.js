'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const SERVER_DIR = path.resolve(__dirname, '..');
const LOGIN_PASSWORD = 'AmlTest1027!';
const PAY_PASSWORD = '123456';
const ADMIN_PASSWORD = 'aml-admin-test-password';
const SERVER_SECRET = 'aml-system-test-secret';
const ID_CARD = '11010519491231002X';

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

function scrypt(value, salt) {
  return crypto.scryptSync(value, salt, 64).toString('hex');
}

function makeUser(id, username, nickname, options) {
  const salt = crypto.randomBytes(16).toString('hex');
  const paySalt = crypto.randomBytes(16).toString('hex');
  return Object.assign({
    id,
    username,
    nickname,
    avatar: '',
    bio: '',
    phone: '',
    gender: 'secret',
    balance: 0,
    transferLimit: 20000,
    salt,
    passwordHash: scrypt(LOGIN_PASSWORD, salt),
    paySalt,
    payPasswordHash: scrypt(PAY_PASSWORD, paySalt),
    createdAt: new Date(Date.now() - 30 * 86400000).toISOString(),
    tokenVersion: 0,
    phoneSession: 0
  }, options || {});
}

async function waitForHealth(base, child, logs) {
  for (let i = 0; i < 160; i += 1) {
    if (child.exitCode !== null) throw new Error('测试服务提前退出：\n' + logs.join(''));
    try {
      if ((await fetch(base + '/api/health')).ok) return;
    } catch (_) {
      // 启动中。
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('测试服务启动超时：\n' + logs.join(''));
}

async function call(base, method, endpoint, body, cookie) {
  const headers = { 'x-device-kind': 'desktop' };
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
    envelope,
    headers: response.headers
  };
}

function cookieOf(response) {
  const raw = response.headers.getSetCookie
    ? response.headers.getSetCookie()[0]
    : response.headers.get('set-cookie') || '';
  return raw.split(';')[0];
}

async function login(base, username) {
  const response = await call(base, 'POST', '/api/login', {
    username,
    password: LOGIN_PASSWORD
  });
  assert.strictEqual(response.status, 200, JSON.stringify(response.data));
  const cookie = cookieOf(response);
  assert.ok(cookie);
  return cookie;
}

async function adminLogin(base) {
  const response = await call(base, 'POST', '/api/ops/login', {
    username: 'admin',
    password: ADMIN_PASSWORD
  });
  assert.strictEqual(response.status, 200, JSON.stringify(response.data));
  const cookie = cookieOf(response);
  assert.ok(cookie);
  return cookie;
}

async function currentBalance(base, cookie) {
  const response = await call(base, 'GET', '/api/me', undefined, cookie);
  assert.strictEqual(response.status, 200, JSON.stringify(response.data));
  return Number(response.data.user.balance) || 0;
}

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'chris-aml-system-'));
  const port = await freePort();
  const turnPort = await freePort();
  const base = 'http://127.0.0.1:' + port;
  const logs = [];
  let child;

  try {
    const idCardHash = crypto.createHmac('sha256', SERVER_SECRET)
      .update('idcard:' + ID_CARD).digest('hex');
    const users = [
      makeUser('u_aml_payer', 'li_lei', '李雷', {
        realName: 'Li Lei',
        realNameVerified: true,
        idCardHash,
        idCardMask: '110105********002X',
        idCardVerifiedAt: new Date().toISOString(),
        bankCards: [{ id: 'bank_aml', bank: '测试银行', tail: '0001', holder: 'Li Lei', isDefault: true }],
        walletUpgradedAt: new Date().toISOString(),
        balance: 10000,
        transferLimit: 20000
      }),
      makeUser('u_aml_recipient', 'recipient', '收款人', {
        realName: 'Wang Fang',
        realNameVerified: true,
        idCardHash: crypto.createHmac('sha256', SERVER_SECRET)
          .update('idcard:110105194912310011').digest('hex'),
        balance: 0
      })
    ];
    fs.writeFileSync(path.join(dataDir, 'secret.key'), SERVER_SECRET);
    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({ users }, null, 2));
    fs.writeFileSync(path.join(dataDir, 'friendships.json'), JSON.stringify({
      friendships: [{
        id: 'f_aml',
        fromId: 'u_aml_payer',
        toId: 'u_aml_recipient',
        status: 'accepted',
        createdAt: users[0].createdAt,
        respondedAt: users[0].createdAt
      }]
    }, null, 2));
    fs.writeFileSync(path.join(dataDir, 'chats.json'), JSON.stringify({
      chats: [{
        id: 'c_aml',
        type: 'direct',
        name: '',
        avatar: '',
        memberIds: ['u_aml_payer', 'u_aml_recipient'],
        ownerId: 'u_aml_payer',
        seq: 0,
        createdAt: users[0].createdAt
      }]
    }, null, 2));
    fs.writeFileSync(path.join(dataDir, 'security.json'),
      JSON.stringify({ sliderLogin: 0, allowRecharge: 0 }, null, 2));
    fs.writeFileSync(path.join(dataDir, 'ui.json'), JSON.stringify({ multiDevice: 1 }, null, 2));

    child = spawn(process.execPath, ['server.js'], {
      cwd: SERVER_DIR,
      env: Object.assign({}, process.env, {
        DATA_DIR: dataDir,
        PORT: String(port),
        TURN_PORT: String(turnPort),
        ADMIN_PASSWORD,
        CHRIS_LOCAL_ONLY: '1'
      }),
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true
    });
    child.stdout.on('data', (chunk) => logs.push(chunk.toString()));
    child.stderr.on('data', (chunk) => logs.push(chunk.toString()));
    await waitForHealth(base, child, logs);

    const payerCookie = await login(base, 'li_lei');
    const adminCookie = await adminLogin(base);

    let balance = await currentBalance(base, payerCookie);
    assert.strictEqual(balance, 10000);

    let response = await call(base, 'POST', '/api/pay/transfer', {
      chatId: 'c_aml',
      amount: 100,
      password: PAY_PASSWORD,
      requestId: 'aml_req_allowed_1',
      note: 'AML 系统测试-正常'
    }, payerCookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    balance = await currentBalance(base, payerCookie);
    assert.strictEqual(balance, 9900, 'allowed transfer must debit exactly once');
    response = await call(base, 'GET', '/api/chats', undefined, payerCookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const chatRow = (response.data.chats || []).find((x) => x.id === 'c_aml');
    assert.ok(chatRow && chatRow.lastMessage, 'transfer must create a conversation preview');
    assert.strictEqual(chatRow.lastMessage.preview, '[转账] ¥100.00',
      'conversation preview must include the transfer amount');

    response = await call(base, 'POST', '/api/ops/aml/rules', {
      confirmPassword: ADMIN_PASSWORD,
      rules: { pairReviewCount: 99 }
    }, adminCookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));

    response = await call(base, 'POST', '/api/pay/redpacket', {
      chatId: 'c_aml',
      amount: 50,
      count: 1,
      password: PAY_PASSWORD,
      requestId: 'aml_req_redpacket_1',
      note: 'AML 系统测试红包'
    }, payerCookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    response = await call(base, 'GET', '/api/chats', undefined, payerCookie);
    const redPacketChat = (response.data.chats || []).find((x) => x.id === 'c_aml');
    assert.strictEqual(redPacketChat.lastMessage.preview, '[红包] ¥50.00',
      'conversation preview must include the red packet amount');

    response = await call(base, 'POST', '/api/ops/aml/lists/import', {
      confirmPassword: ADMIN_PASSWORD,
      source: 'AML 系统测试制裁名单',
      text: 'type,name,aliases,idHashes,country,dob,source,sourceRef\n'
        + 'sanctions,Li Lei,Li L.|LL,' + idCardHash + ',,,AML-TEST,S-001'
    }, adminCookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(Number(response.data.added), 1);

    response = await call(base, 'POST', '/api/ops/aml/screening/run', {
      userId: 'u_aml_payer'
    }, adminCookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.ok(response.data.screening.matches.length >= 1);

    balance = await currentBalance(base, payerCookie);
    response = await call(base, 'POST', '/api/pay/transfer', {
      chatId: 'c_aml',
      amount: 100,
      password: PAY_PASSWORD,
      requestId: 'aml_req_blocked_1',
      note: 'AML 系统测试-制裁拦截'
    }, payerCookie);
    assert.strictEqual(response.status, 403, JSON.stringify(response.data));
    assert.strictEqual(response.data.details.amlBlocked, true);
    assert.ok(response.data.details.caseId);
    assert.strictEqual(await currentBalance(base, payerCookie), balance,
      'blocked transfer must not debit the wallet');

    const caseId = response.data.details.caseId;
    response = await call(base, 'GET', '/api/ops/aml/cases/' + caseId, undefined, adminCookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(response.data.case.decision, 'block');
    assert.strictEqual(response.data.profile.sanctioned, true);
    assert.strictEqual(response.data.profile.restricted.moneyOut, true);

    response = await call(base, 'POST', '/api/ops/aml/cases/' + caseId + '/review', {
      action: 'release',
      note: '错误地尝试绕过有效制裁名单',
      confirmPassword: ADMIN_PASSWORD
    }, adminCookie);
    assert.strictEqual(response.status, 409, 'active sanctions must not be released');
    assert.match(response.envelope.error || '', /制裁|黑名单/);

    const lists = await call(base, 'GET',
      '/api/ops/aml/lists?q=' + encodeURIComponent('Li Lei') + '&active=1', undefined, adminCookie);
    assert.strictEqual(lists.status, 200);
    const listId = lists.data.lists[0].id;
    response = await call(base, 'POST', '/api/ops/aml/lists/disable', {
      id: listId,
      reason: '测试名单版本撤销',
      confirmPassword: ADMIN_PASSWORD
    }, adminCookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));

    response = await call(base, 'POST', '/api/ops/aml/screening/run', {
      userId: 'u_aml_payer'
    }, adminCookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(response.data.screening.matches.length, 0);

    response = await call(base, 'POST', '/api/ops/aml/cases/' + caseId + '/review', {
      action: 'release',
      note: '名单版本撤销并重新筛查后解除限制',
      confirmPassword: ADMIN_PASSWORD
    }, adminCookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(response.data.case.status, 'closed');
    assert.strictEqual(response.data.profile.restricted.moneyOut, false);

    balance = await currentBalance(base, payerCookie);
    response = await call(base, 'POST', '/api/pay/transfer', {
      chatId: 'c_aml',
      amount: 100,
      password: PAY_PASSWORD,
      requestId: 'aml_req_allowed_2',
      note: 'AML 系统测试-解除后'
    }, payerCookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(await currentBalance(base, payerCookie), balance - 100);

    balance = await currentBalance(base, payerCookie);
    response = await call(base, 'POST', '/api/pay/transfer', {
      chatId: 'c_aml',
      amount: 5000,
      password: PAY_PASSWORD,
      requestId: 'aml_req_review_1',
      note: 'AML 系统测试-大额人工审核'
    }, payerCookie);
    assert.strictEqual(response.status, 403, JSON.stringify(response.data));
    assert.strictEqual(response.data.details && response.data.details.needAmlReview, true,
      JSON.stringify(response.envelope));
    assert.ok(response.data.details.caseId);
    assert.strictEqual(await currentBalance(base, payerCookie), balance,
      'manual-review transfer must not debit before approval');

    response = await call(base, 'GET', '/api/ops/aml/integrity', undefined, adminCookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(response.data.ok, true,
      'AML evidence chain must pass after the full flow');
    assert.ok(response.data.checked >= 8);

    response = await call(base, 'GET', '/api/bills/ledger?limit=50', undefined, payerCookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(response.data.verified, true,
      'wallet and double-entry ledger must reconcile after allowed/blocked flows');

    response = await call(base, 'GET', '/api/ops/aml', undefined, adminCookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.ok(Number(response.data.stats.openCases) >= 1);
    assert.ok(Number(response.data.stats.activeListEntries) >= 0);
    assert.strictEqual(typeof response.data.dualReview, 'boolean');

    console.log('aml-system: passed');
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
