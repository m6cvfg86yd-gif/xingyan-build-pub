'use strict';

const crypto = require('crypto');
const { canonical } = require('./shard-snapshot');

function verifyDeviceSignature(publicKey, payload, signature) {
  const key = crypto.createPublicKey(publicKey);
  const data = Buffer.from(canonical(payload), 'utf8');
  const raw = Buffer.from(String(signature || ''), 'base64');
  if (!raw.length) return false;
  try {
    if (key.asymmetricKeyType === 'ed25519' || key.asymmetricKeyType === 'ed448') {
      return crypto.verify(null, data, key, raw);
    }
    return crypto.verify('sha256', data, key, raw);
  } catch (_) {
    return false;
  }
}

class PaymentDeviceEnrollment {
  constructor(options) {
    const opts = options || {};
    this.tokens = opts.tokens;
    this.uid = opts.uid;
    this.now = typeof opts.now === 'function' ? opts.now : () => new Date().toISOString();
    this.ttlMs = Math.max(30000, Number(opts.ttlMs) || 120000);
    if (!this.tokens || typeof this.tokens.enroll !== 'function') {
      throw new Error('payment token vault is required');
    }
    if (typeof this.uid !== 'function') throw new Error('uid generator is required');
    this.challenges = new Map();
  }

  prune() {
    const at = Date.now();
    for (const [id, value] of this.challenges.entries()) {
      if (value.expiresAtMs <= at) this.challenges.delete(id);
    }
  }

  begin(input) {
    this.prune();
    const row = input || {};
    const userId = String(row.userId || '');
    const deviceId = String(row.deviceId || '');
    const publicKey = String(row.publicKey || '');
    if (!userId || !deviceId) throw new Error('user and device are required');
    if (publicKey.length < 64 || publicKey.length > 4096) throw new Error('invalid device public key');
    try { crypto.createPublicKey(publicKey); }
    catch (_) { throw new Error('invalid device public key'); }
    const challenge = crypto.randomBytes(32).toString('base64url');
    const tokenId = this.uid('ptk');
    const expiresAtMs = Date.now() + this.ttlMs;
    this.challenges.set(challenge, {
      tokenId,
      userId,
      deviceId,
      publicKey,
      createdAt: this.now(),
      expiresAtMs
    });
    return {
      challenge,
      tokenId,
      expiresAt: new Date(expiresAtMs).toISOString()
    };
  }

  finish(input) {
    this.prune();
    const row = input || {};
    const challenge = String(row.challenge || '');
    const pending = this.challenges.get(challenge);
    if (!pending) throw new Error('device enrollment challenge is invalid or expired');
    const payload = {
      purpose: 'payment-device-enrollment',
      challenge,
      tokenId: pending.tokenId,
      userId: pending.userId,
      deviceId: pending.deviceId,
      publicKey: pending.publicKey
    };
    if (!verifyDeviceSignature(pending.publicKey, payload, row.signature)) {
      throw new Error('device enrollment signature is invalid');
    }
    const token = this.tokens.enroll({
      tokenId: pending.tokenId,
      userId: pending.userId,
      deviceId: pending.deviceId,
      publicKey: pending.publicKey,
      network: 'xingyan-internal',
      last4: String(row.last4 || '').replace(/\D/g, '').slice(-4)
    });
    this.challenges.delete(challenge);
    return token;
  }

  revoke(tokenId, userId) {
    return this.tokens.revoke(tokenId, userId);
  }
}

module.exports = {
  verifyDeviceSignature,
  PaymentDeviceEnrollment
};
