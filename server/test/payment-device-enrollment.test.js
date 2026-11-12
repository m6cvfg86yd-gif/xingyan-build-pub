'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { canonical } = require('../lib/shard-snapshot');
const { PaymentTokenVault } = require('../lib/payment-token-vault');
const { PaymentDeviceEnrollment } = require('../lib/payment-device-enrollment');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-payment-enrollment-'));

try {
  let sequence = 0;
  const vault = new PaymentTokenVault({
    file: path.join(root, 'tokens.json'),
    now: () => '2026-11-13T03:00:00.000Z'
  });
  const enrollment = new PaymentDeviceEnrollment({
    tokens: vault,
    uid: (prefix) => prefix + '-' + String(++sequence).padStart(8, '0'),
    now: () => '2026-11-13T03:00:00.000Z',
    ttlMs: 120000
  });

  for (const type of ['ed25519', 'ec']) {
    const options = type === 'ec'
      ? { namedCurve: 'prime256v1' }
      : undefined;
    const pair = crypto.generateKeyPairSync(type, options);
    const publicKey = pair.publicKey.export({ format: 'pem', type: 'spki' }).toString();
    const started = enrollment.begin({
      userId: 'enroll-user',
      deviceId: 'device-' + type,
      publicKey
    });
    const payload = {
      purpose: 'payment-device-enrollment',
      challenge: started.challenge,
      tokenId: started.tokenId,
      userId: 'enroll-user',
      deviceId: 'device-' + type,
      publicKey
    };
    const signature = type === 'ec'
      ? crypto.sign('sha256', Buffer.from(canonical(payload)), pair.privateKey).toString('base64')
      : crypto.sign(null, Buffer.from(canonical(payload)), pair.privateKey).toString('base64');
    const token = enrollment.finish({
      challenge: started.challenge,
      signature,
      last4: '4242'
    });
    assert.strictEqual(token.tokenId, started.tokenId);
    assert.strictEqual(token.deviceId, 'device-' + type);
    assert.throws(() => enrollment.finish({
      challenge: started.challenge,
      signature
    }), /invalid or expired/);

    const authorization = {
      userId: 'enroll-user',
      deviceId: 'device-' + type,
      amountCents: 100,
      currency: 'CNY'
    };
    const authSignature = type === 'ec'
      ? crypto.sign('sha256', Buffer.from(canonical(authorization)), pair.privateKey)
      : crypto.sign(null, Buffer.from(canonical(authorization)), pair.privateKey);
    assert.strictEqual(vault.verifyAuthorization(
      started.tokenId,
      authorization,
      authSignature.toString('base64')
    ).ok, true);
  }

  console.log('payment-device-enrollment: passed');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
