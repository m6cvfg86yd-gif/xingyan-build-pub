(function () {
  'use strict';

  const $ = (id) => document.getElementById(id);
  const VIEWS = {
    dashboard: ['经营总览', '经营总览'],
    products: ['商品管理', '商品中心'],
    categories: ['分类管理', '商品中心'],
    inventory: ['库存管理', '商品中心'],
    orders: ['订单中心', '交易履约'],
    fulfillment: ['履约发货', '交易履约'],
    aftersales: ['售后处理', '交易履约'],
    coupons: ['优惠券', '营销中心'],
    campaigns: ['营销活动', '营销中心'],
    shops: ['店铺商家', '商家管理'],
    finance: ['财务结算', '交易履约'],
    audit: ['操作审计', '系统'],
    settings: ['商城设置', '系统']
  };
  const STATUS = {
    paying: ['待付款', 'orange'], grouping: ['拼团中', 'blue'], wait: ['待发货', 'orange'],
    shipped: ['待收货', 'blue'], done: ['已完成', 'green'], cancel: ['已取消', 'gray'],
    refunded: ['已退款', 'gray'], closed: ['已关闭', 'gray'], aftersale: ['售后中', 'red']
  };

  let DATA = null;
  let VIEW = 'dashboard';
  let STATE = { productQ: '', productCate: '', productOn: '', orderQ: '', orderStatus: '' };
  let toastTimer = 0;

  function esc(v) {
    return String(v == null ? '' : v).replace(/[&<>"']/g, (c) =>
      ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  }
  function money(v) { return '¥' + (Number(v) || 0).toFixed(2); }
  function fmt(v) {
    if (!v) return '—';
    const d = new Date(v);
    if (Number.isNaN(d.getTime())) return String(v);
    const p = (n) => String(n).padStart(2, '0');
    return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate()) +
      ' ' + p(d.getHours()) + ':' + p(d.getMinutes());
  }
  function stockOf(p) {
    if (p.stock !== undefined && p.stock !== null && p.stock !== '') return Math.max(0, Number(p.stock) || 0);
    if (Array.isArray(p.variants)) return p.variants.reduce((n, v) => n + Math.max(0, Number(v.stock) || 0), 0);
    return 0;
  }
  function tag(text, tone) { return '<span class="tag ' + (tone || 'gray') + '">' + esc(text) + '</span>'; }
  function statusTag(status) {
    const item = STATUS[status] || [status || '未知', 'gray'];
    return tag(item[0], item[1]);
  }
  function img(p) {
    if (p.img) return '<img class="thumb" src="' + esc(p.img) + '" alt="">';
    return '<span class="thumb" style="display:grid;place-items:center;font-size:20px">' + esc(p.em || '📦') + '</span>';
  }
  function toast(msg, bad) {
    const el = $('toast');
    el.textContent = msg;
    el.className = 'toast show' + (bad ? ' bad' : '');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { el.className = 'toast'; }, 2400);
  }
  function openModal(html) {
    $('modalBody').innerHTML = html;
    $('modal').classList.add('open');
  }
  function closeModal() { $('modal').classList.remove('open'); }

  async function api(path, options) {
    const opts = Object.assign({ headers: {} }, options || {});
    if (opts.body && typeof opts.body !== 'string') {
      opts.headers['Content-Type'] = 'application/json';
      opts.body = JSON.stringify(opts.body);
    }
    const res = await fetch('/api/ops' + path, opts);
    let json = null;
    try { json = await res.json(); } catch (_) { json = null; }
    if (!res.ok || !json || json.ok !== true) {
      throw new Error((json && json.error) || ('请求失败 ' + res.status));
    }
    return json.data || {};
  }

  async function boot() {
    if (new URLSearchParams(location.search).get('embed') === '1') {
      document.body.classList.add('embedded');
    }
    try {
      const session = await api('/session');
      if (!session.authenticated) return showLogin();
      showApp(session.admin);
      await load();
    } catch (_) {
      showLogin();
    }
  }
  function showLogin() {
    $('login').classList.remove('hidden');
    $('shell').classList.add('hidden');
  }
  function showApp(admin) {
    $('login').classList.add('hidden');
    $('shell').classList.remove('hidden');
    const name = (admin && (admin.name || admin.username)) || '管理员';
    $('adminName').textContent = name;
    $('adminRole').textContent = (admin && (admin.roleName || admin.role)) || '';
    $('adminAvatar').textContent = name.slice(0, 1).toUpperCase();
  }

  async function load() {
    $('syncState').textContent = '正在同步';
    try {
      DATA = await api('/malladmin');
      $('syncState').textContent = '数据已连接';
      updateBadges();
      render();
    } catch (e) {
      $('syncState').textContent = '同步失败';
      toast(e.message, true);
    }
  }
  function updateBadges() {
    const d = DATA.dashboard;
    $('badgeProducts').textContent = d.products || '';
    $('badgeStock').textContent = d.lowStock || '';
    $('badgeOrders').textContent = (d.waitingShip || 0) + (d.shipping || 0) || '';
    $('badgeAfter').textContent = d.afterSales || '';
  }
  function go(view) {
    if (!VIEWS[view]) view = 'dashboard';
    VIEW = view;
    document.querySelectorAll('#nav button').forEach((b) => b.classList.toggle('active', b.dataset.view === view));
    $('viewTitle').textContent = VIEWS[view][0];
    $('crumb').textContent = VIEWS[view][1];
    document.title = VIEWS[view][0] + ' · 星言商城后台';
    document.body.classList.remove('menu-open');
    render();
  }
  function render() {
    if (!DATA) return;
    const box = $('view');
    if (VIEW === 'dashboard') box.innerHTML = dashboardView();
    else if (VIEW === 'products') box.innerHTML = productsView();
    else if (VIEW === 'categories') box.innerHTML = categoriesView();
    else if (VIEW === 'inventory') box.innerHTML = inventoryView();
    else if (VIEW === 'orders') box.innerHTML = ordersView(false);
    else if (VIEW === 'fulfillment') box.innerHTML = ordersView(true);
    else if (VIEW === 'aftersales') box.innerHTML = afterSalesView();
    else if (VIEW === 'coupons') box.innerHTML = couponsView();
    else if (VIEW === 'campaigns') box.innerHTML = genericView('campaigns', '营销活动', '创建满减、秒杀、拼团、专题会场等活动骨架');
    else if (VIEW === 'shops') box.innerHTML = genericView('shops', '店铺商家', '维护店铺主体、结算方式、发货地和经营状态');
    else if (VIEW === 'finance') box.innerHTML = financeView();
    else if (VIEW === 'audit') box.innerHTML = auditView();
    else if (VIEW === 'settings') box.innerHTML = settingsView();
    bindView();
  }

  function dashCard(k, v, s, warn) {
    return '<article class="kpi' + (warn ? ' warn' : '') + '"><div class="k">' + esc(k) +
      '</div><div class="v">' + esc(v) + '</div><div class="s">' + esc(s) + '</div></article>';
  }
  function dashboardView() {
    const d = DATA.dashboard;
    const orders = (DATA.admin.orders || []).slice(0, 8);
    const low = DATA.mall.products.filter((p) => stockOf(p) <= 10).sort((a, b) => stockOf(a) - stockOf(b)).slice(0, 7);
    const max = Math.max(1, ...orders.map((o) => Number(o.total) || 0));
    return '<div class="kpis">' +
      dashCard('累计成交额', money(d.gmv), '已付款且未取消订单') +
      dashCard('订单总数', d.orders || 0, '待发货 ' + (d.waitingShip || 0) + ' · 待收货 ' + (d.shipping || 0)) +
      dashCard('在售商品', d.activeProducts + ' / ' + d.products, '库存预警 ' + d.lowStock + ' 件', d.lowStock > 0) +
      dashCard('待处理售后', d.afterSales || 0, '已发放未使用券 ' + d.coupons, d.afterSales > 0) +
      '</div><div class="grid2"><section class="panel"><div class="panel-head"><h3>最近订单</h3><span class="spacer"></span>' +
      '<button class="btn small" data-nav="orders">全部订单</button></div><div class="table-wrap"><table><thead><tr>' +
      '<th>订单</th><th>买家</th><th>金额</th><th>状态</th><th>时间</th></tr></thead><tbody>' +
      (orders.length ? orders.map((o) => '<tr><td>' + esc(o.id) + '<div class="hint">' + esc((o.items || []).join('、')).slice(0, 60) +
        '</div></td><td>' + esc(o.buyer || '—') + '</td><td class="money">' + money(o.total) + '</td><td>' +
        statusTag(o.status) + '</td><td>' + fmt(o.at) + '</td></tr>').join('') :
        '<tr><td colspan="5"><div class="empty-state">还没有订单</div></td></tr>') +
      '</tbody></table></div></section><section class="panel"><div class="panel-head"><h3>库存预警</h3><span class="spacer"></span>' +
      '<button class="btn small" data-nav="inventory">处理库存</button></div><div class="panel-body">' +
      (low.length ? low.map((p) => '<div class="product-line" style="margin-bottom:13px">' + img(p) +
        '<div><b>' + esc(p.title) + '</b><small>剩余 ' + stockOf(p) + ' · ' + esc(p.cate || '未分类') +
        '</small></div></div>').join('') : '<div class="empty-state">库存充足</div>') +
      '</div></section></div><section class="panel" style="margin-top:16px"><div class="panel-head"><h3>成交分布</h3>' +
      '<span class="spacer"></span><span class="hint">按最近订单金额</span></div><div class="spark">' +
      (orders.length ? orders.map((o) => '<i class="bar" title="' + money(o.total) + '" style="height:' +
        Math.max(6, Math.round((Number(o.total) || 0) / max * 138)) + 'px"></i>').join('') :
        '<div class="empty-state">暂无成交数据</div>') + '</div></section>';
  }

  function productsView() {
    const cats = [...new Set(DATA.mall.products.map((p) => p.cate).filter(Boolean))];
    const q = STATE.productQ.trim().toLowerCase();
    const rows = DATA.mall.products.filter((p) =>
      (!q || (p.title || '').toLowerCase().includes(q) || (p.id || '').toLowerCase().includes(q)) &&
      (!STATE.productCate || p.cate === STATE.productCate) &&
      (STATE.productOn === '' || String(p.on !== false) === STATE.productOn));
    return '<div class="toolbar"><input class="grow" id="productQ" placeholder="搜索商品标题或 ID" value="' + esc(STATE.productQ) + '">' +
      '<select id="productCate"><option value="">全部分类</option>' + cats.map((c) =>
        '<option value="' + esc(c) + '"' + (STATE.productCate === c ? ' selected' : '') + '>' + esc(c) + '</option>').join('') +
      '</select><select id="productOn"><option value="">全部状态</option><option value="true"' +
      (STATE.productOn === 'true' ? ' selected' : '') + '>在售</option><option value="false"' +
      (STATE.productOn === 'false' ? ' selected' : '') + '>下架</option></select>' +
      '<span class="spacer"></span><button class="btn primary" data-action="product-new">＋ 新建商品</button></div>' +
      '<section class="panel"><div class="table-wrap"><table><thead><tr><th>商品</th><th>分类</th><th>售价</th><th>成本</th>' +
      '<th>库存</th><th>状态</th><th>操作</th></tr></thead><tbody>' +
      (rows.length ? rows.map((p) => '<tr><td class="title-cell"><div class="product-line">' + img(p) +
        '<div><b>' + esc(p.title) + '</b><small>' + esc(p.id) + ' · ' + esc(p.shop || '未绑定店铺') + '</small></div></div></td>' +
        '<td>' + esc(p.cate || '其它') + '</td><td class="money">' + money(p.price) + '</td><td class="money">' +
        money(p.cost) + '</td><td>' + stockOf(p) + '</td><td>' + statusTag(p.on === false ? 'closed' : 'done').replace('已完成', '在售') +
        '</td><td><div class="actions"><button class="btn small" data-action="product-edit" data-id="' + esc(p.id) +
        '">编辑</button><button class="btn small" data-action="product-toggle" data-id="' + esc(p.id) + '">' +
        (p.on === false ? '上架' : '下架') + '</button><button class="btn small danger" data-action="product-delete" data-id="' +
        esc(p.id) + '">删除</button></div></td></tr>').join('') :
        '<tr><td colspan="7"><div class="empty-state">没有符合条件的商品</div></td></tr>') +
      '</tbody></table></div></section>';
  }
  function categoriesView() {
    const names = [...new Set([
      ...(DATA.mall.categories || []),
      ...DATA.mall.products.map((p) => p.cate).filter(Boolean)
    ])];
    return '<div class="toolbar"><div><h3 class="section-title">商品分类</h3><span class="hint">分类会同步用于商品编辑和前台筛选</span></div>' +
      '<span class="spacer"></span><button class="btn primary" data-action="category-new">＋ 新增分类</button></div>' +
      '<section class="panel"><div class="sub-grid" style="padding:16px">' + (names.length ? names.map((name) => {
        const products = DATA.mall.products.filter((p) => p.cate === name);
        const active = products.filter((p) => p.on !== false).length;
        return '<article class="mini-card"><b>' + esc(name) + '</b><small>' + products.length + ' 件商品 · 在售 ' + active +
          '</small><div class="actions" style="margin-top:13px"><button class="btn small danger" data-action="category-remove" data-name="' +
          esc(name) + '">删除</button></div></article>';
      }).join('') : '<div class="empty-state">暂无分类</div>') + '</div></section>';
  }
  function inventoryView() {
    const rows = [...DATA.mall.products].sort((a, b) => stockOf(a) - stockOf(b));
    return '<div class="toolbar"><div><h3 class="section-title">库存总览</h3><span class="hint">库存 ≤ 10 自动进入预警</span></div>' +
      '<span class="spacer"></span><button class="btn primary" data-action="inventory-adjust">调整库存</button></div>' +
      '<section class="panel"><div class="table-wrap"><table><thead><tr><th>商品</th><th>当前库存</th><th>预警</th><th>仓库</th>' +
      '<th>供应商</th><th>最近调整</th></tr></thead><tbody>' +
      rows.map((p) => {
        const logs = (DATA.admin.inventoryLogs || []).filter((x) => x.productId === p.id);
        return '<tr><td class="title-cell"><div class="product-line">' + img(p) + '<div><b>' + esc(p.title) +
          '</b><small>' + esc(p.id) + '</small></div></div></td><td><b>' + stockOf(p) + '</b></td><td>' +
          (stockOf(p) <= 10 ? tag('需要补货', 'red') : tag('正常', 'green')) + '</td><td>' + esc(p.warehouse || '默认仓') +
          '</td><td>' + esc(p.supplier || '—') + '</td><td>' + fmt(logs[0] && logs[0].at) + '</td></tr>';
      }).join('') + '</tbody></table></div></section><section class="panel" style="margin-top:16px"><div class="panel-head"><h3>最近库存流水</h3></div>' +
      '<div class="panel-body">' + ((DATA.admin.inventoryLogs || []).slice(0, 20).map((x) =>
        '<div class="audit-line"><span>' + fmt(x.at) + '</span><b>' + esc(x.reason) + '</b><span>' + esc(x.title) +
        '</span><span>' + esc(x.before) + ' → ' + esc(x.after) + ' · ' + esc(x.by) + '</span></div>').join('') ||
        '<div class="empty-state">暂无库存流水</div>') + '</div></section>';
  }
  function financeView() {
    const orders = DATA.admin.orders || [];
    const paid = orders.filter((o) => o.paid && o.status !== 'cancel');
    const refunded = orders.filter((o) => ['refunded'].includes(o.status));
    const gross = paid.reduce((n, o) => n + (Number(o.total) || 0), 0);
    const refund = refunded.reduce((n, o) => n + (Number(o.total) || 0), 0);
    const byShop = new Map();
    paid.forEach((o) => {
      const first = (o.lines || [])[0];
      const p = first && productById(first.pid);
      const shop = (p && p.shop) || '未绑定店铺';
      const cur = byShop.get(shop) || { orders: 0, amount: 0, refund: 0 };
      cur.orders += 1;
      cur.amount += Number(o.total) || 0;
      if (refunded.some((r) => r.id === o.id)) cur.refund += Number(o.total) || 0;
      byShop.set(shop, cur);
    });
    const shops = (DATA.admin.shops || []);
    if (!shops.length) {
      [...byShop.keys()].forEach((name) => shops.push({ id: 'derived-' + name, name, enabled: true }));
    }
    return '<div class="kpis">' +
      dashCard('成交总额', money(gross), '支付成功且未取消') +
      dashCard('退款金额', money(refund), refunded.length + ' 笔退款') +
      dashCard('净成交额', money(Math.max(0, gross - refund)), '扣除已退款订单') +
      dashCard('客单价', money(paid.length ? gross / paid.length : 0), paid.length + ' 笔有效订单') +
      '</div><section class="panel"><div class="panel-head"><h3>店铺结算骨架</h3><span class="spacer"></span>' +
      '<span class="hint">结算金额 = 成交额 - 退款额，实际打款仍需支付通道接入</span></div><div class="table-wrap"><table>' +
      '<thead><tr><th>店铺</th><th>有效订单</th><th>成交额</th><th>退款额</th><th>应结金额</th><th>状态</th></tr></thead><tbody>' +
      (shops.length ? shops.map((s) => {
        const row = byShop.get(s.name) || { orders: 0, amount: 0, refund: 0 };
        return '<tr><td><b>' + esc(s.name) + '</b><div class="hint">' + esc(s.id || '') + '</div></td><td>' + row.orders +
          '</td><td class="money">' + money(row.amount) + '</td><td class="money">' + money(row.refund) +
          '</td><td class="money"><b>' + money(Math.max(0, row.amount - row.refund)) + '</b></td><td>' +
          tag(s.enabled === false ? '暂停结算' : '待接入支付', s.enabled === false ? 'gray' : 'blue') + '</td></tr>';
      }).join('') : '<tr><td colspan="6"><div class="empty-state">暂无结算数据</div></td></tr>') +
      '</tbody></table></div></section>';
  }

  function filteredOrders(fulfillment) {
    const q = STATE.orderQ.trim().toLowerCase();
    return (DATA.admin.orders || []).filter((o) =>
      (!fulfillment || ['wait', 'grouping', 'shipped'].includes(o.status)) &&
      (!STATE.orderStatus || o.status === STATE.orderStatus) &&
      (!q || (o.id || '').toLowerCase().includes(q) || (o.buyer || '').toLowerCase().includes(q)));
  }
  function ordersView(fulfillment) {
    const rows = filteredOrders(fulfillment);
    return '<div class="toolbar"><input class="grow" id="orderQ" placeholder="搜索订单号、买家" value="' + esc(STATE.orderQ) + '">' +
      '<select id="orderStatus"><option value="">全部状态</option>' + Object.keys(STATUS).map((s) =>
        '<option value="' + s + '"' + (STATE.orderStatus === s ? ' selected' : '') + '>' + STATUS[s][0] + '</option>').join('') +
      '</select><span class="spacer"></span><button class="btn" data-action="orders-export">导出当前列表</button></div>' +
      '<section class="panel"><div class="table-wrap"><table><thead><tr><th>订单</th><th>买家</th><th>商品</th><th>金额</th>' +
      '<th>状态</th><th>物流</th><th>时间</th><th>操作</th></tr></thead><tbody>' +
      (rows.length ? rows.map((o) => '<tr><td><b>' + esc(o.id) + '</b><div class="hint">' +
        esc(o.payWay || '未选择支付') + '</div></td><td>' + esc(o.buyer || '—') + '</td><td class="title-cell">' +
        esc((o.items || []).join('、')).slice(0, 100) + '</td><td class="money">' + money(o.total) + '</td><td>' +
        statusTag(o.status) + '</td><td>' + esc(o.express ? ((o.express.company || '') + ' ' + (o.express.no || '')) : '—') +
        '</td><td>' + fmt(o.at) + '</td><td><button class="btn small" data-action="order-detail" data-id="' + esc(o.id) +
        '">详情</button></td></tr>').join('') : '<tr><td colspan="8"><div class="empty-state">暂无订单</div></td></tr>') +
      '</tbody></table></div></section>';
  }
  function afterSalesView() {
    const rows = DATA.admin.afterSales || [];
    return '<section class="panel"><div class="panel-head"><h3>售后工单</h3><span class="spacer"></span><span class="hint">' +
      rows.filter((x) => x.status === 'pending').length + ' 条待处理</span></div><div class="table-wrap"><table><thead><tr>' +
      '<th>售后单</th><th>订单</th><th>买家</th><th>类型</th><th>原因</th><th>状态</th><th>申请时间</th><th>操作</th></tr></thead><tbody>' +
      (rows.length ? rows.map((x) => '<tr><td>' + esc(x.id) + '</td><td>' + esc(x.orderId) + '</td><td>' + esc(x.buyer) +
        '</td><td>' + esc(x.kind) + '</td><td class="title-cell">' + esc(x.reason) + '</td><td>' +
        tag(x.status === 'pending' ? '待审核' : x.status === 'approved' ? '已同意' : '已拒绝', x.status === 'pending' ? 'orange' : x.status === 'approved' ? 'green' : 'gray') +
        '</td><td>' + fmt(x.askAt) + '</td><td>' + (x.status === 'pending' ? '<div class="actions">' +
        '<button class="btn small primary" data-action="after-pass" data-id="' + esc(x.id) + '">同意</button>' +
        '<button class="btn small danger" data-action="after-reject" data-id="' + esc(x.id) + '">拒绝</button></div>' : '—') +
        '</td></tr>').join('') : '<tr><td colspan="8"><div class="empty-state">暂无售后单</div></td></tr>') +
      '</tbody></table></div></section>';
  }
  function couponsView() {
    const rows = DATA.admin.coupons || [];
    const used = new Set((DATA.admin.couponClaims || []).map((x) => x.couponId));
    return '<div class="toolbar"><div><h3 class="section-title">优惠券模板</h3><span class="hint">发放记录 ' +
      (DATA.admin.couponClaims || []).length + ' 张</span></div><span class="spacer"></span>' +
      '<button class="btn primary" data-action="coupon-new">＋ 新建优惠券</button></div><section class="panel"><div class="table-wrap"><table>' +
      '<thead><tr><th>名称</th><th>优惠</th><th>门槛</th><th>总量</th><th>每人限领</th><th>有效期</th><th>状态</th><th>操作</th></tr></thead><tbody>' +
      (rows.length ? rows.map((c) => '<tr><td><b>' + esc(c.title) + '</b><div class="hint">' + esc(c.id) +
        (used.has(c.id) ? ' · 已发放' : '') + '</div></td><td>' + (c.kind === 'discount' ? (Number(c.off) || 0) + ' 折' : money(c.off)) +
        '</td><td>' + money(c.min) + '</td><td>' + (c.total || '不限') + '</td><td>' + (c.perUser || 1) +
        '</td><td>' + (c.days || 7) + ' 天</td><td>' + tag(c.enabled === false ? '停用' : '启用', c.enabled === false ? 'gray' : 'green') +
        '</td><td><div class="actions"><button class="btn small" data-action="coupon-edit" data-id="' + esc(c.id) +
        '">编辑</button><button class="btn small danger" data-action="coupon-delete" data-id="' + esc(c.id) + '">删除</button></div></td></tr>').join('') :
        '<tr><td colspan="8"><div class="empty-state">还没有优惠券模板</div></td></tr>') +
      '</tbody></table></div></section>';
  }
  function genericView(key, title, hint) {
    const rows = DATA.admin[key] || [];
    return '<div class="toolbar"><div><h3 class="section-title">' + esc(title) + '</h3><span class="hint">' + esc(hint) +
      '</span></div><span class="spacer"></span><button class="btn primary" data-action="generic-new" data-key="' + key +
      '">＋ 新建</button></div><section class="panel"><div class="sub-grid" style="padding:16px">' +
      (rows.length ? rows.map((x) => '<article class="mini-card"><b>' + esc(x.name || x.title || x.id) + '</b><small>' +
        esc(x.description || x.desc || x.address || '') + '</small><div class="actions" style="margin-top:13px">' +
        '<button class="btn small" data-action="generic-edit" data-key="' + key + '" data-id="' + esc(x.id) + '">编辑</button>' +
        '<button class="btn small danger" data-action="generic-delete" data-key="' + key + '" data-id="' + esc(x.id) +
        '">删除</button></div></article>').join('') : '<div class="empty-state">暂无数据</div>') + '</div></section>';
  }
  function auditView() {
    const rows = DATA.admin.auditLogs || [];
    return '<section class="panel"><div class="panel-head"><h3>商城操作审计</h3><span class="spacer"></span><span class="hint">' +
      rows.length + ' 条</span></div><div class="panel-body">' +
      (rows.length ? rows.slice(0, 400).map((x) => '<div class="audit-line"><span>' + fmt(x.at) + '</span><b>' +
        esc(x.by) + '</b><span>' + esc(x.action) + ' · ' + esc(x.target) + '</span><span>' + esc(x.detail) + '</span></div>').join('') :
        '<div class="empty-state">暂无操作记录</div>') + '</div></section>';
  }
  function settingsView() {
    const m = DATA.mall;
    const s = DATA.admin.settings || {};
    return '<div class="grid2"><section class="panel"><div class="panel-head"><h3>商城基础设置</h3></div><div class="panel-body">' +
      '<div class="form-grid"><div class="field"><label>商城名称</label><input id="storeName" value="' + esc(m.name) + '"></div>' +
      '<div class="field"><label>商城标语</label><input id="storeSlogan" value="' + esc(m.slogan) + '"></div>' +
      '<div class="field full"><label>首页轮播图（每行一个 URL）</label><textarea id="banners">' +
      esc((m.banners || []).join('\n')) + '</textarea></div></div><div class="form-actions">' +
      '<button class="btn primary" data-action="store-save">保存商城设置</button></div></div></section>' +
      '<section class="panel"><div class="panel-head"><h3>交易规则</h3></div><div class="panel-body"><div class="form-grid">' +
      '<div class="field"><label>自动确认收货（天）</label><input id="autoConfirmDays" type="number" value="' + esc(s.autoConfirmDays) + '"></div>' +
      '<div class="field"><label>待付款超时（分钟）</label><input id="unpaidTimeoutMinutes" type="number" value="' + esc(s.unpaidTimeoutMinutes) + '"></div>' +
      '<div class="field"><label>库存策略</label><select id="stockPolicy"><option value="block"' + (s.stockPolicy === 'block' ? ' selected' : '') +
      '>禁止超卖</option><option value="warn"' + (s.stockPolicy === 'warn' ? ' selected' : '') + '>预警</option>' +
      '<option value="oversell"' + (s.stockPolicy === 'oversell' ? ' selected' : '') + '>允许超卖</option></select></div>' +
      '<div class="field"><label>客服电话</label><input id="servicePhone" value="' + esc(s.servicePhone) + '"></div>' +
      '<div class="field full"><label>服务时间</label><input id="serviceHours" value="' + esc(s.serviceHours) + '"></div>' +
      '<div class="field full"><label>下单备注</label><textarea id="orderNote">' + esc(s.orderNote) + '</textarea></div>' +
      '</div><div class="form-actions"><button class="btn primary" data-action="rules-save">保存交易规则</button></div></div></section></div>';
  }

  function productById(id) { return DATA.mall.products.find((p) => String(p.id) === String(id)); }
  function variantText(p) {
    return (Array.isArray(p.variants) ? p.variants : [])
      .map((v) => [v.name || '', Number(v.price) || 0, Number(v.stock) || 0].join(','))
      .join('\n');
  }
  function productForm(p) {
    p = p || {};
    const cats = [...new Set(DATA.mall.products.map((x) => x.cate).filter(Boolean))];
    return '<h3>' + (p.id ? '编辑商品' : '新建商品') + '</h3><input type="hidden" id="pfId" value="' + esc(p.id || '') + '">' +
      '<div class="form-grid"><div class="field full"><label>商品标题</label><input id="pfTitle" value="' + esc(p.title) + '"></div>' +
      '<div class="field"><label>分类</label><input id="pfCate" list="pfCats" value="' + esc(p.cate || '') + '"><datalist id="pfCats">' +
      cats.map((c) => '<option value="' + esc(c) + '">').join('') + '</datalist></div>' +
      '<div class="field"><label>店铺</label><input id="pfShop" value="' + esc(p.shop || '') + '"></div>' +
      '<div class="field"><label>售价</label><input id="pfPrice" type="number" step="0.01" value="' + esc(p.price || 0) + '"></div>' +
      '<div class="field"><label>划线价</label><input id="pfOrig" type="number" step="0.01" value="' + esc(p.orig || 0) + '"></div>' +
      '<div class="field"><label>成本价</label><input id="pfCost" type="number" step="0.01" value="' + esc(p.cost || 0) + '"></div>' +
      '<div class="field"><label>库存</label><input id="pfStock" type="number" value="' + esc(stockOf(p)) + '"></div>' +
      '<div class="field"><label>主图 URL</label><input id="pfImg" value="' + esc(p.img || '') + '"></div>' +
      '<div class="field"><label>Emoji</label><input id="pfEm" value="' + esc(p.em || '📦') + '"></div>' +
      '<div class="field"><label>供应商</label><input id="pfSupplier" value="' + esc(p.supplier || '') + '"></div>' +
      '<div class="field"><label>仓库</label><input id="pfWarehouse" value="' + esc(p.warehouse || '默认仓') + '"></div>' +
      '<div class="field full"><label>卖点标签（逗号分隔）</label><input id="pfTags" value="' + esc((p.tags || []).join(',')) + '"></div>' +
      '<div class="field full"><label>规格 SKU（每行：名称,价格,库存）</label><textarea id="pfVariants" placeholder="S,59.90,20\nM,59.90,20">' +
      esc(variantText(p)) + '</textarea></div>' +
      '<div class="field full"><label>商品详情</label><textarea id="pfDetail">' + esc(p.detail || '') + '</textarea></div>' +
      '<div class="field"><label>状态</label><select id="pfOn"><option value="true"' + (p.on !== false ? ' selected' : '') +
      '>在售</option><option value="false"' + (p.on === false ? ' selected' : '') + '>下架</option></select></div></div>' +
      '<div class="form-actions"><button class="btn" data-close>取消</button><button class="btn primary" data-action="product-save">保存商品</button></div>';
  }
  function orderDetail(o) {
    const options = Object.keys(STATUS).map((s) => '<option value="' + s + '"' + (o.status === s ? ' selected' : '') + '>' +
      STATUS[s][0] + '</option>').join('');
    return '<h3>订单 ' + esc(o.id) + '</h3><input type="hidden" id="ofId" value="' + esc(o.id) + '">' +
      '<div class="sub-grid"><article class="mini-card"><small>买家</small><b>' + esc(o.buyer) + '</b></article>' +
      '<article class="mini-card"><small>金额</small><b>' + money(o.total) + '</b></article>' +
      '<article class="mini-card"><small>状态</small><b>' + (STATUS[o.status] || [o.status])[0] + '</b></article></div>' +
      '<div class="form-grid" style="margin-top:16px"><div class="field full"><label>地址</label><input id="ofAddress" value="' +
      esc(o.address || '') + '"></div><div class="field"><label>订单状态</label><select id="ofStatus">' + options + '</select></div>' +
      '<div class="field"><label>快递公司</label><input id="ofCompany" value="' + esc(o.express && o.express.company || '') + '"></div>' +
      '<div class="field"><label>快递单号</label><input id="ofNo" value="' + esc(o.express && o.express.no || '') + '"></div>' +
      '<div class="field full"><label>追加物流动态</label><textarea id="ofTrack"></textarea></div>' +
      '<div class="field full"><label>订单备注</label><textarea id="ofRemark">' + esc(o.remark || '') + '</textarea></div></div>' +
      '<div class="panel-body" style="padding:16px 0 0"><b>商品</b>' + (o.lines || []).map((x) => '<div class="audit-line"><span></span><b>' +
      esc(x.title) + '</b><span>' + money(x.price) + ' × ' + esc(x.count) + '</span><span>' + esc(x.spec || '') + '</span></div>').join('') +
      '</div><div class="panel-body" style="padding:16px 0 0"><b>物流记录</b>' + ((o.logistics || []).slice().reverse().map((x) =>
      '<div class="audit-line"><span>' + fmt(x.time) + '</span><b>' + esc(x.src) + '</b><span></span><span>' + esc(x.text) +
      '</span></div>').join('') || '<div class="hint">暂无物流</div>') + '</div>' +
      '<div class="form-actions"><button class="btn" data-close>关闭</button><button class="btn primary" data-action="order-save">保存订单</button></div>';
  }

  function bindView() {
    const pQ = $('productQ');
    if (pQ) pQ.oninput = (e) => rerenderWithFocus('productQ', () => { STATE.productQ = e.target.value; });
    const pCate = $('productCate');
    if (pCate) pCate.onchange = (e) => { STATE.productCate = e.target.value; render(); };
    const pOn = $('productOn');
    if (pOn) pOn.onchange = (e) => { STATE.productOn = e.target.value; render(); };
    const oQ = $('orderQ');
    if (oQ) oQ.oninput = (e) => rerenderWithFocus('orderQ', () => { STATE.orderQ = e.target.value; });
    const oStatus = $('orderStatus');
    if (oStatus) oStatus.onchange = (e) => { STATE.orderStatus = e.target.value; render(); };
  }
  function rerenderWithFocus(id, mutate) {
    const old = $(id);
    const pos = old ? old.selectionStart : 0;
    mutate();
    render();
    const next = $(id);
    if (next) {
      next.focus();
      try { next.setSelectionRange(pos, pos); } catch (_) {}
    }
  }

  async function submitProduct() {
    const id = $('pfId').value.trim();
    const item = {
      id,
      title: $('pfTitle').value.trim(),
      cate: $('pfCate').value.trim(),
      shop: $('pfShop').value.trim(),
      price: Number($('pfPrice').value) || 0,
      orig: Number($('pfOrig').value) || 0,
      cost: Number($('pfCost').value) || 0,
      stock: Number($('pfStock').value) || 0,
      img: $('pfImg').value.trim(),
      em: $('pfEm').value.trim() || '📦',
      supplier: $('pfSupplier').value.trim(),
      warehouse: $('pfWarehouse').value.trim(),
      tags: $('pfTags').value.split(',').map((x) => x.trim()).filter(Boolean).slice(0, 4),
      variants: $('pfVariants').value.split(/\r?\n/).map((line) => {
        const parts = line.split(',').map((x) => x.trim());
        return { name: parts[0] || '', price: Number(parts[1]) || 0, stock: Number(parts[2]) || 0 };
      }).filter((x) => x.name),
      detail: $('pfDetail').value,
      on: $('pfOn').value === 'true'
    };
    if (!item.title) return toast('请填写商品标题', true);
    await api('/mall', { method: 'POST', body: { action: 'product', item } });
    closeModal();
    toast('商品已保存');
    await load();
  }
  async function submitOrder() {
    await api('/malladmin', { method: 'POST', body: {
      action: 'order.update', id: $('ofId').value, status: $('ofStatus').value,
      expressCompany: $('ofCompany').value, expressNo: $('ofNo').value,
      logisticsText: $('ofTrack').value, remark: $('ofRemark').value
    }});
    closeModal();
    toast('订单已更新');
    await load();
  }

  function couponForm(c) {
    c = c || {};
    return '<h3>' + (c.id ? '编辑优惠券' : '新建优惠券') + '</h3><input type="hidden" id="cfId" value="' + esc(c.id || '') + '">' +
      '<div class="form-grid"><div class="field full"><label>名称</label><input id="cfTitle" value="' + esc(c.title || '') + '"></div>' +
      '<div class="field"><label>类型</label><select id="cfKind"><option value="cash"' + (c.kind !== 'discount' ? ' selected' : '') +
      '>满减券</option><option value="discount"' + (c.kind === 'discount' ? ' selected' : '') + '>折扣券</option></select></div>' +
      '<div class="field"><label>优惠值</label><input id="cfOff" type="number" step="0.01" value="' + esc(c.off || 5) + '"></div>' +
      '<div class="field"><label>使用门槛</label><input id="cfMin" type="number" step="0.01" value="' + esc(c.min || 0) + '"></div>' +
      '<div class="field"><label>总量</label><input id="cfTotal" type="number" value="' + esc(c.total || 0) + '"></div>' +
      '<div class="field"><label>每人限领</label><input id="cfPer" type="number" value="' + esc(c.perUser || 1) + '"></div>' +
      '<div class="field"><label>有效天数</label><input id="cfDays" type="number" value="' + esc(c.days || 7) + '"></div>' +
      '<div class="field"><label>状态</label><select id="cfEnabled"><option value="true"' + (c.enabled !== false ? ' selected' : '') +
      '>启用</option><option value="false"' + (c.enabled === false ? ' selected' : '') + '>停用</option></select></div></div>' +
      '<div class="form-actions"><button class="btn" data-close>取消</button><button class="btn primary" data-action="coupon-save">保存</button></div>';
  }
  function genericForm(key, item) {
    item = item || {};
    return '<h3>' + (key === 'campaigns' ? '营销活动' : '店铺') + '</h3><input type="hidden" id="gfKey" value="' + esc(key) +
      '"><input type="hidden" id="gfId" value="' + esc(item.id || '') + '"><div class="form-grid">' +
      '<div class="field full"><label>名称</label><input id="gfName" value="' + esc(item.name || item.title || '') + '"></div>' +
      '<div class="field full"><label>说明</label><textarea id="gfDesc">' + esc(item.description || item.desc || '') + '</textarea></div>' +
      '<div class="field full"><label>备注 / 地址</label><input id="gfAddress" value="' + esc(item.address || item.note || '') + '"></div>' +
      '<div class="field"><label>状态</label><select id="gfEnabled"><option value="true"' + (item.enabled !== false ? ' selected' : '') +
      '>启用</option><option value="false"' + (item.enabled === false ? ' selected' : '') + '>停用</option></select></div></div>' +
      '<div class="form-actions"><button class="btn" data-close>取消</button><button class="btn primary" data-action="generic-save">保存</button></div>';
  }
  function inventoryForm() {
    return '<h3>调整库存</h3><div class="form-grid"><div class="field full"><label>商品</label><select id="ifProduct">' +
      DATA.mall.products.map((p) => '<option value="' + esc(p.id) + '">' + esc(p.title) + '（当前 ' + stockOf(p) + '）</option>').join('') +
      '</select></div><div class="field"><label>新库存</label><input id="ifStock" type="number" value="0"></div>' +
      '<div class="field"><label>原因</label><input id="ifReason" placeholder="盘点、补货、损耗"></div></div>' +
      '<div class="form-actions"><button class="btn" data-close>取消</button><button class="btn primary" data-action="inventory-save">保存库存</button></div>';
  }
  function categoryForm() {
    return '<h3>新增分类</h3><div class="field"><label>分类名称</label><input id="catName" placeholder="例如：数码"></div>' +
      '<div class="form-actions"><button class="btn" data-close>取消</button><button class="btn primary" data-action="category-save">保存</button></div>';
  }

  document.addEventListener('click', async (e) => {
    const nav = e.target.closest('[data-nav]');
    if (nav) return go(nav.dataset.nav);
    if (e.target.closest('[data-close]') || e.target.id === 'modal' || e.target.id === 'modalClose') {
      closeModal();
      return;
    }
    const btn = e.target.closest('[data-action]');
    if (!btn || !DATA) return;
    const action = btn.dataset.action;
    const id = btn.dataset.id;
    try {
      if (action === 'product-new') return openModal(productForm());
      if (action === 'product-edit') return openModal(productForm(productById(id)));
      if (action === 'product-toggle') {
        const p = productById(id);
        await api('/mall', { method: 'POST', body: { action: 'product', item: Object.assign({}, p, { on: p.on === false }) } });
        toast(p.on === false ? '商品已上架' : '商品已下架');
        return load();
      }
      if (action === 'product-delete') {
        if (!confirm('确认删除这个商品？')) return;
        await api('/mall', { method: 'POST', body: { action: 'remove', id } });
        toast('商品已删除');
        return load();
      }
      if (action === 'product-save') return submitProduct();
      if (action === 'category-new') return openModal(categoryForm());
      if (action === 'category-save') {
        const name = $('catName').value.trim();
        if (!name) return toast('请填写分类名称', true);
        const list = [...new Set([...(DATA.mall.categories || []), ...DATA.mall.products.map((p) => p.cate).filter(Boolean), name])];
        await api('/mall', { method: 'POST', body: { action: 'categories', categories: list } });
        closeModal(); toast('分类已保存'); return load();
      }
      if (action === 'category-remove') {
        const name = btn.dataset.name;
        const n = DATA.mall.products.filter((p) => p.cate === name).length;
        if (n) return toast('这个分类下还有 ' + n + ' 件商品，请先调整商品分类', true);
        if (!confirm('确认删除分类「' + name + '」？')) return;
        const list = (DATA.mall.categories || []).filter((x) => x !== name);
        await api('/mall', { method: 'POST', body: { action: 'categories', categories: list } });
        toast('分类已删除'); return load();
      }
      if (action === 'order-detail') return openModal(orderDetail(DATA.admin.orders.find((o) => String(o.id) === String(id))));
      if (action === 'order-save') return submitOrder();
      if (action === 'inventory-adjust') return openModal(inventoryForm());
      if (action === 'inventory-save') {
        await api('/malladmin', { method: 'POST', body: { action: 'inventory.adjust',
          productId: $('ifProduct').value, stock: Number($('ifStock').value) || 0, reason: $('ifReason').value } });
        closeModal(); toast('库存已更新'); return load();
      }
      if (action === 'after-pass' || action === 'after-reject') {
        const note = prompt(action === 'after-pass' ? '售后通过备注' : '拒绝原因', '');
        if (note === null) return;
        await api('/malladmin', { method: 'POST', body: { action: 'aftersale.review', id, pass: action === 'after-pass', note } });
        toast('售后单已处理'); return load();
      }
      if (action === 'coupon-new') return openModal(couponForm());
      if (action === 'coupon-edit') return openModal(couponForm((DATA.admin.coupons || []).find((x) => String(x.id) === String(id))));
      if (action === 'coupon-delete') {
        if (!confirm('确认删除这张优惠券模板？')) return;
        await api('/malladmin', { method: 'POST', body: { action: 'coupon.remove', id } });
        toast('优惠券已删除'); return load();
      }
      if (action === 'coupon-save') {
        await api('/malladmin', { method: 'POST', body: { action: 'coupon.save', item: {
          id: $('cfId').value, title: $('cfTitle').value, kind: $('cfKind').value,
          off: Number($('cfOff').value) || 0, min: Number($('cfMin').value) || 0,
          total: Number($('cfTotal').value) || 0, perUser: Number($('cfPer').value) || 1,
          days: Number($('cfDays').value) || 7, enabled: $('cfEnabled').value === 'true'
        }}});
        closeModal(); toast('优惠券已保存'); return load();
      }
      if (action === 'generic-new') return openModal(genericForm(btn.dataset.key));
      if (action === 'generic-edit') {
        const key = btn.dataset.key;
        return openModal(genericForm(key, (DATA.admin[key] || []).find((x) => String(x.id) === String(id))));
      }
      if (action === 'generic-delete') {
        const key = btn.dataset.key;
        if (!confirm('确认删除？')) return;
        await api('/malladmin', { method: 'POST', body: { action: key === 'campaigns' ? 'campaign.remove' : 'shop.remove', id } });
        toast('已删除'); return load();
      }
      if (action === 'generic-save') {
        const key = $('gfKey').value;
        await api('/malladmin', { method: 'POST', body: {
          action: key === 'campaigns' ? 'campaign.save' : 'shop.save',
          item: { id: $('gfId').value, name: $('gfName').value, description: $('gfDesc').value,
            address: $('gfAddress').value, enabled: $('gfEnabled').value === 'true' }
        }});
        closeModal(); toast('已保存'); return load();
      }
      if (action === 'store-save') {
        await api('/mall', { method: 'POST', body: { action: 'settings', name: $('storeName').value, slogan: $('storeSlogan').value } });
        await api('/mall', { method: 'POST', body: { action: 'banners',
          banners: $('banners').value.split(/\r?\n/).map((x) => x.trim()).filter(Boolean) } });
        toast('商城设置已保存'); return load();
      }
      if (action === 'rules-save') {
        await api('/malladmin', { method: 'POST', body: { action: 'settings.save', settings: {
          autoConfirmDays: Number($('autoConfirmDays').value) || 0,
          unpaidTimeoutMinutes: Number($('unpaidTimeoutMinutes').value) || 30,
          stockPolicy: $('stockPolicy').value,
          servicePhone: $('servicePhone').value,
          serviceHours: $('serviceHours').value,
          orderNote: $('orderNote').value
        }}});
        toast('交易规则已保存'); return load();
      }
      if (action === 'orders-export') {
        const rows = filteredOrders(VIEW === 'fulfillment');
        const body = rows.map((o) => [o.id, o.buyer, o.total, o.status, o.at, o.address].join('\t')).join('\n');
        const blob = new Blob([body], { type: 'text/tab-separated-values;charset=utf-8' });
        const a = document.createElement('a');
        a.href = URL.createObjectURL(blob);
        a.download = 'mall-orders-' + Date.now() + '.tsv';
        a.click();
        URL.revokeObjectURL(a.href);
      }
    } catch (err) {
      toast(err.message || String(err), true);
    }
  });

  $('loginForm').addEventListener('submit', async (e) => {
    e.preventDefault();
    $('loginError').textContent = '';
    try {
      const r = await api('/login', { method: 'POST', body: {
        username: $('loginUser').value.trim(), password: $('loginPass').value
      }});
      showApp(r.admin);
      await load();
    } catch (err) {
      $('loginError').textContent = err.message;
    }
  });
  $('logout').addEventListener('click', async () => {
    try { await api('/logout', { method: 'POST' }); } catch (_) {}
    location.reload();
  });
  $('refresh').addEventListener('click', load);
  $('menuToggle').addEventListener('click', () => document.body.classList.toggle('menu-open'));
  document.querySelectorAll('#nav button').forEach((b) => b.addEventListener('click', () => go(b.dataset.view)));
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') closeModal();
    if (e.key.toLowerCase() === 'r' && (e.metaKey || e.ctrlKey)) {
      e.preventDefault();
      load();
    }
  });
  boot();
})();
