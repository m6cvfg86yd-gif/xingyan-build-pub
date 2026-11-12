'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { canonical } = require('./shard-snapshot');

class PaymentTokenVault {
  constructor(options) {
    const opts = options || {};
    this.file = String(opts.file || '');
    this.now = typeof opts.now === 'function' ? opts.now : () => new Date().toISOString();
    this.tokens = new Map();
    if (!this.file) throw new Error('payment token vault file is required');
    this.load();
  }

  load() {
    try {
      const row = JSON.parse(fs.readFileSync(this.file, 'utf8'));
      for (const token of row && row.tokens || []) {
        if (token && token.tokenId) this.tokens.set(token.tokenId, token);
      }
    } catch (error) {
      if (error && error.code !== 'ENOENT') {
        throw new Error('payment token vault is corrupt');
      }
    }
  }

  save() {
    fs.mkdirSync(path.dirname(this.file), { recursive: true });
    const temporary = this.file + '.' + process.pid + '.tmp';
    fs.writeFileSync(temporary, JSON.stringify({
      version: 1,
      tokens: Array.from(this.tokens.values())
    }), 'utf8');
    fs.renameSync(temporary, this.file);
  }

  enroll(input) {
    const row = input || {};
    const tokenId = String(row.tokenId || '');
    if (!/^[A-Za-z0-9._:-]{8,128}$/.test(tokenId)) throw new Error('invalid network token id');
    if (this.tokens.has(tokenId)) throw new Error('network token already enrolled');
    if (!row.userId || !row.deviceId) throw new Error('token owner and device are required');
    const publicKey = String(row.publicKey || '');
    if (publicKey.length < 64 || publicKey.length > 4096) throw new Error('invalid device public key');
    try { crypto.createPublicKey(publicKey); }
    catch (_) { throw new Error('invalid device public key'); }
    const token = {
      tokenId,
      userId: String(row.userId),
      deviceId: String(row.deviceId),
      network: String(row.network || 'network-token'),
      last4: String(row.last4 || '').replace(/\D/g, '').slice(-4),
      publicKey,
      status: 'active',
      createdAt: this.now(),
      revokedAt: ''
    };
    this.tokens.set(tokenId, token);
    this.save();
    return Object.assign({}, token);
  }

  revoke(tokenId, userId) {
    const token = this.tokens.get(String(tokenId || ''));
    if (!token || token.userId !== String(userId || '')) throw new Error('network token not found');
    token.status = 'revoked';
    token.revokedAt = this.now();
    this.save();
    return Object.assign({}, token);
  }

  get(tokenId) {
    const token = this.tokens.get(String(tokenId || ''));
    return token ? Object.assign({}, token) : null;
  }

  verifyAuthorization(tokenId, expected, signature) {
    const token = this.tokens.get(String(tokenId || ''));
    if (!token || token.status !== 'active') return { ok: false, reason: 'token-inactive' };
    if (token.userId !== expected.userId || token.deviceId !== expected.deviceId) {
      return { ok: false, reason: 'device-binding-mismatch' };
    }
    const key = crypto.createPublicKey(token.publicKey);
    const valid = crypto.verify(
      null,
      Buffer.from(canonical(expected), 'utf8'),
      key,
      Buffer.from(String(signature || ''), 'base64')
    );
    return valid ? { ok: true, token } : { ok: false, reason: 'invalid-device-signature' };
  }
}

module.exports = { PaymentTokenVault };
