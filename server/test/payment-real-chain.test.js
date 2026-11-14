'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');
const { canonical } = require('../lib/shard-snapshot');

const SERVER_DIR = path.resolve(__dirname, '..');
const PASSWORD = 'RealChain123!';
const PAY_PASSWORD = '123456';

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

function makeUser(id, username, nickname, balance) {
  const salt = crypto.randomBytes(16).toString('hex');
  const paySalt = crypto.randomBytes(16).toString('hex');
  return {
    id,
    username,
    nickname,
    avatar: '',
    bio: '',
    phone: '',
    gender: 'secret',
    balance,
    salt,
    passwordHash: crypto.scryptSync(PASSWORD, salt, 64).toString('hex'),
    paySalt,
    payPasswordHash: crypto.scryptSync(PAY_PASSWORD, paySalt, 64).toString('hex'),
    realName: nickname,
    realNameVerified: true,
    idCardHash: crypto.createHash('sha256').update('real-chain:' + id).digest('hex'),
    idCardMask: '110105********' + id.slice(-4).padStart(4, '0'),
    createdAt: new Date(Date.now() - 86400000).toISOString(),
    tokenVersion: 0,
    phoneSession: 0
  };
}

async function call(base, method, endpoint, body, cookie) {
  const headers = { 'x-device-kind': 'phone', 'x-device-id': 'real-chain-device' };
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
    data: envelope.data === undefined ? envelope : envelope.data,
    headers: response.headers
  };
}

async function login(base, username) {
  const response = await call(base, 'POST', '/api/login', {
    username,
    password: PASSWORD
  });
  assert.strictEqual(response.status, 200, JSON.stringify(response.data));
  const raw = response.headers.getSetCookie
    ? response.headers.getSetCookie()[0]
    : response.headers.get('set-cookie') || '';
  return raw.split(';')[0];
}

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-real-chain-'));
  const port = await freePort();
  const turnPort = await freePort();
  const base = 'http://127.0.0.1:' + port;
  const logs = [];
  let child;
  try {
    const alice = makeUser('real_alice', 'real_alice', 'Alice', 100);
    const bob = makeUser('real_bob', 'real_bob', 'Bob', 0);
    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({
      users: [alice, bob]
    }));
    fs.writeFileSync(path.join(dataDir, 'friendships.json'), JSON.stringify({
      friendships: [{
        id: 'real-friendship',
        fromId: alice.id,
        toId: bob.id,
        status: 'accepted',
        createdAt: new Date().toISOString(),
        respondedAt: new Date().toISOString()
      }]
    }));
    fs.writeFileSync(path.join(dataDir, 'chats.json'), JSON.stringify({
      chats: [{
        id: 'real-chat',
        type: 'direct',
        name: '',
        avatar: '',
        memberIds: [alice.id, bob.id],
        ownerId: alice.id,
        seq: 0,
        createdAt: new Date().toISOString()
      }]
    }));
    fs.writeFileSync(path.join(dataDir, 'security.json'), JSON.stringify({
      sliderLogin: 0,
      allowRecharge: 0
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
        PAYMENT_KEY_ID: 'real-chain-key',
        PAYMENT_KEY_BASE64: crypto.randomBytes(32).toString('base64'),
        ADMIN_PASSWORD: 'real-chain-admin'
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
      } catch (_) { /* starting */ }
      await new Promise((resolve) => setTimeout(resolve, 100));
    }

    const aliceCookie = await login(base, alice.username);
    const bobCookie = await login(base, bob.username);
    const device = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
    const publicKey = device.publicKey.export({ format: 'pem', type: 'spki' })
      .toString().trim();

    let response = await call(base, 'POST', '/api/payment/devices/challenge', {
      deviceId: 'real-chain-device',
      publicKey
    }, aliceCookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const enrollment = response.data;
    const enrollmentPayload = {
      purpose: 'payment-device-enrollment',
      challenge: enrollment.challenge,
      tokenId: enrollment.tokenId,
      userId: alice.id,
      deviceId: 'real-chain-device',
      publicKey
    };
    const enrollmentSignature = crypto.sign(
      'sha256',
      Buffer.from(canonical(enrollmentPayload)),
      device.privateKey
    ).toString('base64');
    response = await call(base, 'POST', '/api/payment/devices/enroll', {
      challenge: enrollment.challenge,
      signature: enrollmentSignature,
      last4: '4242'
    }, aliceCookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const tokenId = response.data.tokenId;

    response = await call(base, 'POST', '/api/payment/intents', {
      requestId: 'real-chain-intent-request',
      chatId: 'real-chat',
      amount: 1,
      amountCents: 100,
      deviceId: 'real-chain-device',
      note: 'real chain'
    }, aliceCookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const intentId = response.data.intent.id;
    assert.strictEqual(response.data.intent.status, 'created');

    response = await call(base, 'POST',
      '/api/payment/intents/' + intentId + '/challenge',
      { tokenId }, aliceCookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const challenge = response.data;
    const paymentSignature = crypto.sign(
      'sha256',
      Buffer.from(canonical(challenge.payload)),
      device.privateKey
    ).toString('base64');
    response = await call(base, 'POST',
      '/api/payment/intents/' + intentId + '/authorize',
      { tokenId, signature: paymentSignature }, aliceCookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(response.data.intent.status, 'authorized');

    response = await call(base, 'POST', '/api/pay/transfer', {
      paymentIntentId: intentId,
      chatId: 'real-chat',
      amount: 1,
      method: 'balance'
    }, aliceCookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(response.data.paymentIntent.status, 'captured');
    assert.strictEqual(response.data.balance, 99);
    const transferId = response.data.transfer.id;

    response = await call(base, 'GET', '/api/me', undefined, aliceCookie);
    assert.strictEqual(Number(response.data.user.balance), 99);
    response = await call(base, 'POST', '/api/pay/transfer', {
      paymentIntentId: intentId,
      chatId: 'real-chat',
      amount: 1,
      method: 'balance'
    }, aliceCookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(response.data.transfer.id, transferId);
    response = await call(base, 'GET', '/api/me', undefined, aliceCookie);
    assert.strictEqual(Number(response.data.user.balance), 99,
      'duplicate capture must not debit twice');

    response = await call(base, 'POST', '/api/transfers/' + transferId + '/claim', {}, bobCookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    response = await call(base, 'GET', '/api/me', undefined, bobCookie);
    assert.strictEqual(Number(response.data.user.balance), 1);

    response = await call(base, 'POST', '/api/pay/code', {}, bobCookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    const paymentCode = response.data.code;
    response = await call(base, 'POST', '/api/pay/collect', {
      text: paymentCode,
      amount: 2,
      password: PAY_PASSWORD,
      requestId: 'secure-paycode-request'
    }, aliceCookie);
    assert.strictEqual(response.status, 200, JSON.stringify(response.data));
    assert.strictEqual(Number(response.data.balance), 97);
    response = await call(base, 'GET', '/api/me', undefined, bobCookie);
    assert.strictEqual(Number(response.data.user.balance), 3);

    response = await call(base, 'GET', '/api/bills/ledger?limit=100', undefined, aliceCookie);
    assert.strictEqual(response.data.verified, true);
    const captureEntries = (response.data.entries || []).filter(
      (row) => row.ref === 'payment-intent:' + intentId
    );
    assert.strictEqual(captureEntries.length, 1);
    assert.strictEqual(Number(captureEntries[0].delta), -1);

    response = await call(base, 'POST', '/api/pay/transfer', {
      chatId: 'real-chat',
      amount: 1,
      password: PAY_PASSWORD,
      requestId: 'legacy-without-intent'
    }, aliceCookie);
    assert.strictEqual(response.status, 404,
      'enforce mode must reject the legacy unsigned path');

    console.log('payment-real-chain: passed');
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
