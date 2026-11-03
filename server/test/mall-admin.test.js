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
const OPS_ID = 'u_2883edf4d038a117';
const OPS_USERNAME = 'wzy245441545';

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

function user(id, username, nickname) {
  const salt = crypto.randomBytes(16).toString('hex');
  return {
    id,
    username,
    nickname,
    avatar: '',
    bio: '',
    phone: '',
    gender: 'secret',
    balance: 1000,
    transferLimit: 20000,
    salt,
    passwordHash: crypto.scryptSync(PASSWORD, salt, 64).toString('hex'),
    createdAt: new Date().toISOString(),
    tokenVersion: 0,
    phoneSession: 0
  };
}

async function waitForHealth(base, child, logs) {
  for (let i = 0; i < 120; i++) {
    if (child.exitCode !== null) throw new Error('测试服务器提前退出：\n' + logs.join(''));
    try {
      const response = await fetch(base + '/api/health');
      if (response.ok) return;
    } catch (_) {}
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('测试服务器启动超时：\n' + logs.join(''));
}

async function call(base, cookie, method, url, body) {
  const headers = { 'x-device-kind': 'desktop' };
  if (cookie) headers.Cookie = cookie;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const response = await fetch(base + url, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const text = await response.text();
  let envelope = {};
  try { envelope = text ? JSON.parse(text) : {}; } catch (_) { envelope = { raw: text }; }
  const data = envelope && envelope.data !== undefined ? envelope.data : envelope;
  return { status: response.status, data, headers: response.headers };
}

async function login(base, username) {
  const response = await call(base, '', 'POST', '/api/login', { username, password: PASSWORD });
  assert.equal(response.status, 200, JSON.stringify(response.data));
  const cookie = (response.headers.getSetCookie
    ? response.headers.getSetCookie()[0]
    : response.headers.get('set-cookie') || '').split(';')[0];
  assert.ok(cookie, '登录响应缺少会话 Cookie');
  return { cookie, user: response.data.user };
}

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'chris-mall-admin-'));
  const port = await freePort();
  const turnPort = await freePort();
  const base = 'http://127.0.0.1:' + port;
  const logs = [];
  let child;
  try {
    fs.writeFileSync(path.join(dataDir, 'users.json'), JSON.stringify({
      users: [
        user(OPS_ID, OPS_USERNAME, 'Mall Admin'),
        user('u_buyer_smoke', 'buyer_smoke', '买家测试')
      ]
    }, null, 2));
    fs.writeFileSync(path.join(dataDir, 'security.json'), JSON.stringify({ sliderLogin: 0 }, null, 2));
    fs.writeFileSync(path.join(dataDir, 'ui.json'), JSON.stringify({ multiDevice: 1 }, null, 2));

    child = spawn(process.execPath, ['server.js'], {
      cwd: SERVER_DIR,
      env: Object.assign({}, process.env, {
        DATA_DIR: dataDir,
        PORT: String(port),
        TURN_PORT: String(turnPort),
        CHRIS_LOCAL_ONLY: '1'
      }),
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true
    });
    child.stdout.on('data', (chunk) => logs.push(chunk.toString()));
    child.stderr.on('data', (chunk) => logs.push(chunk.toString()));
    await waitForHealth(base, child, logs);

    const ops = await login(base, OPS_USERNAME);
    const buyer = await login(base, 'buyer_smoke');
    const webLogin = await call(base, '', 'POST', '/api/ops/login', {
      username: 'admin', password: 'chris888'
    });
    assert.equal(webLogin.status, 200, JSON.stringify(webLogin.data));
    const webCookie = (webLogin.headers.getSetCookie
      ? webLogin.headers.getSetCookie()[0]
      : webLogin.headers.get('set-cookie') || '').split(';')[0];
    assert.ok(webCookie, '网页后台登录缺少 Cookie');

    let response = await call(base, webCookie, 'GET', '/api/ops/malladmin');
    assert.equal(response.status, 200, JSON.stringify(response.data));

    response = await call(base, '', 'GET', '/api/mall');
    assert.equal(response.status, 200, JSON.stringify(response.data));
    assert.ok(response.data.products.length >= 16, '商城种子商品没有返回');
    const product = response.data.products[0];
    const productId = product.id;

    response = await call(base, ops.cookie, 'POST', '/api/ops/mall', {
      action: 'product',
      item: Object.assign({}, product, {
        stock: 15,
        cost: 12.5,
        supplier: '测试供应商',
        warehouse: '上海一仓',
        on: true
      })
    });
    assert.equal(response.status, 200, JSON.stringify(response.data));

    response = await call(base, ops.cookie, 'POST', '/api/ops/mall', {
      action: 'categories', categories: ['数码', '食品', '烟测分类']
    });
    assert.equal(response.status, 200, JSON.stringify(response.data));
    assert.ok(response.data.categories.includes('烟测分类'));

    response = await call(base, buyer.cookie, 'POST', '/api/mall/order', {
      id: 'mo_smoke_1',
      items: [{ pid: productId, title: product.title, price: product.price, count: 2 }],
      total: Number(product.price) * 2,
      payWay: '测试支付',
      address: '测试用户 13800000000 上海市测试路 1 号',
      at: new Date().toISOString(),
      paid: true,
      remark: '商城后台烟测'
    });
    assert.equal(response.status, 200, JSON.stringify(response.data));
    assert.equal(response.data.order.status, 'wait');

    response = await call(base, buyer.cookie, 'GET', '/api/mall/orders');
    assert.equal(response.status, 200, JSON.stringify(response.data));
    assert.equal(response.data.orders.length, 1);

    response = await call(base, ops.cookie, 'GET', '/api/ops/malladmin');
    assert.equal(response.status, 200, JSON.stringify(response.data));
    assert.equal(response.data.admin.orders.length, 1);
    const edited = response.data.mall.products.find((p) => p.id === productId);
    assert.equal(Number(edited.stock), 13, '付款订单没有扣减库存');
    assert.equal(edited.cost, 12.5);

    response = await call(base, ops.cookie, 'POST', '/api/ops/malladmin', {
      action: 'inventory.adjust', productId, stock: 30, reason: '烟测补货'
    });
    assert.equal(response.status, 200, JSON.stringify(response.data));
    assert.equal(response.data.after, 30);

    response = await call(base, ops.cookie, 'POST', '/api/ops/ship', {
      id: 'mo_smoke_1', company: '顺丰速运', no: 'SFTEST123'
    });
    assert.equal(response.status, 200, JSON.stringify(response.data));
    assert.equal(response.data.order.status, 'shipped');

    response = await call(base, buyer.cookie, 'GET',
      '/api/mall/logistics?id=mo_smoke_1');
    assert.equal(response.status, 200, JSON.stringify(response.data));
    assert.equal(response.data.express.no, 'SFTEST123');

    response = await call(base, buyer.cookie, 'POST', '/api/mall/aftersale', {
      id: 'mo_smoke_1', kind: 'refund', reason: '后台烟测退款'
    });
    assert.equal(response.status, 200, JSON.stringify(response.data));
    const afterId = response.data.afterSale.id;

    response = await call(base, ops.cookie, 'GET', '/api/ops/aftersales?only=pending');
    assert.equal(response.status, 200, JSON.stringify(response.data));
    assert.ok(response.data.orders.some((x) => x.id === afterId));

    response = await call(base, ops.cookie, 'POST', '/api/ops/aftersale/review', {
      id: afterId, pass: true, note: '烟测通过'
    });
    assert.equal(response.status, 200, JSON.stringify(response.data));
    assert.equal(response.data.afterSale.status, 'approved');

    response = await call(base, ops.cookie, 'POST', '/api/ops/malladmin', {
      action: 'coupon.save',
      item: { title: '烟测满减券', off: 10, min: 50, days: 7, total: 100 }
    });
    assert.equal(response.status, 200, JSON.stringify(response.data));
    const couponId = response.data.coupon.id;

    response = await call(base, ops.cookie, 'POST', '/api/ops/coupon/send', {
      to: buyer.user.id, couponId, title: '烟测满减券', off: 10, min: 50, days: 7, count: 2
    });
    assert.equal(response.status, 200, JSON.stringify(response.data));
    assert.equal(response.data.sent, 2);

    response = await call(base, buyer.cookie, 'POST', '/api/mall/ad', { do: 'mine' });
    assert.equal(response.status, 200, JSON.stringify(response.data));
    assert.equal(response.data.coupons.length, 2);

    for (const [action, item] of [
      ['campaign.save', { name: '烟测会场', description: '活动骨架' }],
      ['shop.save', { name: '烟测旗舰店', address: '杭州' }]
    ]) {
      response = await call(base, ops.cookie, 'POST', '/api/ops/malladmin', { action, item });
      assert.equal(response.status, 200, JSON.stringify(response.data));
    }

    response = await call(base, ops.cookie, 'POST', '/api/ops/malladmin', {
      action: 'settings.save',
      settings: { autoConfirmDays: 9, unpaidTimeoutMinutes: 20, stockPolicy: 'warn',
        servicePhone: '400-000-0000', serviceHours: '09:00-22:00', orderNote: '烟测' }
    });
    assert.equal(response.status, 200, JSON.stringify(response.data));
    assert.equal(response.data.settings.autoConfirmDays, 9);

    response = await call(base, ops.cookie, 'GET', '/api/ops/malladmin');
    assert.equal(response.status, 200, JSON.stringify(response.data));
    assert.ok(response.data.admin.auditLogs.length >= 6, '商城后台没有留下操作审计');
    assert.ok(fs.existsSync(path.join(dataDir, 'mall-admin.json')));

    response = await call(base, buyer.cookie, 'GET', '/api/ops/malladmin');
    assert.equal(response.status, 404, '普通用户不应拿到商城后台数据');

    console.log('mall-admin: passed');
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
