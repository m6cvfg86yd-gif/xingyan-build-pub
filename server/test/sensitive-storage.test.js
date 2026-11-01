'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const SERVER_DIR = path.resolve(__dirname, '..');
const PASSWORD = 'StorageTest1027!';

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

function secureFile(name) {
  const parsed = JSON.parse(fs.readFileSync(name, 'utf8'));
  assert.equal(parsed.enc, 1, name + ' 仍是明文');
  return parsed;
}

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'chris-sensitive-store-'));
  const port = await freePort();
  const turnPort = await freePort();
  const base = 'http://127.0.0.1:' + port;
  const logs = [];
  let child;
  const salt = crypto.randomBytes(16).toString('hex');
  const cardNumber = '6222021234567890123';
  const holder = '银行卡持有人测试';
  const transferNote = '测试转账明文备注';
  const redpacketName = '测试红包发送人';
  const withdrawBank = '测试提现银行卡';
  const invoiceTaxNo = 'TEST-TAX-20261101';
  const invoiceBankAccount = '6228480000000000001';
  const orderAddress = '测试省测试市隐私地址 88 号';
  const ledgerNote = '测试记账午餐';

  try {
    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({
      users: [{
        id: 'u_storage', username: 'storage_user', nickname: '存储测试',
        phone: '13800000123', realName: '存储测试', gender: 'secret',
        balance: 100, transferLimit: 20000, salt,
        passwordHash: crypto.scryptSync(PASSWORD, salt, 64).toString('hex'),
        bankCards: [{
          id: 'bc_storage', bank: '工商银行', number: cardNumber, tail: '0123',
          holder, type: '储蓄卡', idCardTail: '1234', phoneMask: '138****0123',
          noPin: false, single: 5000, day: 5000, addedAt: new Date().toISOString()
        }],
        createdAt: new Date().toISOString(), tokenVersion: 0, phoneSession: 0
      }]
    }, null, 2));
    fs.writeFileSync(path.join(dataDir, 'security.json'), JSON.stringify({ sliderLogin: 0 }));
    fs.writeFileSync(path.join(dataDir, 'ui.json'), JSON.stringify({ multiDevice: 1 }));
    fs.writeFileSync(path.join(dataDir, 'transfers.json'), JSON.stringify({
      transfers: [{ id: 'tr_storage', fromId: 'u_storage', toId: 'u_other', amount: 12.34, note: transferNote }]
    }));
    fs.writeFileSync(path.join(dataDir, 'redpackets.json'), JSON.stringify({
      redpackets: [{ id: 'rp_storage', fromId: 'u_storage', fromName: redpacketName, total: 8.88, claims: [] }]
    }));
    fs.writeFileSync(path.join(dataDir, 'wallet-ops.json'), JSON.stringify({
      ops: [{ id: 'wop_storage', userId: 'u_storage', kind: 'withdraw', bankText: withdrawBank, amount: 5 }]
    }));
    fs.writeFileSync(path.join(dataDir, 'ledger.json'), JSON.stringify({
      items: [{ id: 'gd_storage', userId: 'u_storage', what: ledgerNote, amount: 23 }]
    }));
    fs.writeFileSync(path.join(dataDir, 'money-state.json'), JSON.stringify({
      users: { u_storage: { balance: 100, at: new Date().toISOString() } }
    }));
    fs.writeFileSync(path.join(dataDir, 'biz.json'), JSON.stringify({
      accounts: { u_storage: {
        balance: 66.6,
        records: [{ id: 'bz_storage', userId: 'u_storage', amount: 6.6 }],
        invoice: { title: '测试公司', taxNo: invoiceTaxNo, address: '测试地址', phone: '13800000123',
          bankName: '工商银行', bankAccount: invoiceBankAccount },
        invoices: []
      } }
    }));
    fs.writeFileSync(path.join(dataDir, 'orders.json'), JSON.stringify({
      items: [{ id: 'od_storage', userId: 'u_storage', name: '测试商品', address: orderAddress, price: 9.9 }]
    }));
    fs.writeFileSync(path.join(dataDir, 'money-journal.jsonl'), JSON.stringify({
      at: new Date().toISOString(), userId: 'u_storage', delta: 1, before: 99, after: 100,
      reason: '存储迁移测试'
    }) + '\n');

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
    for (let i = 0; i < 180; i++) {
      if (child.exitCode !== null) throw new Error('测试服务提前退出：\n' + logs.join(''));
      try {
        if ((await fetch(base + '/api/health')).ok) break;
      } catch (_) {
        // 等待服务启动和迁移完成。
      }
      await new Promise((resolve) => setTimeout(resolve, 100));
    }

    for (const name of ['transfers.json', 'redpackets.json', 'wallet-ops.json',
      'ledger.json', 'money-state.json', 'biz.json', 'orders.json']) {
      secureFile(path.join(dataDir, name));
    }
    const usersDisk = JSON.parse(fs.readFileSync(path.join(dataDir, 'users.json'), 'utf8'));
    const storedCard = usersDisk.users[0].bankCards[0];
    assert.ok(String(storedCard.number).startsWith('enc1:'));
    assert.ok(String(storedCard.holder).startsWith('enc1:'));

    const allDisk = fs.readdirSync(dataDir)
      .filter((name) => fs.statSync(path.join(dataDir, name)).isFile())
      .map((name) => fs.readFileSync(path.join(dataDir, name), 'utf8'))
      .join('\n');
    for (const secret of [cardNumber, holder, transferNote, redpacketName, withdrawBank,
      invoiceTaxNo, invoiceBankAccount, orderAddress, ledgerNote]) {
      assert.ok(!allDisk.includes(secret), '敏感明文仍落盘：' + secret);
    }
    const journalLine = JSON.parse(fs.readFileSync(path.join(dataDir, 'money-journal.jsonl'), 'utf8')
      .trim().split('\n')[0]);
    assert.equal(journalLine.enc, 1);

    let response = await call(base, 'POST', '/api/login',
      { username: 'storage_user', password: PASSWORD });
    assert.equal(response.status, 200, JSON.stringify(response.data));
    const cookie = (response.headers.getSetCookie
      ? response.headers.getSetCookie()[0]
      : response.headers.get('set-cookie') || '').split(';')[0];
    response = await call(base, 'GET', '/api/me/bankcards', undefined, cookie);
    assert.equal(response.status, 200, JSON.stringify(response.data));
    assert.equal(response.data.cards[0].tail, '0123');
    assert.equal(response.data.cards[0].number, undefined);

    console.log('sensitive-storage: passed');
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
