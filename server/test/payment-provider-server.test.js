'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const http = require('http');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const SERVER_DIR = path.resolve(__dirname, '..');
const PASSWORD = 'ProviderTest123!';
const PAY_PASSWORD = '123456';
const API_KEY = 'provider-api-key-test';
const WEBHOOK_SECRET = 'provider-webhook-secret-test';

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

function makeUser(id, username, balance) {
  const salt = crypto.randomBytes(16).toString('hex');
  const paySalt = crypto.randomBytes(16).toString('hex');
  return {
    id,
    username,
    nickname: username,
    avatar: '',
    bio: '',
    phone: '',
    gender: 'secret',
    balance,
    salt,
    passwordHash: crypto.scryptSync(PASSWORD, salt, 64).toString('hex'),
    paySalt,
    payPasswordHash: crypto.scryptSync(PAY_PASSWORD, paySalt, 64).toString('hex'),
    realName: username,
    realNameVerified: true,
    idCardHash: crypto.createHash('sha256').update('provider:' + id).digest('hex'),
    idCardMask: '110105********0000',
    createdAt: new Date(Date.now() - 86400000).toISOString(),
    tokenVersion: 0,
    phoneSession: 0,
    banks: [{
      id: 'bank-test',
      bank: '测试银行',
      tail: '4242',
      holder: username,
      isDefault: true
    }]
  };
}

async function call(base, method, endpoint, body, cookie) {
  const headers = {
    'x-device-kind': 'phone',
    'x-device-id': 'provider-test-device'
  };
  if (cookie) headers.Cookie = cookie;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const response = await fetch(base + endpoint, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const text = await response.text();
  let envelope = {};
  try { envelope = text ? JSON.parse(text) : {}; }
  catch (_) { envelope = { raw: text }; }
  return {
    status: response.status,
    data: envelope.data === undefined ? envelope : envelope.data,
    headers: response.headers
  };
}

async function login(base, username) {
  const response = await call(base, 'POST', '/api/login', { username, password: PASSWORD });
  assert.strictEqual(response.status, 200, JSON.stringify(response.data));
  const raw = response.headers.getSetCookie
    ? response.headers.getSetCookie()[0]
    : response.headers.get('set-cookie') || '';
  return raw.split(';')[0];
}

function signedWebhook(base, payload, secret = WEBHOOK_SECRET) {
  const body = JSON.stringify(payload);
  const timestamp = String(Date.now());
  const signature = crypto.createHmac('sha256', secret)
    .update(timestamp + '\n' + body)
    .digest('base64url');
  return fetch(base + '/api/payment/provider/webhook', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-xingyan-timestamp': timestamp,
      'x-xingyan-signature': signature
    },
    body
  });
}

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-provider-server-'));
  const port = await freePort();
  const turnPort = await freePort();
  const providerPort = await freePort();
  const base = 'http://127.0.0.1:' + port;
  const providerBase = 'http://127.0.0.1:' + providerPort;
  const logs = [];
  const providerCalls = [];
  let child;
  const provider = http.createServer((req, res) => {
    const chunks = [];
    req.on('data', (chunk) => chunks.push(chunk));
    req.on('end', () => {
      const raw = Buffer.concat(chunks).toString('utf8');
      providerCalls.push({ url: req.url, raw });
      const input = JSON.parse(raw || '{}');
      const data = req.url === '/v1/deposits'
        ? {
          providerRef: 'deposit-' + input.orderId,
          checkoutUrl: 'https://provider.invalid/checkout/' + input.orderId
        }
        : {
          providerRef: 'payout-' + input.orderId,
          accepted: true
        };
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ ok: true, data }));
    });
  });
  await new Promise((resolve) => provider.listen(providerPort, '127.0.0.1', resolve));

  try {
    const user = makeUser('provider_user', 'provider_user', 100);
    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({ users: [user] }));
    fs.writeFileSync(path.join(dataDir, 'security.json'), JSON.stringify({
      sliderLogin: 0,
      allowRecharge: 1
    }));
    fs.writeFileSync(path.join(dataDir, 'wallet-rules.json'), JSON.stringify({
      allowRecharge: 1,
      feeRate: 0.001,
      feeMin: 0.1,
      withdrawMin: 1,
      withdrawMax: 50000
    }));
    fs.writeFileSync(path.join(dataDir, 'ui.json'), JSON.stringify({ multiDevice: 1 }));

    child = spawn(process.execPath, ['server.js'], {
      cwd: SERVER_DIR,
      env: Object.assign({}, process.env, {
        DATA_DIR: dataDir,
        PORT: String(port),
        TURN_PORT: String(turnPort),
        CHRIS_LOCAL_ONLY: '1',
        AML_RUNTIME_ENABLED: '0',
        PAYMENT_REAL_MONEY_MODE: 'enforce',
        PAYMENT_DATABASE_MODE: 'sqlite',
        PAYMENT_KEY_ID: 'provider-intent-key',
        PAYMENT_KEY_BASE64: crypto.randomBytes(32).toString('base64'),
        PAYMENT_PROVIDER_NAME: 'licensed-mock',
        PAYMENT_PROVIDER_BASE_URL: providerBase,
        PAYMENT_PROVIDER_API_KEY: API_KEY,
        PAYMENT_PROVIDER_WEBHOOK_SECRET: WEBHOOK_SECRET,
        ADMIN_PASSWORD: 'provider-admin'
      }),
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true
    });
    child.stdout.on('data', (chunk) => logs.push(chunk.toString()));
    child.stderr.on('data', (chunk) => logs.push(chunk.toString()));
    for (let index = 0; index < 200; index += 1) {
      if (child.exitCode !== null) throw new Error('测试服务提前退出：\n' + logs.join(''));
      try {
        if ((await fetch(base + '/api/health')).ok) break;
      } catch (_) { /* starting */ }
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    const cookie = await login(base, user.username);

    let response = await call(base, 'GET', '/api/payment/status', undefined, cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(response.data.realMoneyReady, true);
    assert.strictEqual(response.data.providerReady, true);
    assert.strictEqual(response.data.amlEnforcement, false);

    response = await call(base, 'POST', '/api/wallet/recharge', {
      amount: 25,
      bankId: 'bank-test',
      password: PAY_PASSWORD,
      requestId: 'provider-deposit-request'
    }, cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(response.data.pending, true);
    assert.strictEqual(response.data.balance, 100, 'deposit must not credit before webhook');
    assert.ok(response.data.checkoutUrl.indexOf('provider.invalid') > 0);
    const depositOrder = response.data.order;
    assert.strictEqual(depositOrder.status, 'pending');
    assert.ok(providerCalls.some((row) => row.url === '/v1/deposits'));

    const rejectedWebhook = await signedWebhook(base, {
      id: 'provider-deposit-bad-signature',
      type: 'deposit.succeeded',
      data: {
        kind: 'deposit',
        orderId: depositOrder.id,
        status: 'succeeded',
        providerRef: 'provider-deposit-ref'
      }
    }, 'wrong-webhook-secret');
    assert.strictEqual(rejectedWebhook.status, 401);
    response = await call(base, 'GET', '/api/me', undefined, cookie);
    assert.strictEqual(Number(response.data.user.balance), 100);

    let webhook = await signedWebhook(base, {
      id: 'provider-deposit-event',
      type: 'deposit.succeeded',
      data: {
        kind: 'deposit',
        orderId: depositOrder.id,
        status: 'succeeded',
        providerRef: 'provider-deposit-ref'
      }
    });
    assert.strictEqual(webhook.status, 200, await webhook.text());

    response = await call(base, 'GET', '/api/me', undefined, cookie);
    assert.strictEqual(Number(response.data.user.balance), 125);
    response = await call(base, 'POST', '/api/wallet/withdraw', {
      amount: 10,
      bankId: 'bank-test',
      password: PAY_PASSWORD,
      requestId: 'provider-payout-request'
    }, cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(response.data.pending, true);
    assert.strictEqual(Number(response.data.balance), 114.9);
    const payoutOrder = response.data.order;
    assert.ok(providerCalls.some((row) => row.url === '/v1/payouts'));

    webhook = await signedWebhook(base, {
      id: 'provider-payout-event',
      type: 'payout.succeeded',
      data: {
        kind: 'payout',
        orderId: payoutOrder.id,
        status: 'succeeded',
        providerRef: 'provider-payout-ref'
      }
    });
    assert.strictEqual(webhook.status, 200, await webhook.text());
    response = await call(base, 'GET', '/api/payment/funding/' + payoutOrder.id, undefined, cookie);
    assert.strictEqual(response.data.order.status, 'succeeded');
    response = await call(base, 'GET', '/api/bills/ledger?limit=200', undefined, cookie);
    assert.strictEqual(response.data.verified, true);
    assert.strictEqual(Number(response.data.balance), 114.9);

    webhook = await signedWebhook(base, {
      id: 'provider-payout-event',
      type: 'payout.succeeded',
      data: {
        kind: 'payout',
        orderId: payoutOrder.id,
        status: 'succeeded',
        providerRef: 'provider-payout-ref'
      }
    });
    assert.strictEqual(webhook.status, 200);
    response = await call(base, 'GET', '/api/me', undefined, cookie);
    assert.strictEqual(Number(response.data.user.balance), 114.9,
      'duplicate provider webhook must not move money twice');

    response = await call(base, 'POST', '/api/wallet/withdraw', {
      amount: 5,
      bankId: 'bank-test',
      password: PAY_PASSWORD,
      requestId: 'provider-payout-failure-request'
    }, cookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const failedPayout = response.data.order;
    assert.strictEqual(Number(response.data.balance), 109.8);
    webhook = await signedWebhook(base, {
      id: 'provider-payout-failure-event',
      type: 'payout.failed',
      data: {
        kind: 'payout',
        orderId: failedPayout.id,
        status: 'failed',
        providerRef: 'provider-payout-failed-ref',
        failureCode: 'bank_rejected'
      }
    });
    assert.strictEqual(webhook.status, 200, await webhook.text());
    response = await call(base, 'GET', '/api/payment/funding/' + failedPayout.id, undefined, cookie);
    assert.strictEqual(response.data.order.status, 'failed');
    response = await call(base, 'GET', '/api/me', undefined, cookie);
    assert.strictEqual(Number(response.data.user.balance), 114.9,
      'failed payout must return both principal and fee');

    console.log('payment-provider-server: passed');
  } finally {
    if (child && child.exitCode === null) child.kill();
    await new Promise((resolve) => provider.close(resolve));
    await new Promise((resolve) => setTimeout(resolve, 200));
    if (process.platform !== 'win32') {
      fs.rmSync(dataDir, { recursive: true, force: true });
    }
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
