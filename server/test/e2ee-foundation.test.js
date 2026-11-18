'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const {
  createE2EEFoundation,
  SIGNED_PREKEY_DOMAIN
} = require('../lib/e2ee-foundation');

function base64url(buffer) {
  return Buffer.from(buffer).toString('base64url');
}

function rawKey(type) {
  const pair = crypto.generateKeyPairSync(type);
  const jwk = pair.publicKey.export({ format: 'jwk' });
  return {
    privateKey: pair.privateKey,
    raw: Buffer.from(jwk.x, 'base64url')
  };
}

function deviceRegistration(deviceId, preKeyCount = 2) {
  const identity = rawKey('x25519');
  const signing = rawKey('ed25519');
  const signedPreKey = rawKey('x25519');
  const signedSignature = crypto.sign(
    null,
    Buffer.concat([SIGNED_PREKEY_DOMAIN, signedPreKey.raw]),
    signing.privateKey
  );
  return {
    deviceId,
    identityKey: base64url(identity.raw),
    signingKey: base64url(signing.raw),
    signedPreKey: {
      id: 11,
      publicKey: base64url(signedPreKey.raw),
      signature: base64url(signedSignature)
    },
    oneTimePreKeys: Array.from({ length: preKeyCount }, (_, index) => ({
      id: index + 101,
      publicKey: base64url(rawKey('x25519').raw)
    })),
    privateKey: 'must-never-be-stored'
  };
}

async function main() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-e2ee-foundation-'));
  try {
    const disabled = createE2EEFoundation({ dataDir, enabled: false });
    assert.throws(
      () => disabled.registerDevice('u1', deviceRegistration('phone')),
      /disabled/
    );

    const store = createE2EEFoundation({ dataDir, enabled: true });
    const alice = store.registerDevice('u_alice', deviceRegistration('alice-phone'));
    assert.strictEqual(alice.deviceId, 'alice-phone');
    assert.ok(alice.identityKey);
    assert.strictEqual(Object.prototype.hasOwnProperty.call(alice, 'privateKey'), false);

    const bobInput = deviceRegistration('bob-phone', 3);
    store.registerDevice('u_bob', bobInput);
    const bundle = store.bundle('u_bob', 'bob-phone');
    assert.strictEqual(bundle.protocolVersion, 1);
    assert.strictEqual(Object.prototype.hasOwnProperty.call(bundle, 'privateKey'), false);
    assert.strictEqual(bundle.oneTimePreKey, null);

    const claimedFirst = store.claimOneTimePreKey('u_bob', 'bob-phone');
    const claimedSecond = store.claimOneTimePreKey('u_bob', 'bob-phone');
    assert.ok(claimedFirst.oneTimePreKey);
    assert.ok(claimedSecond.oneTimePreKey);
    assert.notStrictEqual(
      claimedFirst.oneTimePreKey.id,
      claimedSecond.oneTimePreKey.id
    );

    const invalid = deviceRegistration('invalid-device', 1);
    invalid.signedPreKey.signature = base64url(Buffer.alloc(64, 7));
    assert.throws(
      () => store.registerDevice('u_bad', invalid),
      /signature/
    );

    const ciphertext = {
      version: 1,
      sessionId: 'session-bootstrap',
      header: { ephemeralKey: base64url(Buffer.alloc(32, 2)) },
      nonce: base64url(Buffer.alloc(12, 3)),
      ciphertext: base64url(Buffer.alloc(64, 4))
    };
    const posted = store.putEnvelope('u_alice', 'alice-phone', {
      recipientUserId: 'u_bob',
      recipientDeviceId: 'bob-phone',
      envelope: ciphertext
    });
    assert.ok(posted.id);

    const reopened = createE2EEFoundation({ dataDir, enabled: true });
    const queued = reopened.listEnvelopes('u_bob', 'bob-phone', '');
    assert.strictEqual(queued.length, 1);
    assert.strictEqual(queued[0].fromUserId, 'u_alice');
    assert.deepStrictEqual(queued[0].envelope, ciphertext);
    assert.strictEqual(reopened.acknowledgeEnvelopes('u_bob', 'bob-phone', [posted.id]), 1);
    assert.strictEqual(reopened.listEnvelopes('u_bob', 'bob-phone', '').length, 0);

    const persisted = JSON.parse(fs.readFileSync(
      path.join(dataDir, 'e2ee-foundation.json'),
      'utf8'
    ));
    assert.ok(persisted.devices.u_bob['bob-phone']);
    assert.strictEqual(JSON.stringify(persisted).includes('must-never-be-stored'), false);
    console.log('e2ee-foundation: passed');
  } finally {
    fs.rmSync(dataDir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
