'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const STORE_FILE = 'e2ee-foundation.json';
const VERSION = 1;
const SIGNED_PREKEY_DOMAIN = Buffer.from('xingyan-e2ee-spk-v1', 'utf8');
const MAX_ONE_TIME_PREKEYS = 200;
const MAX_ENVELOPES = 500;
const MAX_ENVELOPE_BYTES = 128 * 1024;

function foundationError(code, message) {
  const error = new Error(message);
  error.code = code;
  return error;
}

function cleanId(value, field) {
  const text = String(value || '').trim();
  if (!/^[A-Za-z0-9._:-]{1,100}$/.test(text)) {
    throw foundationError('invalid-' + field, field + ' is invalid');
  }
  return text;
}

function publicKey(value, field) {
  const text = String(value || '').trim();
  if (!/^[A-Za-z0-9_-]{43}$/.test(text)) {
    throw foundationError('invalid-' + field, field + ' must be a 32-byte base64url key');
  }
  const raw = Buffer.from(text, 'base64url');
  if (raw.length !== 32 || raw.toString('base64url') !== text) {
    throw foundationError('invalid-' + field, field + ' must be canonical base64url');
  }
  return text;
}

function signature(value) {
  const text = String(value || '').trim();
  if (!/^[A-Za-z0-9_-]{86}$/.test(text)) {
    throw foundationError('invalid-signature', 'signed prekey signature must be 64 bytes');
  }
  const raw = Buffer.from(text, 'base64url');
  if (raw.length !== 64 || raw.toString('base64url') !== text) {
    throw foundationError('invalid-signature', 'signed prekey signature must be canonical base64url');
  }
  return text;
}

function verifySignedPreKey(signingPublicKey, signedPreKey, signedPreKeySignature) {
  try {
    const key = crypto.createPublicKey({
      key: {
        kty: 'OKP',
        crv: 'Ed25519',
        x: Buffer.from(signingPublicKey, 'base64url').toString('base64url')
      },
      format: 'jwk'
    });
    const message = Buffer.concat([
      SIGNED_PREKEY_DOMAIN,
      Buffer.from(signedPreKey, 'base64url')
    ]);
    return crypto.verify(
      null,
      message,
      key,
      Buffer.from(signedPreKeySignature, 'base64url')
    );
  } catch (_) {
    return false;
  }
}

function createE2EEFoundation(options) {
  const opts = options || {};
  const dataDir = path.resolve(opts.dataDir || '');
  const enabled = opts.enabled === true;
  const storeFile = dataDir ? path.join(dataDir, STORE_FILE) : '';
  let store = null;

  function emptyStore() {
    return { version: VERSION, devices: {}, envelopes: {} };
  }

  function load() {
    if (store) return store;
    if (!dataDir) {
      store = emptyStore();
      return store;
    }
    try {
      const parsed = JSON.parse(fs.readFileSync(storeFile, 'utf8'));
      store = parsed && parsed.version === VERSION
        && parsed.devices && typeof parsed.devices === 'object'
        && parsed.envelopes && typeof parsed.envelopes === 'object'
        ? parsed
        : emptyStore();
    } catch (_) {
      store = emptyStore();
    }
    return store;
  }

  function save() {
    if (!dataDir) return;
    fs.mkdirSync(dataDir, { recursive: true, mode: 0o700 });
    const temporary = storeFile + '.' + process.pid + '.tmp';
    fs.writeFileSync(temporary, JSON.stringify(load()), {
      encoding: 'utf8',
      mode: 0o600
    });
    fs.renameSync(temporary, storeFile);
  }

  function requireEnabled() {
    if (!enabled) {
      throw foundationError('feature-disabled', 'E2EE foundation is disabled');
    }
  }

  function sanitizeSignedPreKey(raw) {
    const value = raw && typeof raw === 'object' ? raw : {};
    const id = Math.max(1, Math.floor(Number(value.id) || 0));
    if (!id) throw foundationError('invalid-signed-prekey-id', 'signed prekey id is required');
    const key = publicKey(value.publicKey, 'signed-prekey');
    const sig = signature(value.signature);
    return { id, publicKey: key, signature: sig };
  }

  function sanitizeOneTimePreKeys(raw) {
    const rows = Array.isArray(raw) ? raw : [];
    const output = [];
    const seen = new Set();
    for (const item of rows.slice(0, MAX_ONE_TIME_PREKEYS)) {
      if (!item || typeof item !== 'object') continue;
      const id = Math.max(1, Math.floor(Number(item.id) || 0));
      if (!id || seen.has(id)) continue;
      seen.add(id);
      output.push({
        id,
        publicKey: publicKey(item.publicKey, 'one-time-prekey')
      });
    }
    return output;
  }

  function sanitizeDevice(userId, raw) {
    const input = raw && typeof raw === 'object' ? raw : {};
    const deviceId = cleanId(input.deviceId, 'device-id');
    const identityKey = publicKey(input.identityKey, 'identity-key');
    const signingKey = publicKey(input.signingKey, 'signing-key');
    const signedPreKey = sanitizeSignedPreKey(input.signedPreKey);
    if (!verifySignedPreKey(signingKey, signedPreKey.publicKey, signedPreKey.signature)) {
      throw foundationError('invalid-signed-prekey-signature', 'signed prekey signature is invalid');
    }
    return {
      userId,
      deviceId,
      identityKey,
      signingKey,
      signedPreKey,
      oneTimePreKeys: sanitizeOneTimePreKeys(input.oneTimePreKeys),
      protocolVersion: VERSION
    };
  }

  function publicDevice(row) {
    return {
      protocolVersion: VERSION,
      userId: row.userId,
      deviceId: row.deviceId,
      identityKey: row.identityKey,
      signingKey: row.signingKey,
      signedPreKey: {
        id: row.signedPreKey.id,
        publicKey: row.signedPreKey.publicKey,
        signature: row.signedPreKey.signature
      },
      oneTimePreKey: null
    };
  }

  function registerDevice(userId, input) {
    requireEnabled();
    const owner = cleanId(userId, 'user-id');
    const next = sanitizeDevice(owner, input);
    const root = load();
    if (!root.devices[owner]) root.devices[owner] = {};
    const ownerDevices = root.devices[owner];
    if (Object.keys(ownerDevices).length >= 12 && !ownerDevices[next.deviceId]) {
      throw foundationError('device-limit', 'too many devices');
    }
    const current = ownerDevices[next.deviceId];
    if (current) {
      if (current.identityKey !== next.identityKey || current.signingKey !== next.signingKey) {
        throw foundationError(
          'identity-change-requires-reenrollment',
          'existing device identity cannot be replaced in-place'
        );
      }
      const byId = new Map(
        (current.oneTimePreKeys || []).map((row) => [Number(row.id), row])
      );
      for (const row of next.oneTimePreKeys) {
        byId.set(Number(row.id), row);
      }
      next.oneTimePreKeys = Array.from(byId.values())
        .sort((a, b) => a.id - b.id)
        .slice(-MAX_ONE_TIME_PREKEYS);
      next.registeredAt = current.registeredAt;
    } else {
      next.registeredAt = new Date().toISOString();
    }
    next.updatedAt = new Date().toISOString();
    ownerDevices[next.deviceId] = next;
    save();
    return publicDevice(next);
  }

  function bundle(userId, deviceId) {
    requireEnabled();
    const owner = cleanId(userId, 'user-id');
    const root = load();
    const devices = root.devices[owner] || {};
    const wanted = deviceId
      ? cleanId(deviceId, 'device-id')
      : Object.keys(devices).sort()[0];
    const row = wanted ? devices[wanted] : null;
    if (!row) throw foundationError('device-not-found', 'E2EE device not found');
    return publicDevice(row);
  }

  function claimOneTimePreKey(userId, deviceId) {
    requireEnabled();
    const owner = cleanId(userId, 'user-id');
    const device = cleanId(deviceId, 'device-id');
    const root = load();
    const row = root.devices[owner] && root.devices[owner][device];
    if (!row) throw foundationError('device-not-found', 'E2EE device not found');
    const claimed = (row.oneTimePreKeys || []).shift() || null;
    if (claimed) save();
    return Object.assign(publicDevice(row), {
      oneTimePreKey: claimed
    });
  }

  function putEnvelope(fromUserId, fromDeviceId, input) {
    requireEnabled();
    const sender = cleanId(fromUserId, 'sender-user-id');
    const senderDevice = cleanId(fromDeviceId, 'sender-device-id');
    const body = input && typeof input === 'object' ? input : {};
    const recipientUserId = cleanId(body.recipientUserId, 'recipient-user-id');
    const recipientDeviceId = cleanId(body.recipientDeviceId, 'recipient-device-id');
    const envelope = body.envelope && typeof body.envelope === 'object'
      ? body.envelope
      : null;
    if (!envelope || envelope.version !== VERSION) {
      throw foundationError('invalid-envelope', 'E2EE envelope is required');
    }
    const serialized = JSON.stringify(envelope);
    if (Buffer.byteLength(serialized, 'utf8') > MAX_ENVELOPE_BYTES) {
      throw foundationError('envelope-too-large', 'E2EE envelope is too large');
    }
    const root = load();
    const target = root.devices[recipientUserId]
      && root.devices[recipientUserId][recipientDeviceId];
    if (!target) throw foundationError('device-not-found', 'recipient E2EE device not found');
    if (!root.envelopes[recipientUserId]) root.envelopes[recipientUserId] = [];
    const row = {
      id: 'ee_' + crypto.randomBytes(12).toString('hex'),
      fromUserId: sender,
      fromDeviceId: senderDevice,
      recipientDeviceId,
      envelope,
      receivedAt: new Date().toISOString()
    };
    root.envelopes[recipientUserId].push(row);
    if (root.envelopes[recipientUserId].length > MAX_ENVELOPES) {
      root.envelopes[recipientUserId].splice(
        0,
        root.envelopes[recipientUserId].length - MAX_ENVELOPES
      );
    }
    save();
    return { id: row.id, receivedAt: row.receivedAt };
  }

  function listEnvelopes(userId, deviceId, after) {
    requireEnabled();
    const owner = cleanId(userId, 'user-id');
    const device = cleanId(deviceId, 'device-id');
    const cursor = String(after || '');
    const rows = ((load().envelopes[owner] || [])
      .filter((row) => row.recipientDeviceId === device)
      .filter((row) => !cursor || String(row.receivedAt) > cursor));
    return rows.slice(0, 100).map((row) => ({
      id: row.id,
      fromUserId: row.fromUserId,
      fromDeviceId: row.fromDeviceId,
      envelope: row.envelope,
      receivedAt: row.receivedAt
    }));
  }

  function acknowledgeEnvelopes(userId, deviceId, ids) {
    requireEnabled();
    const owner = cleanId(userId, 'user-id');
    const device = cleanId(deviceId, 'device-id');
    const wanted = new Set(
      (Array.isArray(ids) ? ids : []).map((id) => String(id || '')).filter(Boolean)
    );
    if (!wanted.size) return 0;
    const root = load();
    const before = (root.envelopes[owner] || []).length;
    root.envelopes[owner] = (root.envelopes[owner] || []).filter((row) =>
      row.recipientDeviceId !== device || !wanted.has(row.id)
    );
    const removed = before - root.envelopes[owner].length;
    if (removed) save();
    return removed;
  }

  return {
    enabled,
    registerDevice,
    bundle,
    claimOneTimePreKey,
    putEnvelope,
    listEnvelopes,
    acknowledgeEnvelopes
  };
}

module.exports = {
  createE2EEFoundation,
  SIGNED_PREKEY_DOMAIN,
  verifySignedPreKey
};
