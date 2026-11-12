'use strict';

const https = require('https');

function appleValidationHost(hostname) {
  const host = String(hostname || '').toLowerCase();
  return host === 'apple-pay-gateway.apple.com'
    || host === 'apple-pay-gateway-cert.apple.com'
    || /^apple-pay-gateway(?:-[a-z0-9-]+)?\.apple\.com$/.test(host);
}

function validateMerchantUrl(value) {
  const url = new URL(String(value || ''));
  if (url.protocol !== 'https:' || !appleValidationHost(url.hostname)) {
    throw new Error('untrusted Apple Pay validation URL');
  }
  return url;
}

function defaultRequest(options, body) {
  return new Promise((resolve, reject) => {
    const req = https.request(Object.assign({}, options, {
      method: 'POST',
      headers: Object.assign({
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body)
      }, options.headers || {})
    }), (res) => {
      const chunks = [];
      res.on('data', (chunk) => chunks.push(chunk));
      res.on('end', () => {
        const text = Buffer.concat(chunks).toString('utf8');
        let json = null;
        try { json = text ? JSON.parse(text) : null; } catch (_) { json = null; }
        resolve({ statusCode: res.statusCode, headers: res.headers, body: json, raw: text });
      });
    });
    req.on('error', reject);
    req.setTimeout(10000, () => req.destroy(new Error('Apple Pay validation timeout')));
    req.end(body);
  });
}

class ApplePayMerchantProvider {
  constructor(options) {
    const opts = options || {};
    this.merchantIdentifier = String(opts.merchantIdentifier || '');
    this.domainName = String(opts.domainName || '');
    this.displayName = String(opts.displayName || '');
    this.cert = opts.cert || null;
    this.key = opts.key || null;
    this.request = typeof opts.request === 'function' ? opts.request : defaultRequest;
  }

  available() {
    return !!(this.merchantIdentifier && this.domainName && this.cert && this.key);
  }

  async createSession(validationURL) {
    if (!this.available()) throw new Error('Apple Pay merchant provider is not configured');
    const url = validateMerchantUrl(validationURL);
    const payload = JSON.stringify({
      merchantIdentifier: this.merchantIdentifier,
      displayName: this.displayName || this.domainName,
      domainName: this.domainName,
      initiative: 'web',
      initiativeContext: this.domainName
    });
    const response = await this.request({
      protocol: 'https:',
      hostname: url.hostname,
      port: url.port || 443,
      path: url.pathname + url.search,
      cert: this.cert,
      key: this.key,
      headers: { Accept: 'application/json' }
    }, payload);
    if (!response || response.statusCode !== 200 || !response.body) {
      throw new Error('Apple Pay merchant validation failed');
    }
    return response.body;
  }
}

function validateApplePayToken(token) {
  const row = token || {};
  if (row.number || row.pan || row.cvv || row.expiry) {
    throw new Error('raw card data is forbidden');
  }
  const paymentData = row.paymentData;
  const validPaymentData = typeof paymentData === 'string'
    ? paymentData.length > 0
    : !!(paymentData && typeof paymentData === 'object'
      && typeof paymentData.data === 'string'
      && typeof paymentData.signature === 'string'
      && paymentData.header && typeof paymentData.header === 'object'
      && paymentData.version);
  if (!row.transactionIdentifier || !validPaymentData) {
    throw new Error('invalid Apple Pay payment token');
  }
  if (row.paymentMethod && row.paymentMethod.type !== 'debit'
      && row.paymentMethod.type !== 'credit') {
    throw new Error('unsupported Apple Pay payment method');
  }
  return row;
}

class ApplePayNetworkProcessor {
  constructor(options) {
    const opts = options || {};
    this.provider = String(opts.provider || '');
    this.processor = opts.processor || null;
  }

  available() {
    return !!(this.provider && this.processor
      && typeof this.processor.authorize === 'function'
      && typeof this.processor.capture === 'function'
      && typeof this.processor.refund === 'function'
      && typeof this.processor.void === 'function');
  }

  requireProcessor() {
    if (!this.available()) throw new Error('Apple Pay network processor is not connected');
    return this.processor;
  }

  authorize(token, intent) {
    validateApplePayToken(token);
    return this.requireProcessor().authorize(token, intent);
  }

  capture(reference, amountCents, currency) {
    return this.requireProcessor().capture(reference, amountCents, currency);
  }

  refund(reference, amountCents, currency) {
    return this.requireProcessor().refund(reference, amountCents, currency);
  }

  void(reference) {
    return this.requireProcessor().void(reference);
  }
}

module.exports = {
  appleValidationHost,
  validateMerchantUrl,
  validateApplePayToken,
  ApplePayMerchantProvider,
  ApplePayNetworkProcessor
};
