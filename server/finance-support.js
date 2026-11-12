'use strict';

const fs = require('fs');
const path = require('path');

const FINANCE_CATEGORIES = [
  {
    id: 'transfer',
    title: '转账与收款',
    items: [
      { q: '转账一直没到账怎么办？', a: '先打开这笔转账的详情确认状态。待收款超过 24 小时会原路退回；如果显示已收款但余额未更新，可以直接转金融客服人工核查。' },
      { q: '转错人了能撤回吗？', a: '对方尚未收款时可在转账详情中退还；对方已经收款时需要联系对方协商。涉及争议可转金融客服人工协助。' }
    ]
  },
  {
    id: 'deduction',
    title: '扣款与账单',
    items: [
      { q: '为什么有一笔我不认识的扣款？', a: '请在账单中打开对应交易，核对时间、金额和交易单号。疑似盗刷时立即联系金融客服，不要向任何人提供验证码或支付密码。' },
      { q: '账单余额和零钱不一致怎么办？', a: '先下拉刷新并查看最新流水。如果仍然不一致，转金融客服人工核查，系统会保留账本证据。' }
    ]
  },
  {
    id: 'refund',
    title: '退款与退回',
    items: [
      { q: '退款多久到账？', a: '退款会原路退回。零钱通常即时到账，银行卡到账时间以发卡行处理为准；超过页面提示时间仍未到账可转人工。' },
      { q: '红包过期后钱去哪了？', a: '未领取金额会退回付款方零钱，可在账单中查看退回记录。' }
    ]
  },
  {
    id: 'risk',
    title: '风控与账户限制',
    items: [
      { q: '为什么提示支付受限？', a: '交易可能因实名认证、账户安全或反洗钱规则进入核查。请按页面提示处理；需要申诉时直接转金融客服人工复核。' },
      { q: '实名认证失败怎么办？', a: '确认姓名、证件号和本人信息一致，并检查证件是否在有效期内。连续失败可转金融客服人工协助。' }
    ]
  }
];

const ISSUE_RULES = [
  {
    category: '账户安全',
    priority: 'critical',
    slaMinutes: 15,
    test: /盗刷|被骗|诈骗|不是本人|陌生转账|陌生扣款|验证码|支付密码|屏幕共享|远程控制|账号被盗/i
  },
  {
    category: '资金未到账',
    priority: 'high',
    slaMinutes: 30,
    test: /没到账|未到账|没收到|未收到|扣款|双扣|重复扣|少钱|余额不对|钱不见|转账异常|退款不到/i
  },
  {
    category: '转错与交易争议',
    priority: 'high',
    slaMinutes: 60,
    test: /转错|错转|发错人|对方不退|交易争议|订单争议|付款争议/i
  },
  {
    category: '账户限制',
    priority: 'high',
    slaMinutes: 60,
    test: /冻结|限制|风控|反洗钱|实名失败|支付受限|账户异常/i
  },
  {
    category: '红包与退款',
    priority: 'normal',
    slaMinutes: 240,
    test: /红包|退款|退回|过期/i
  }
];

function classifyFinanceIssue(text) {
  const body = String(text || '').trim();
  for (const rule of ISSUE_RULES) {
    if (rule.test.test(body)) {
      return {
        category: rule.category,
        priority: rule.priority,
        slaMinutes: rule.slaMinutes,
        needsHuman: true
      };
    }
  }
  return {
    category: '支付咨询',
    priority: 'normal',
    slaMinutes: 240,
    needsHuman: /人工|客服|专员|投诉|申诉/.test(body)
  };
}

function sanitizeReference(value) {
  const text = String(value || '').trim();
  if (!text) return '';
  if (/^(?:tr_|led_|rp_|tk_|tk)[A-Za-z0-9_-]{2,80}$/.test(text)) return text.slice(0, 88);
  if (/^[A-Za-z0-9_-]{4,80}$/.test(text)) return text;
  return '';
}

class FinanceSupportStore {
  constructor(options) {
    this.dataDir = options.dataDir;
    this.fileName = options.fileName || 'finance-support-events.jsonl';
    this.sealValue = options.sealValue;
    this.openSealed = options.openSealed;
    this.uid = options.uid;
    this.now = options.now;
  }

  filePath() {
    return path.join(this.dataDir, this.fileName);
  }

  appendEvent(type, ticketId, actor, data) {
    const event = {
      id: this.uid('fse'),
      ticketId: String(ticketId || ''),
      type: String(type || 'event'),
      actor: String(actor || 'system'),
      at: this.now(),
      data: data && typeof data === 'object' ? data : {}
    };
    const line = JSON.stringify(this.sealValue(this.fileName, event)) + '\n';
    fs.mkdirSync(this.dataDir, { recursive: true });
    const fd = fs.openSync(this.filePath(), 'a');
    try {
      fs.writeSync(fd, line, null, 'utf8');
      fs.fsyncSync(fd);
    } finally {
      fs.closeSync(fd);
    }
    return event;
  }

  readEvents() {
    try {
      return fs.readFileSync(this.filePath(), 'utf8')
        .split('\n')
        .filter((line) => line.trim())
        .map((line) => {
          try { return this.openSealed(this.fileName, JSON.parse(line)); }
          catch (_) { return null; }
        })
        .filter(Boolean);
    } catch (_) {
      return [];
    }
  }

  projectTickets(events) {
    const tickets = new Map();
    for (const event of events || []) {
      if (!event || !event.ticketId) continue;
      if (event.type === 'created') {
        tickets.set(event.ticketId, Object.assign({}, event.data, {
          id: event.ticketId,
          kind: 'finance',
          timeline: []
        }));
      }
      const ticket = tickets.get(event.ticketId);
      if (!ticket) continue;
      if (event.type !== 'created') Object.assign(ticket, event.data || {});
      ticket.updatedAt = event.at || ticket.updatedAt || ticket.createdAt || '';
      ticket.timeline = Array.isArray(ticket.timeline) ? ticket.timeline : [];
      ticket.timeline.push({
        id: event.id,
        type: event.type,
        actor: event.actor,
        at: event.at
      });
      ticket.timeline = ticket.timeline.slice(-80);
    }
    return Array.from(tickets.values());
  }

  tickets(limit, userId) {
    let rows = this.projectTickets(this.readEvents());
    if (userId) rows = rows.filter((ticket) => ticket.userId === userId);
    return rows
      .sort((a, b) => String(b.updatedAt || b.createdAt || '').localeCompare(String(a.updatedAt || a.createdAt || '')))
      .slice(0, Math.max(1, Number(limit) || 50));
  }

  find(id) {
    return this.tickets(1000).find((ticket) => ticket.id === id) || null;
  }

  ensure(user, input) {
    const userId = String(user && user.id || '');
    if (!userId) throw new Error('金融客服工单缺少用户');
    const open = this.tickets(200, userId)
      .find((ticket) => ticket.status !== 'done'
        && Date.now() - Date.parse(ticket.updatedAt || ticket.createdAt || 0) < 24 * 60 * 60 * 1000);
    if (open) return open;

    const issue = classifyFinanceIssue(input && input.content);
    const createdAt = this.now();
    const id = this.uid('ftk');
    const ticket = {
      id,
      userId,
      username: String(user.username || ''),
      nickname: String(user.nickname || ''),
      category: String(input && input.category || issue.category).slice(0, 40),
      title: String(input && input.title || issue.category).slice(0, 80),
      content: String(input && input.content || '').slice(0, 1000),
      contact: String(input && input.contact || '').slice(0, 80),
      reference: sanitizeReference(input && input.reference),
      priority: issue.priority,
      slaMinutes: issue.slaMinutes,
      status: 'pending',
      humanRequested: !!issue.needsHuman,
      assignedTo: '',
      reply: '',
      createdAt,
      updatedAt: createdAt,
      repliedAt: '',
      doneAt: '',
      dueAt: new Date(Date.now() + issue.slaMinutes * 60000).toISOString(),
      source: String(input && input.source || 'finance_chat').slice(0, 30)
    };
    this.appendEvent('created', id, 'customer', ticket);
    return this.projectTickets(this.readEvents()).find((row) => row.id === id) || Object.assign({}, ticket, { kind: 'finance', timeline: [] });
  }

  touch(ticket, patch, type, actor) {
    if (!ticket || !ticket.id) return null;
    const next = Object.assign({}, patch || {}, { updatedAt: this.now() });
    this.appendEvent(type || 'updated', ticket.id, actor || 'system', next);
    return this.find(ticket.id);
  }
}

function financeReply(options) {
  const category = String(options.category || '支付咨询');
  const priority = String(options.priority || 'normal');
  const ticketId = String(options.ticketId || '');
  const offDuty = !!options.offDuty;
  const workTime = String(options.workTime || '金融客服 09:00 - 22:00');

  if (priority === 'critical') {
    return [
      '先停止继续转账，也不要向任何人提供验证码、支付密码，或开启屏幕共享。',
      '已为你建立资金安全工单 ' + ticketId + '，优先级为最高。',
      '金融客服人工专员会按安全事件流程接手；你现在只需补充交易时间和金额。'
    ].join('\n');
  }
  if (priority === 'high') {
    const tail = offDuty
      ? '当前不在人工值班时段，工单已进入队列，值班后会优先处理。'
      : '已转入金融客服人工队列，请保持会话畅通。';
    return [
      '这笔' + category + '已记录，不需要重复提交。',
      '工单 ' + ticketId + ' 已进入人工核查，系统会核对交易流水和账本记录。',
      tail
    ].join('\n');
  }
  if (options.needsHuman) {
    return [
      '已为你建立金融客服工单 ' + ticketId + '。',
      offDuty ? '当前不在人工值班时段，问题已保留，值班后会继续处理。' : '人工专员会在这里继续回复。',
      '请只提供交易时间、金额和单号，不要发送完整银行卡号或密码。'
    ].join('\n');
  }
  const answer = financeSelfServiceAnswer(options.text);
  if (answer) {
    return [
      answer,
      '本次咨询已记录为 ' + ticketId + '。',
      '如果涉及实际扣款、到账或退款，请直接回复「转人工」。'
    ].join('\n');
  }
  return [
    '这是可自助处理的问题，本次咨询已记录为 ' + ticketId + '。',
    '如果涉及实际扣款、到账或退款，请直接回复「转人工」。',
    '人工在线时间：' + workTime + '。'
  ].join('\n');
}

function financeSelfServiceAnswer(text) {
  const body = String(text || '');
  if (/怎么充值|如何充值|充值入口/.test(body)) {
    return '充值路径：「我」→「服务」→「钱包」→「零钱」→「充值」，选择银行卡并输入金额。';
  }
  if (/提现入口|怎么提现|如何提现/.test(body)) {
    return '提现路径：「我」→「服务」→「钱包」→「零钱」→「提现」。到账时间以银行卡处理为准。';
  }
  if (/退款多久|退款时间/.test(body)) {
    return '零钱退款通常即时到账；银行卡退款到账时间以发卡行处理为准。';
  }
  if (/红包.*过期|过期.*红包/.test(body)) {
    return '红包过期后，未领取金额会原路退回付款方零钱，可在「账单」中查看。';
  }
  if (/账单在哪|怎么看账单|查看账单/.test(body)) {
    return '账单路径：「我」→「服务」→「钱包」→「账单」，每一笔收支都带时间和交易单号。';
  }
  if (/实名入口|怎么实名|如何实名/.test(body)) {
    return '实名认证路径：「我」→「设置」→「账号与安全」→「实名认证」。';
  }
  if (/支付密码.*改|改.*支付密码|重置支付密码/.test(body)) {
    return '支付密码路径：「我」→「设置」→「支付密码」。客服不会向你索要支付密码。';
  }
  if (/转账.*24小时|多久退回|自动退回/.test(body)) {
    return '对方 24 小时内未收款，转账会自动原路退回；退款记录可在账单中查看。';
  }
  return '';
}

module.exports = {
  FINANCE_CATEGORIES,
  FinanceSupportStore,
  classifyFinanceIssue,
  financeReply,
  financeSelfServiceAnswer,
  sanitizeReference
};
