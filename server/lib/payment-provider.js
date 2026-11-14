'use strict';

const crypto = require('crypto');
const { stableJson } = require('./sqlite-payment-ledger');

function safeEqualText(left, right) {
  const a = Buffer.from(String(left || ''), 'utf8');
  const b = Buffer.from(String(right || ''), 'utf8');
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

class SignedPaymentProviderBridge {
  constructor(options) {
    const opts = options || {};
    this.name = String(opts.name || '');
    this.baseUrl = String(opts.baseUrl || '').replace(/\/+$/, '');
    this.apiKey = String(opts.apiKey || '');
    this.webhookSecret = String(opts.webhookSecret || '');
    this.now = typeof opts.now === 'function' ? opts.now : () => Date.now();
    this.fetch = typeof opts.fetch === 'function' ? opts.fetch : global.fetch;
  }

  ready() {
    return !!(this.name && this.baseUrl && this.apiKey && this.webhookSecret
      && typeof this.fetch === 'function');
  }

  assertReady() {
    if (!this.ready()) {
      throw new Error('licensed payment provider is not configured');
    }
  }

  requestSignature(timestamp, body) {
    return crypto.createHmac('sha256', this.apiKey)
      .update(String(timestamp) + '\n' + String(body || ''))
      .digest('base64url');
  }

  async request(pathname, payload) {
    this.assertReady();
    const body = stableJson(payload || {});
    const timestamp = String(this.now());
    const response = await this.fetch(this.baseUrl + pathname, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-xingyan-timestamp': timestamp,
        'x-xingyan-signature': this.requestSignature(timestamp, body)
      },
      body
    });
    const text = await response.text();
    let envelope = {};
    try { envelope = text ? JSON.parse(text) : {}; }
    catch (_) { throw new Error('payment provider returned invalid JSON'); }
    if (!response.ok || envelope.ok === false) {
      throw new Error(String(envelope.message || envelope.error
        || ('payment provider HTTP ' + response.status)));
    }
    return envelope.data || envelope;
  }

  async requestGet(pathname) {
    this.assertReady();
    const timestamp = String(this.now());
    const response = await this.fetch(this.baseUrl + pathname, {
      method: 'GET',
      headers: {
        'x-xingyan-timestamp': timestamp,
        'x-xingyan-signature': this.requestSignature(timestamp, '')
      }
    });
    const text = await response.text();
    let envelope = {};
    try { envelope = text ? JSON.parse(text) : {}; }
    catch (_) { throw new Error('payment provider returned invalid JSON'); }
    if (!response.ok || envelope.ok === false) {
      throw new Error(String(envelope.message || envelope.error
        || ('payment provider HTTP ' + response.status)));
    }
    return envelope.data || envelope;
  }

  createDeposit(order) {
    return this.request('/v1/deposits', {
      orderId: order.id,
      amountCents: order.amountCents,
      currency: order.currency,
      userId: order.userId,
      description: '星言零钱充值',
      idempotencyKey: 'deposit:' + order.id
    });
  }

  createPayout(order, bank) {
    return this.request('/v1/payouts', {
      orderId: order.id,
      amountCents: order.amountCents,
      feeCents: order.feeCents,
      currency: order.currency,
      userId: order.userId,
      bank: bank || {},
      description: '星言零钱提现',
      idempotencyKey: 'payout:' + order.id
    });
  }

  async settlementReport(date) {
    const report = await this.requestGet('/v1/settlements?date=' + encodeURIComponent(date));
    return Array.isArray(report) ? report : (Array.isArray(report.lines) ? report.lines : []);
  }

  verifyWebhook(headers, rawBody) {
    this.assertReady();
    const timestamp = String(headers && (
      headers['x-xingyan-timestamp'] || headers['X-Xingyan-Timestamp']
    ) || '');
    const signature = String(headers && (
      headers['x-xingyan-signature'] || headers['X-Xingyan-Signature']
    ) || '');
    const timestampMs = Number(timestamp);
    if (!Number.isFinite(timestampMs)
        || Math.abs(this.now() - timestampMs) > 5 * 60 * 1000) {
      return { ok: false, reason: 'stale-webhook' };
    }
    const body = Buffer.isBuffer(rawBody) ? rawBody.toString('utf8') : String(rawBody || '');
    const expected = crypto.createHmac('sha256', this.webhookSecret)
      .update(timestamp + '\n' + body)
      .digest('base64url');
    return safeEqualText(expected, signature)
      ? { ok: true, body }
      : { ok: false, reason: 'bad-signature' };
  }

  parseWebhook(body) {
    const row = typeof body === 'string' ? JSON.parse(body) : (body || {});
    const providerEventId = String(row.id || row.eventId || '');
    const type = String(row.type || '');
    const data = row.data && typeof row.data === 'object' ? row.data : row;
    const status = String(data.status || '');
    if (!providerEventId || !type) throw new Error('provider webhook identity is missing');
    if (!['deposit', 'payout'].includes(String(data.kind || ''))) {
      throw new Error('provider webhook kind is missing');
    }
    if (!['succeeded', 'failed'].includes(status)) {
      throw new Error('provider webhook status is invalid');
    }
    return {
      providerEventId,
      type,
      kind: String(data.kind),
      orderId: String(data.orderId || ''),
      status,
      providerRef: String(data.providerRef || ''),
      failureCode: String(data.failureCode || ''),
      raw: row
    };
  }
}

function createPaymentProviderFromEnv(env) {
  const source = env || process.env;
  return new SignedPaymentProviderBridge({
    name: source.PAYMENT_PROVIDER_NAME || '',
    baseUrl: source.PAYMENT_PROVIDER_BASE_URL || '',
    apiKey: source.PAYMENT_PROVIDER_API_KEY || '',
    webhookSecret: source.PAYMENT_PROVIDER_WEBHOOK_SECRET || ''
  });
}

module.exports = {
  SignedPaymentProviderBridge,
  createPaymentProviderFromEnv,
  safeEqualText
};
