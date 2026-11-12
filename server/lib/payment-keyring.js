'use strict';

const crypto = require('crypto');
const { canonical } = require('./shard-snapshot');

class PaymentKeyRing {
  constructor(options) {
    const opts = options || {};
    this.keys = new Map();
    this.activeKeyId = String(opts.activeKeyId || '');
    for (const row of opts.keys || []) {
      this.add(row.id, row.secret, row.active === true);
    }
    if (!this.activeKeyId) this.activeKeyId = String(opts.activeKeyId || '');
    if (!this.keys.has(this.activeKeyId)) {
      throw new Error('active payment signing key is required');
    }
  }

  add(id, secret, active) {
    const keyId = String(id || '');
    if (!/^[A-Za-z0-9._:-]{3,80}$/.test(keyId)) throw new Error('invalid payment key id');
    const value = Buffer.isBuffer(secret) ? Buffer.from(secret) : Buffer.from(String(secret || ''), 'base64');
    if (value.length < 32) throw new Error('payment signing key must be at least 32 bytes');
    this.keys.set(keyId, value);
    if (active) this.activeKeyId = keyId;
  }

  rotate(id, secret) {
    this.add(id, secret, true);
    return this.activeKeyId;
  }

  sign(payload) {
    const key = this.keys.get(this.activeKeyId);
    if (!key) throw new Error('active payment signing key is unavailable');
    return {
      alg: 'HMAC-SHA256',
      keyId: this.activeKeyId,
      value: crypto.createHmac('sha256', key).update(canonical(payload)).digest('base64')
    };
  }

  verify(payload, signature) {
    const row = signature || {};
    const key = this.keys.get(String(row.keyId || ''));
    if (!key || row.alg !== 'HMAC-SHA256' || !row.value) return false;
    const expected = this.signWithKey(key, payload);
    const actual = Buffer.from(String(row.value), 'base64');
    return expected.length === actual.length && crypto.timingSafeEqual(expected, actual);
  }

  signWithKey(key, payload) {
    return crypto.createHmac('sha256', key).update(canonical(payload)).digest();
  }
}

module.exports = { PaymentKeyRing };
