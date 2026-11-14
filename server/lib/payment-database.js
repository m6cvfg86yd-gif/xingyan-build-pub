'use strict';

const crypto = require('crypto');
const { canonical, hash } = require('./shard-snapshot');
const { verifyDeviceSignature } = require('./payment-device-enrollment');
const {
  SqlitePaymentLedger,
  cents,
  money,
  stableJson
} = require('./sqlite-payment-ledger');

function parseJson(value, fallback) {
  try {
    const parsed = JSON.parse(String(value || ''));
    return parsed === undefined ? fallback : parsed;
  } catch (_) {
    return fallback;
  }
}

class PaymentDatabase extends SqlitePaymentLedger {
  constructor(options) {
    super(options);
    const opts = options || {};
    this.keyring = opts.keyring;
    if (!this.keyring) throw new Error('payment intent keyring is required');
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS payment_devices (
        token_id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        device_id TEXT NOT NULL,
        network TEXT NOT NULL,
        last4 TEXT NOT NULL DEFAULT '',
        public_key_pem TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL,
        revoked_at TEXT NOT NULL DEFAULT ''
      );

      CREATE INDEX IF NOT EXISTS payment_devices_user
        ON payment_devices(user_id, status);

      CREATE TABLE IF NOT EXISTS payment_device_challenges (
        challenge TEXT PRIMARY KEY,
        token_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        device_id TEXT NOT NULL,
        public_key_pem TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        used_at TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      );

      CREATE INDEX IF NOT EXISTS payment_device_challenges_expiry
        ON payment_device_challenges(expires_at, used_at);

      CREATE TABLE IF NOT EXISTS payment_intents (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        merchant_id TEXT NOT NULL,
        device_id TEXT NOT NULL,
        amount_cents INTEGER NOT NULL,
        currency TEXT NOT NULL,
        metadata_json TEXT NOT NULL,
        status TEXT NOT NULL,
        version INTEGER NOT NULL,
        token_id TEXT NOT NULL DEFAULT '',
        nonce TEXT NOT NULL DEFAULT '',
        last4 TEXT NOT NULL DEFAULT '',
        refunded_cents INTEGER NOT NULL DEFAULT 0,
        pending_refund_cents INTEGER NOT NULL DEFAULT 0,
        ledger_ref TEXT NOT NULL DEFAULT '',
        settlement_reference TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        authorized_at TEXT NOT NULL DEFAULT '',
        captured_at TEXT NOT NULL DEFAULT '',
        updated_at TEXT NOT NULL
      );

      CREATE INDEX IF NOT EXISTS payment_intents_user
        ON payment_intents(user_id, created_at);

      CREATE TABLE IF NOT EXISTS payment_intent_events (
        sequence INTEGER PRIMARY KEY AUTOINCREMENT,
        event_id TEXT NOT NULL UNIQUE,
        command_id TEXT NOT NULL UNIQUE,
        intent_id TEXT NOT NULL,
        type TEXT NOT NULL,
        version INTEGER NOT NULL,
        at TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        prev_hash TEXT NOT NULL,
        signature_json TEXT NOT NULL,
        hash TEXT NOT NULL,
        FOREIGN KEY(intent_id) REFERENCES payment_intents(id)
      );

      CREATE TABLE IF NOT EXISTS payment_intent_challenges (
        intent_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        token_id TEXT NOT NULL,
        nonce TEXT NOT NULL UNIQUE,
        expires_at TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        used_at TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        PRIMARY KEY(intent_id, user_id),
        FOREIGN KEY(intent_id) REFERENCES payment_intents(id)
      );

      CREATE TABLE IF NOT EXISTS payment_transfers (
        id TEXT PRIMARY KEY,
        intent_id TEXT UNIQUE,
        chat_id TEXT NOT NULL,
        from_id TEXT NOT NULL,
        to_id TEXT NOT NULL,
        amount_cents INTEGER NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        method TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        received_at TEXT NOT NULL DEFAULT '',
        refunded_at TEXT NOT NULL DEFAULT '',
        refunded_by TEXT NOT NULL DEFAULT '',
        message_id TEXT NOT NULL DEFAULT '',
        updated_at TEXT NOT NULL
      );

      CREATE INDEX IF NOT EXISTS payment_transfers_user
        ON payment_transfers(from_id, to_id, created_at);

      CREATE INDEX IF NOT EXISTS payment_transfers_pending
        ON payment_transfers(status, expires_at);

      CREATE TABLE IF NOT EXISTS payment_wallet_ops (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        amount_cents INTEGER NOT NULL,
        fee_cents INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL,
        bank_text TEXT NOT NULL DEFAULT '',
        bank_id TEXT NOT NULL DEFAULT '',
        provider_ref TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        done_at TEXT NOT NULL DEFAULT '',
        updated_at TEXT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS payment_funding_orders (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        amount_cents INTEGER NOT NULL,
        fee_cents INTEGER NOT NULL DEFAULT 0,
        currency TEXT NOT NULL DEFAULT 'CNY',
        status TEXT NOT NULL,
        provider TEXT NOT NULL,
        provider_ref TEXT NOT NULL DEFAULT '',
        bank_ref TEXT NOT NULL DEFAULT '',
        idempotency_key TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        settled_at TEXT NOT NULL DEFAULT '',
        failure_code TEXT NOT NULL DEFAULT ''
      );

      CREATE INDEX IF NOT EXISTS payment_funding_orders_user
        ON payment_funding_orders(user_id, created_at);

      CREATE TABLE IF NOT EXISTS payment_provider_events (
        provider TEXT NOT NULL,
        provider_event_id TEXT NOT NULL,
        type TEXT NOT NULL,
        payload_hash TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        received_at TEXT NOT NULL,
        processed_at TEXT NOT NULL DEFAULT '',
        result_json TEXT NOT NULL DEFAULT '',
        PRIMARY KEY(provider, provider_event_id)
      );

      CREATE TABLE IF NOT EXISTS payment_outbox (
        id TEXT PRIMARY KEY,
        topic TEXT NOT NULL,
        aggregate_id TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        status TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        next_attempt_at TEXT NOT NULL,
        created_at TEXT NOT NULL,
        delivered_at TEXT NOT NULL DEFAULT '',
        last_error TEXT NOT NULL DEFAULT ''
      );

      CREATE INDEX IF NOT EXISTS payment_outbox_pending
        ON payment_outbox(status, next_attempt_at, created_at);

      CREATE TABLE IF NOT EXISTS payment_commands (
        scope TEXT NOT NULL,
        command_key TEXT NOT NULL,
        status TEXT NOT NULL,
        response_json TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY(scope, command_key)
      );

      CREATE TABLE IF NOT EXISTS payment_settlement_runs (
        id TEXT PRIMARY KEY,
        provider TEXT NOT NULL,
        settlement_date TEXT NOT NULL,
        status TEXT NOT NULL,
        provider_lines INTEGER NOT NULL,
        local_lines INTEGER NOT NULL,
        mismatch_count INTEGER NOT NULL,
        report_json TEXT NOT NULL,
        created_at TEXT NOT NULL
      );

      CREATE INDEX IF NOT EXISTS payment_settlement_runs_date
        ON payment_settlement_runs(provider, settlement_date, created_at);

      CREATE TABLE IF NOT EXISTS payment_settlement_lines (
        run_id TEXT NOT NULL,
        provider_ref TEXT NOT NULL,
        order_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        amount_cents INTEGER NOT NULL,
        fee_cents INTEGER NOT NULL,
        currency TEXT NOT NULL,
        status TEXT NOT NULL,
        raw_json TEXT NOT NULL,
        PRIMARY KEY(run_id, provider_ref),
        FOREIGN KEY(run_id) REFERENCES payment_settlement_runs(id)
      );
    `);
    this.ensureMeta('intent_last_hash', '');
    this.ensureMeta('intent_sequence', '0');
  }

  newId(prefix) {
    return this.uid(prefix);
  }

  registerDevice(input) {
    return this.transaction(() => this.registerDeviceLocked(input));
  }

  registerDeviceLocked(input) {
    const row = input || {};
    const tokenId = String(row.tokenId || '');
    const userId = String(row.userId || '');
    const deviceId = String(row.deviceId || '');
    const publicKey = String(row.publicKey || '');
    if (!/^[A-Za-z0-9._:-]{8,128}$/.test(tokenId)) throw new Error('invalid payment token id');
    if (!userId || !deviceId) throw new Error('token owner and device are required');
    if (publicKey.length < 64 || publicKey.length > 4096) throw new Error('invalid device public key');
    crypto.createPublicKey(publicKey);
    const existing = this.db.prepare(`
      SELECT * FROM payment_devices WHERE token_id = ?
    `).get(tokenId);
    if (existing) {
      if (existing.user_id !== userId || existing.device_id !== deviceId
          || existing.public_key_pem !== publicKey) {
        throw new Error('payment token already enrolled');
      }
      return this.deviceView(existing);
    }
    const at = this.now();
    this.db.prepare(`
      INSERT INTO payment_devices(
        token_id, user_id, device_id, network, last4, public_key_pem,
        status, created_at, revoked_at
      ) VALUES(?, ?, ?, ?, ?, ?, 'active', ?, '')
    `).run(
      tokenId,
      userId,
      deviceId,
      String(row.network || 'xingyan-internal'),
      String(row.last4 || '').replace(/\D/g, '').slice(-4),
      publicKey,
      at
    );
    return this.deviceView(this.db.prepare(`
      SELECT * FROM payment_devices WHERE token_id = ?
    `).get(tokenId));
  }

  beginDeviceEnrollment(input) {
    const row = input || {};
    const userId = String(row.userId || '');
    const deviceId = String(row.deviceId || '');
    const publicKey = String(row.publicKey || '');
    if (!userId || !deviceId) throw new Error('user and device are required');
    if (publicKey.length < 64 || publicKey.length > 4096) throw new Error('invalid device public key');
    crypto.createPublicKey(publicKey);
    return this.transaction(() => {
      this.db.prepare(`
        DELETE FROM payment_device_challenges
        WHERE expires_at <= ? OR used_at <> ''
      `).run(this.now());
      const challenge = crypto.randomBytes(32).toString('base64url');
      const tokenId = this.newId('ptk');
      const expiresAt = new Date(Date.now() + 2 * 60 * 1000).toISOString();
      this.db.prepare(`
        INSERT INTO payment_device_challenges(
          challenge, token_id, user_id, device_id, public_key_pem,
          expires_at, used_at, created_at
        ) VALUES(?, ?, ?, ?, ?, ?, '', ?)
      `).run(
        challenge,
        tokenId,
        userId,
        deviceId,
        publicKey,
        expiresAt,
        this.now()
      );
      return { challenge, tokenId, expiresAt };
    });
  }

  finishDeviceEnrollment(input) {
    const row = input || {};
    const challengeValue = String(row.challenge || '');
    return this.transaction(() => {
      const challenge = this.db.prepare(`
        SELECT * FROM payment_device_challenges WHERE challenge = ?
      `).get(challengeValue);
      if (!challenge || challenge.used_at || Date.parse(challenge.expires_at) <= Date.now()) {
        throw new Error('device enrollment challenge is invalid or expired');
      }
      const payload = {
        purpose: 'payment-device-enrollment',
        challenge: challengeValue,
        tokenId: String(challenge.token_id),
        userId: String(challenge.user_id),
        deviceId: String(challenge.device_id),
        publicKey: String(challenge.public_key_pem)
      };
      if (!verifyDeviceSignature(payload.publicKey, payload, row.signature)) {
        throw new Error('device enrollment signature is invalid');
      }
      const token = this.registerDeviceLocked({
        tokenId: payload.tokenId,
        userId: payload.userId,
        deviceId: payload.deviceId,
        publicKey: payload.publicKey,
        network: 'xingyan-internal',
        last4: row.last4
      });
      this.db.prepare(`
        UPDATE payment_device_challenges SET used_at = ? WHERE challenge = ?
      `).run(this.now(), challengeValue);
      return token;
    });
  }

  deviceView(row) {
    if (!row) return null;
    return {
      tokenId: String(row.token_id),
      userId: String(row.user_id),
      deviceId: String(row.device_id),
      network: String(row.network),
      last4: String(row.last4 || ''),
      publicKey: String(row.public_key_pem),
      status: String(row.status),
      createdAt: String(row.created_at),
      revokedAt: String(row.revoked_at || '')
    };
  }

  device(tokenId) {
    return this.deviceView(this.db.prepare(`
      SELECT * FROM payment_devices WHERE token_id = ?
    `).get(String(tokenId || '')));
  }

  revokeDevice(tokenId, userId) {
    return this.transaction(() => {
      const token = this.device(tokenId);
      if (!token || token.userId !== String(userId || '')) {
        throw new Error('payment token not found');
      }
      const at = this.now();
      this.db.prepare(`
        UPDATE payment_devices
        SET status = 'revoked', revoked_at = ?
        WHERE token_id = ?
      `).run(at, token.tokenId);
      return Object.assign(token, { status: 'revoked', revokedAt: at });
    });
  }

  intentView(row) {
    if (!row) return null;
    return {
      id: String(row.id),
      userId: String(row.user_id),
      merchantId: String(row.merchant_id),
      deviceId: String(row.device_id),
      amountCents: Number(row.amount_cents),
      currency: String(row.currency),
      metadata: parseJson(row.metadata_json, {}),
      status: String(row.status),
      version: Number(row.version),
      tokenId: String(row.token_id || ''),
      last4: String(row.last4 || ''),
      refundedCents: Number(row.refunded_cents || 0),
      pendingRefundCents: Number(row.pending_refund_cents || 0),
      createdAt: String(row.created_at),
      authorizedAt: String(row.authorized_at || ''),
      capturedAt: String(row.captured_at || ''),
      updatedAt: String(row.updated_at)
    };
  }

  intent(intentId) {
    return this.intentView(this.db.prepare(`
      SELECT * FROM payment_intents WHERE id = ?
    `).get(String(intentId || '')));
  }

  appendIntentEventLocked(input) {
    const row = input || {};
    const intent = this.intent(row.intentId);
    if (!intent) throw new Error('payment intent not found');
    const lastEvent = this.db.prepare(`
      SELECT version FROM payment_intent_events
      WHERE intent_id = ?
      ORDER BY sequence DESC
      LIMIT 1
    `).get(intent.id);
    const expectedVersion = lastEvent ? Number(lastEvent.version) + 1 : 1;
    if (Number(row.version) !== expectedVersion) {
      throw new Error('payment intent version sequence is invalid');
    }
    const unsigned = {
      eventId: String(row.eventId || this.newId('pie')),
      commandId: String(row.commandId || ''),
      intentId: intent.id,
      type: String(row.type || ''),
      version: Number(row.version),
      at: String(row.at || this.now()),
      prevHash: String(this.getMeta('intent_last_hash') || ''),
      data: row.data || {}
    };
    if (!unsigned.commandId || !unsigned.type) throw new Error('payment intent event is incomplete');
    const signature = this.keyring.sign(unsigned);
    const eventHash = hash(unsigned);
    this.db.prepare(`
      INSERT INTO payment_intent_events(
        event_id, command_id, intent_id, type, version, at,
        payload_json, prev_hash, signature_json, hash
      ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      unsigned.eventId,
      unsigned.commandId,
      unsigned.intentId,
      unsigned.type,
      unsigned.version,
      unsigned.at,
      stableJson(unsigned.data),
      unsigned.prevHash,
      JSON.stringify(signature),
      eventHash
    );
    this.setMeta('intent_last_hash', eventHash);
    this.setMeta('intent_sequence', String(Number(this.getMeta('intent_sequence') || 0) + 1));
    return { unsigned, signature, hash: eventHash };
  }

  createIntent(input) {
    const row = input || {};
    const intentId = String(row.intentId || this.newId('pi'));
    const commandId = String(row.commandId || '');
    if (!/^[A-Za-z0-9._:-]{8,128}$/.test(intentId)) throw new Error('invalid payment intent id');
    if (!commandId) throw new Error('commandId is required');
    if (!row.userId || !row.merchantId || !row.deviceId) throw new Error('intent parties are required');
    const amountCents = Number(row.amountCents);
    if (!Number.isSafeInteger(amountCents) || amountCents <= 0) {
      throw new Error('amountCents must be a positive integer');
    }
    if (!/^[A-Z]{3}$/.test(String(row.currency || ''))) throw new Error('currency is required');
    const metadata = row.metadata && typeof row.metadata === 'object'
      ? JSON.parse(JSON.stringify(row.metadata))
      : {};
    if (Buffer.byteLength(JSON.stringify(metadata), 'utf8') > 4096) {
      throw new Error('payment metadata is too large');
    }
    return this.transaction(() => {
      const duplicate = this.db.prepare(`
        SELECT intent_id FROM payment_intent_events WHERE command_id = ?
      `).get(commandId);
      if (duplicate) {
        return Object.assign(this.intent(duplicate.intent_id), { idempotent: true });
      }
      if (this.intent(intentId)) throw new Error('payment intent already exists');
      const at = this.now();
      this.db.prepare(`
        INSERT INTO payment_intents(
          id, user_id, merchant_id, device_id, amount_cents, currency,
          metadata_json, status, version, created_at, updated_at
        ) VALUES(?, ?, ?, ?, ?, ?, ?, 'created', 1, ?, ?)
      `).run(
        intentId,
        String(row.userId),
        String(row.merchantId),
        String(row.deviceId),
        amountCents,
        String(row.currency),
        stableJson(metadata),
        at,
        at
      );
      this.appendIntentEventLocked({
        commandId,
        intentId,
        type: 'created',
        version: 1,
        at,
        data: {
          userId: String(row.userId),
          merchantId: String(row.merchantId),
          deviceId: String(row.deviceId),
          amountCents,
          currency: String(row.currency),
          metadata
        }
      });
      return this.intent(intentId);
    });
  }

  createIntentChallenge(input) {
    const row = input || {};
    return this.transaction(() => {
      const intent = this.intent(row.intentId);
      if (!intent || intent.userId !== String(row.userId || '')) {
        throw new Error('payment intent not found');
      }
      if (intent.status !== 'created') throw new Error('payment intent is not authorizable');
      const token = this.device(row.tokenId);
      if (!token || token.userId !== intent.userId || token.status !== 'active') {
        throw new Error('payment token is inactive');
      }
      if (token.deviceId !== intent.deviceId) throw new Error('device-binding-mismatch');
      const nonce = crypto.randomBytes(32).toString('base64url');
      const expiresAt = new Date(Date.now() + 2 * 60 * 1000).toISOString();
      const payload = {
        intentId: intent.id,
        userId: intent.userId,
        merchantId: intent.merchantId,
        deviceId: intent.deviceId,
        amountCents: intent.amountCents,
        currency: intent.currency,
        nonce,
        expiresAt
      };
      this.db.prepare(`
        INSERT INTO payment_intent_challenges(
          intent_id, user_id, token_id, nonce, expires_at, payload_json,
          used_at, created_at
        ) VALUES(?, ?, ?, ?, ?, ?, '', ?)
        ON CONFLICT(intent_id, user_id) DO UPDATE SET
          token_id = excluded.token_id,
          nonce = excluded.nonce,
          expires_at = excluded.expires_at,
          payload_json = excluded.payload_json,
          used_at = '',
          created_at = excluded.created_at
      `).run(
        intent.id,
        intent.userId,
        token.tokenId,
        nonce,
        expiresAt,
        stableJson(payload),
        this.now()
      );
      return { tokenId: token.tokenId, nonce, expiresAt, payload };
    });
  }

  authorizeIntent(input) {
    const row = input || {};
    return this.transaction(() => {
      const intent = this.intent(row.intentId);
      if (!intent || intent.userId !== String(row.userId || '')) {
        throw new Error('payment intent not found');
      }
      const duplicate = this.db.prepare(`
        SELECT intent_id FROM payment_intent_events WHERE command_id = ?
      `).get(String(row.commandId || ''));
      if (duplicate) return Object.assign(intent, { idempotent: true });
      if (intent.status !== 'created') throw new Error('payment intent is not authorizable');
      const challenge = this.db.prepare(`
        SELECT * FROM payment_intent_challenges
        WHERE intent_id = ? AND user_id = ?
      `).get(intent.id, intent.userId);
      if (!challenge || challenge.used_at) {
        throw new Error('payment authorization challenge is missing or used');
      }
      if (String(challenge.token_id) !== String(row.tokenId || '')) {
        throw new Error('payment token does not match challenge');
      }
      const expiresAt = Date.parse(String(challenge.expires_at || ''));
      const nowMs = Date.now();
      if (!Number.isFinite(expiresAt) || expiresAt <= nowMs
          || expiresAt > nowMs + 5 * 60 * 1000) {
        throw new Error('authorization has expired or has an invalid lifetime');
      }
      const token = this.device(challenge.token_id);
      if (!token || token.status !== 'active' || token.userId !== intent.userId
          || token.deviceId !== intent.deviceId) {
        throw new Error('payment token is inactive or bound to another device');
      }
      const payload = parseJson(challenge.payload_json, null);
      if (!payload || !verifyDeviceSignature(token.publicKey, payload, row.signature)) {
        throw new Error('invalid-device-signature');
      }
      const at = this.now();
      this.db.prepare(`
        UPDATE payment_intent_challenges SET used_at = ?
        WHERE intent_id = ? AND user_id = ?
      `).run(at, intent.id, intent.userId);
      this.db.prepare(`
        UPDATE payment_intents
        SET status = 'authorized', version = version + 1, token_id = ?,
            nonce = ?, last4 = ?, authorized_at = ?, updated_at = ?
        WHERE id = ?
      `).run(token.tokenId, String(challenge.nonce), token.last4, at, at, intent.id);
      this.appendIntentEventLocked({
        commandId: String(row.commandId || ('authorize:' + intent.id)),
        intentId: intent.id,
        type: 'authorized',
        version: intent.version + 1,
        at,
        data: {
          tokenId: token.tokenId,
          nonce: String(challenge.nonce),
          network: token.network,
          last4: token.last4
        }
      });
      return this.intent(intent.id);
    });
  }

  setIntentPendingRefundLocked(intent, amountCents, ledgerRef) {
    const at = this.now();
    this.db.prepare(`
      UPDATE payment_intents
      SET status = 'refund_pending', version = version + 1,
          pending_refund_cents = ?, ledger_ref = ?, updated_at = ?
      WHERE id = ?
    `).run(amountCents, ledgerRef, at, intent.id);
    this.appendIntentEventLocked({
      commandId: 'refund:' + intent.id + ':pending',
      intentId: intent.id,
      type: 'refund_pending',
      version: intent.version + 1,
      at,
      data: { amountCents, ledgerRef }
    });
    return this.intent(intent.id);
  }

  refundIntent(input) {
    const row = input || {};
    const requested = Number(row.amountCents);
    return this.transaction(() => {
      let intent = this.intent(row.intentId);
      if (!intent) throw new Error('payment intent not found');
      const duplicate = this.db.prepare(`
        SELECT intent_id FROM payment_intent_events WHERE command_id = ?
      `).get(String(row.commandId || ''));
      if (duplicate) return Object.assign(intent, { idempotent: true });
      if (!['captured', 'partially_refunded', 'refund_pending'].includes(intent.status)) {
        throw new Error('payment intent is not refundable');
      }
      const amountCents = intent.status === 'refund_pending'
        ? intent.pendingRefundCents
        : requested;
      if (!Number.isSafeInteger(amountCents) || amountCents <= 0
          || amountCents > intent.amountCents - intent.refundedCents) {
        throw new Error('invalid refund amount');
      }
      if (intent.status === 'refund_pending' && Number.isSafeInteger(requested)
          && requested !== amountCents) {
        throw new Error('refund retry amount does not match the pending refund');
      }
      const ledgerRef = String(row.ledgerRef || ('intent:refund:' + intent.id + ':' + row.commandId));
      if (intent.status !== 'refund_pending') {
        intent = this.setIntentPendingRefundLocked(intent, amountCents, ledgerRef);
      }
      this.recordLocked({
        userId: intent.userId,
        reason: '支付意图退款',
        ref: ledgerRef
      }, [
        { account: 'user:' + intent.userId, deltaCents: amountCents },
        { account: 'merchant:' + intent.merchantId, deltaCents: -amountCents }
      ], ledgerRef);
      const refundedCents = intent.refundedCents + amountCents;
      const status = refundedCents === intent.amountCents ? 'refunded' : 'partially_refunded';
      const at = this.now();
      this.db.prepare(`
        UPDATE payment_intents
        SET status = ?, version = version + 1, refunded_cents = ?,
            pending_refund_cents = 0, settlement_reference = ?, updated_at = ?
        WHERE id = ?
      `).run(status, refundedCents, ledgerRef, at, intent.id);
      this.appendIntentEventLocked({
        commandId: String(row.commandId || ('refund:' + intent.id)),
        intentId: intent.id,
        type: status,
        version: intent.version + 1,
        at,
        data: { amountCents, refundedCents, settlementReference: ledgerRef }
      });
      return this.intent(intent.id);
    });
  }

  enqueueOutboxLocked(topic, aggregateId, payload, at) {
    const id = this.newId('obx');
    const timestamp = String(at || this.now());
    this.db.prepare(`
      INSERT INTO payment_outbox(
        id, topic, aggregate_id, payload_json, status, attempts,
        next_attempt_at, created_at, delivered_at, last_error
      ) VALUES(?, ?, ?, ?, 'pending', 0, ?, ?, '', '')
    `).run(id, String(topic), String(aggregateId), stableJson(payload || {}), timestamp, timestamp);
    return id;
  }

  transferView(row) {
    if (!row) return null;
    return {
      id: String(row.id),
      intentId: String(row.intent_id || ''),
      chatId: String(row.chat_id),
      fromId: String(row.from_id),
      toId: String(row.to_id),
      amount: money(row.amount_cents),
      amountCents: Number(row.amount_cents),
      note: String(row.note || ''),
      method: String(row.method),
      status: String(row.status),
      createdAt: String(row.created_at),
      expiresAt: Date.parse(String(row.expires_at)),
      receivedAt: String(row.received_at || ''),
      refundedAt: String(row.refunded_at || ''),
      refundedBy: String(row.refunded_by || ''),
      messageId: String(row.message_id || '')
    };
  }

  transfer(transferId) {
    return this.transferView(this.db.prepare(`
      SELECT * FROM payment_transfers WHERE id = ?
    `).get(String(transferId || '')));
  }

  transferByIntent(intentId) {
    return this.transferView(this.db.prepare(`
      SELECT * FROM payment_transfers WHERE intent_id = ?
    `).get(String(intentId || '')));
  }

  captureTransfer(input) {
    const row = input || {};
    return this.transaction(() => {
      let intent = this.intent(row.intentId);
      if (!intent) throw new Error('payment intent not found');
      const existing = this.transferByIntent(intent.id);
      if (existing) return { duplicate: true, transfer: existing, intent };
      if (!['authorized', 'capture_pending'].includes(intent.status)) {
        throw new Error('payment intent is not capturable');
      }
      const amountCents = intent.amountCents;
      const transferId = String(row.transferId || this.newId('tr'));
      const ledgerRef = String(row.ledgerRef || ('payment-intent:' + intent.id));
      const at = this.now();
      const pendingAt = at;
      this.db.prepare(`
        UPDATE payment_intents
        SET status = 'capture_pending', version = version + 1,
            ledger_ref = ?, updated_at = ?
        WHERE id = ?
      `).run(ledgerRef, pendingAt, intent.id);
      this.appendIntentEventLocked({
        commandId: 'capture:' + intent.id + ':pending',
        intentId: intent.id,
        type: 'capture_pending',
        version: intent.version + 1,
        at: pendingAt,
        data: { ledgerRef }
      });
      intent = this.intent(intent.id);

      this.recordLocked({
        userId: intent.userId,
        reason: '转账',
        ref: ledgerRef
      }, [
        { account: 'user:' + intent.userId, deltaCents: -amountCents },
        { account: 'system:pending-transfer', deltaCents: amountCents }
      ], ledgerRef);

      const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
      this.db.prepare(`
        INSERT INTO payment_transfers(
          id, intent_id, chat_id, from_id, to_id, amount_cents, note, method,
          status, created_at, expires_at, received_at, refunded_at,
          refunded_by, message_id, updated_at
        ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?, '', '', '', '', ?)
      `).run(
        transferId,
        intent.id,
        String(row.chatId),
        intent.userId,
        String(row.toId),
        amountCents,
        String(row.note || ''),
        String(row.method || 'balance'),
        at,
        expiresAt,
        at
      );
      const transfer = this.transfer(transferId);
      const outboxId = this.enqueueOutboxLocked('transfer.created', transferId, {
        transfer,
        intentId: intent.id
      }, at);
      this.db.prepare(`
        UPDATE payment_intents
        SET status = 'captured', version = version + 1,
            settlement_reference = ?, captured_at = ?, updated_at = ?
        WHERE id = ?
      `).run(ledgerRef, at, at, intent.id);
      this.appendIntentEventLocked({
        commandId: 'capture:' + intent.id + ':captured',
        intentId: intent.id,
        type: 'captured',
        version: intent.version + 1,
        at,
        data: { settlementReference: ledgerRef, transferId, outboxId }
      });
      return {
        duplicate: false,
        transfer: this.transfer(transferId),
        intent: this.intent(intent.id),
        outboxId
      };
    });
  }

  settleInternalPayment(input) {
    const row = input || {};
    const fromUserId = String(row.fromUserId || '');
    const toUserId = String(row.toUserId || '');
    const amountCents = Number(row.amountCents);
    const ref = String(row.ref || '');
    if (!fromUserId || !toUserId || fromUserId === toUserId) {
      throw new Error('internal payment parties are invalid');
    }
    if (!Number.isSafeInteger(amountCents) || amountCents <= 0) {
      throw new Error('internal payment amount is invalid');
    }
    if (!ref) throw new Error('internal payment reference is required');
    return this.transaction(() => {
      const existing = this.recordForRef(ref);
      if (existing) {
        const existingTransfer = row.transfer && row.transfer.id
          ? this.transfer(String(row.transfer.id))
          : null;
        return {
          duplicate: true,
          fromBalance: this.accountBalance('user:' + fromUserId),
          toBalance: this.accountBalance(
            row.toBusiness ? 'user:biz:' + toUserId : 'user:' + toUserId
          ),
          transfer: existingTransfer
        };
      }
      const toAccount = row.toBusiness ? 'user:biz:' + toUserId : 'user:' + toUserId;
      const record = this.recordLocked({
        userId: fromUserId,
        reason: String(row.reason || '内部付款'),
        ref
      }, [
        { account: 'user:' + fromUserId, deltaCents: -amountCents },
        { account: toAccount, deltaCents: amountCents }
      ], ref);
      const at = this.now();
      let transfer = null;
      let transferOutboxId = '';
      if (row.transfer) {
        const transferInput = row.transfer;
        const transferId = String(transferInput.id || this.newId('tr'));
        this.db.prepare(`
          INSERT INTO payment_transfers(
            id, intent_id, chat_id, from_id, to_id, amount_cents, note, method,
            status, created_at, expires_at, received_at, refunded_at,
            refunded_by, message_id, updated_at
          ) VALUES(?, NULL, ?, ?, ?, ?, ?, ?, 'received', ?, ?, ?, '', '', '', ?)
        `).run(
          transferId,
          String(transferInput.chatId || ''),
          fromUserId,
          toUserId,
          amountCents,
          String(transferInput.note || ''),
          String(transferInput.method || 'balance'),
          at,
          at,
          at,
          at
        );
        transfer = this.transfer(transferId);
        transferOutboxId = this.enqueueOutboxLocked('transfer.created', transferId, {
          transfer,
          internalPaymentRef: ref
        }, at);
      }
      const outboxId = this.enqueueOutboxLocked('balance.settled', ref, {
        fromUserId,
        toUserId,
        amountCents,
        recordId: record.id,
        transferId: transfer ? transfer.id : ''
      }, at);
      return {
        duplicate: false,
        recordId: record.id,
        outboxId,
        transferOutboxId,
        transfer,
        fromBalance: this.accountBalance('user:' + fromUserId),
        toBalance: this.accountBalance(toAccount)
      };
    });
  }

  claimTransfer(transferId, recipientId, toBusiness) {
    return this.transaction(() => {
      const transfer = this.transfer(transferId);
      if (!transfer) throw new Error('transfer not found');
      if (transfer.toId !== String(recipientId || '')) throw new Error('transfer recipient mismatch');
      if (transfer.status === 'received') return { duplicate: true, transfer };
      if (transfer.status === 'refunded') throw new Error('transfer has already been refunded');
      if (transfer.expiresAt <= Date.now()) throw new Error('transfer has expired');
      const account = toBusiness ? 'user:biz:' + recipientId : 'user:' + recipientId;
      this.recordLocked({
        userId: recipientId,
        reason: '收转账',
        ref: 'transfer:claim:' + transfer.id
      }, [
        { account, deltaCents: transfer.amountCents },
        { account: 'system:pending-transfer', deltaCents: -transfer.amountCents }
      ], 'transfer:claim:' + transfer.id);
      const at = this.now();
      this.db.prepare(`
        UPDATE payment_transfers
        SET status = 'received', received_at = ?, updated_at = ?
        WHERE id = ?
      `).run(at, at, transfer.id);
      const outboxId = this.enqueueOutboxLocked('transfer.received', transfer.id, {
        transfer: this.transfer(transfer.id)
      }, at);
      return { duplicate: false, transfer: this.transfer(transfer.id), outboxId };
    });
  }

  refundTransfer(transferId, recipientId, fromBusiness) {
    return this.transaction(() => {
      const transfer = this.transfer(transferId);
      if (!transfer) throw new Error('transfer not found');
      if (transfer.toId !== String(recipientId || '')) throw new Error('transfer recipient mismatch');
      if (transfer.status === 'refunded') return { duplicate: true, transfer };
      if (transfer.status !== 'received') throw new Error('transfer is not received');
      if (Date.parse(transfer.receivedAt) + 5 * 60 * 60 * 1000 < Date.now()) {
        throw new Error('transfer refund window closed');
      }
      const source = fromBusiness ? 'user:biz:' + recipientId : 'user:' + recipientId;
      const at = this.now();
      this.recordLocked({
        userId: recipientId,
        reason: fromBusiness ? '收款方退还（经营账户）' : '收款方退还',
        ref: 'transfer:refund:' + transfer.id
      }, [
        { account: source, deltaCents: -transfer.amountCents },
        { account: 'user:' + transfer.fromId, deltaCents: transfer.amountCents }
      ], 'transfer:refund:' + transfer.id);
      this.db.prepare(`
        UPDATE payment_transfers
        SET status = 'refunded', refunded_at = ?, refunded_by = ?, updated_at = ?
        WHERE id = ?
      `).run(at, recipientId, at, transfer.id);
      const outboxId = this.enqueueOutboxLocked('transfer.refunded', transfer.id, {
        transfer: this.transfer(transfer.id)
      }, at);
      return { duplicate: false, transfer: this.transfer(transfer.id), outboxId };
    });
  }

  expireTransfers(limit) {
    const rows = this.db.prepare(`
      SELECT id FROM payment_transfers
      WHERE status = 'pending' AND expires_at <= ?
      ORDER BY expires_at ASC
      LIMIT ?
    `).all(new Date().toISOString(), Math.max(1, Number(limit) || 100));
    const expired = [];
    for (const row of rows) {
      try {
        this.transaction(() => {
          const transfer = this.transfer(row.id);
          if (!transfer || transfer.status !== 'pending') return;
          this.recordLocked({
            userId: transfer.fromId,
            reason: '转账 24 小时未收自动退回',
            ref: 'transfer:expire:' + transfer.id
          }, [
            { account: 'user:' + transfer.fromId, deltaCents: transfer.amountCents },
            { account: 'system:pending-transfer', deltaCents: -transfer.amountCents }
          ], 'transfer:expire:' + transfer.id);
          const at = this.now();
          this.db.prepare(`
            UPDATE payment_transfers
            SET status = 'refunded', refunded_at = ?, updated_at = ?
            WHERE id = ?
          `).run(at, at, transfer.id);
          const outboxId = this.enqueueOutboxLocked('transfer.expired', transfer.id, {
            transfer: this.transfer(transfer.id)
          }, at);
          expired.push({ id: transfer.id, outboxId });
        });
      } catch (error) {
        if (!/expired|refunded|not found/i.test(String(error && error.message || error))) {
          throw error;
        }
      }
    }
    return expired;
  }

  fundingView(row) {
    if (!row) return null;
    return {
      id: String(row.id),
      userId: String(row.user_id),
      kind: String(row.kind),
      amount: money(row.amount_cents),
      amountCents: Number(row.amount_cents),
      fee: money(row.fee_cents),
      feeCents: Number(row.fee_cents || 0),
      currency: String(row.currency),
      status: String(row.status),
      provider: String(row.provider),
      providerRef: String(row.provider_ref || ''),
      createdAt: String(row.created_at),
      updatedAt: String(row.updated_at),
      settledAt: String(row.settled_at || ''),
      failureCode: String(row.failure_code || '')
    };
  }

  fundingOrder(orderId) {
    return this.fundingView(this.db.prepare(`
      SELECT * FROM payment_funding_orders WHERE id = ?
    `).get(String(orderId || '')));
  }

  createFundingOrder(input) {
    const row = input || {};
    const id = String(row.id || this.newId('fund'));
    const kind = String(row.kind || '');
    const amountCents = Number(row.amountCents);
    const feeCents = Number(row.feeCents || 0);
    if (!['deposit', 'payout'].includes(kind)) throw new Error('invalid funding order kind');
    if (!Number.isSafeInteger(amountCents) || amountCents <= 0) throw new Error('invalid funding amount');
    if (!Number.isSafeInteger(feeCents) || feeCents < 0) throw new Error('invalid funding fee');
    if (!row.userId || !row.provider) throw new Error('funding order parties are required');
    return this.transaction(() => {
      const duplicate = this.db.prepare(`
        SELECT * FROM payment_funding_orders WHERE idempotency_key = ?
      `).get(String(row.idempotencyKey || ''));
      if (duplicate) return Object.assign(this.fundingView(duplicate), { idempotent: true });
      const at = this.now();
      this.db.prepare(`
        INSERT INTO payment_funding_orders(
          id, user_id, kind, amount_cents, fee_cents, currency, status,
          provider, provider_ref, bank_ref, idempotency_key, created_at,
          updated_at, settled_at, failure_code
        ) VALUES(?, ?, ?, ?, ?, ?, 'pending', ?, '', ?, ?, ?, ?, '', '')
      `).run(
        id,
        String(row.userId),
        kind,
        amountCents,
        feeCents,
        String(row.currency || 'CNY'),
        String(row.provider),
        String(row.bankRef || ''),
        String(row.idempotencyKey || ''),
        at,
        at
      );
      if (kind === 'payout') {
        this.recordLocked({
          userId: String(row.userId),
          reason: '提现申请（待支付机构结算）',
          ref: 'funding:payout:' + id
        }, [
          {
            account: 'user:' + row.userId,
            deltaCents: -(amountCents + feeCents)
          },
          { account: 'system:payout-pending', deltaCents: amountCents },
          { account: 'system:fee-revenue', deltaCents: feeCents }
        ], 'funding:payout:' + id);
      }
      this.enqueueOutboxLocked('funding.' + kind + '.created', id, {
        order: this.fundingOrder(id)
      }, at);
      return this.fundingOrder(id);
    });
  }

  setFundingProviderRef(orderId, providerRef) {
    return this.transaction(() => {
      const order = this.fundingOrder(orderId);
      if (!order) throw new Error('funding order not found');
      this.db.prepare(`
        UPDATE payment_funding_orders
        SET provider_ref = ?, updated_at = ?
        WHERE id = ?
      `).run(String(providerRef || ''), this.now(), order.id);
      return this.fundingOrder(order.id);
    });
  }

  recordProviderEvent(input) {
    const row = input || {};
    const provider = String(row.provider || '');
    const eventId = String(row.providerEventId || '');
    if (!provider || !eventId) throw new Error('provider event identity is required');
    const payload = row.payload || {};
    const payloadJson = stableJson(payload);
    const payloadHash = crypto.createHash('sha256').update(payloadJson).digest('hex');
    return this.transaction(() => {
      const existing = this.db.prepare(`
        SELECT * FROM payment_provider_events
        WHERE provider = ? AND provider_event_id = ?
      `).get(provider, eventId);
      if (existing) {
        if (existing.payload_hash !== payloadHash) {
          throw new Error('provider event payload changed after receipt');
        }
        return {
          duplicate: true,
          event: {
            provider,
            providerEventId: eventId,
            type: String(existing.type),
            processedAt: String(existing.processed_at || '')
          }
        };
      }
      this.db.prepare(`
        INSERT INTO payment_provider_events(
          provider, provider_event_id, type, payload_hash, payload_json,
          received_at, processed_at, result_json
        ) VALUES(?, ?, ?, ?, ?, ?, '', '')
      `).run(
        provider,
        eventId,
        String(row.type || ''),
        payloadHash,
        payloadJson,
        this.now()
      );
      return {
        duplicate: false,
        event: { provider, providerEventId: eventId, type: String(row.type || ''), processedAt: '' }
      };
    });
  }

  settleFundingOrder(input) {
    const row = input || {};
    return this.transaction(() => {
      const order = this.fundingOrder(row.orderId);
      if (!order) throw new Error('funding order not found');
      const eventId = String(row.providerEventId || '');
      if (eventId) {
        const event = this.db.prepare(`
          SELECT * FROM payment_provider_events
          WHERE provider = ? AND provider_event_id = ?
        `).get(order.provider, eventId);
        if (!event) throw new Error('provider event was not recorded');
        if (event.processed_at) return { duplicate: true, order };
      }
      if (order.status === 'succeeded') return { duplicate: true, order };
      if (!['pending', 'processing'].includes(order.status)) {
        throw new Error('funding order is not settleable');
      }
      const success = row.success !== false;
      const at = this.now();
      if (success && order.kind === 'deposit') {
        this.recordLocked({
          userId: order.userId,
          reason: '充值到零钱',
          ref: 'funding:deposit:' + order.id
        }, [
          { account: 'user:' + order.userId, deltaCents: order.amountCents },
          { account: 'system:external-settlement', deltaCents: -order.amountCents }
        ], 'funding:deposit:' + order.id);
      } else if (success && order.kind === 'payout') {
        this.recordLocked({
          userId: order.userId,
          reason: '提现已由支付机构结算',
          ref: 'funding:payout-complete:' + order.id
        }, [
          { account: 'system:payout-pending', deltaCents: -order.amountCents },
          { account: 'system:external-settlement', deltaCents: order.amountCents }
        ], 'funding:payout-complete:' + order.id);
      } else if (!success && order.kind === 'payout') {
        this.recordLocked({
          userId: order.userId,
          reason: '提现失败原路退回',
          ref: 'funding:payout-reversal:' + order.id
        }, [
          { account: 'system:payout-pending', deltaCents: -order.amountCents },
          { account: 'system:fee-revenue', deltaCents: -order.feeCents },
          { account: 'user:' + order.userId, deltaCents: order.amountCents + order.feeCents }
        ], 'funding:payout-reversal:' + order.id);
      }
      const status = success ? 'succeeded' : 'failed';
      this.db.prepare(`
        UPDATE payment_funding_orders
        SET status = ?, provider_ref = CASE WHEN ? = '' THEN provider_ref ELSE ? END,
            updated_at = ?, settled_at = ?, failure_code = ?
        WHERE id = ?
      `).run(
        status,
        String(row.providerRef || ''),
        String(row.providerRef || ''),
        at,
        at,
        success ? '' : String(row.failureCode || 'provider_failed'),
        order.id
      );
      if (eventId) {
        this.db.prepare(`
          UPDATE payment_provider_events
          SET processed_at = ?, result_json = ?
          WHERE provider = ? AND provider_event_id = ?
        `).run(at, stableJson({ status }), order.provider, eventId);
      }
      this.enqueueOutboxLocked('funding.' + order.kind + '.' + status, order.id, {
        order: this.fundingOrder(order.id),
        success
      }, at);
      return { duplicate: false, order: this.fundingOrder(order.id) };
    });
  }

  outbox(limit) {
    const max = Math.min(500, Math.max(1, Number(limit) || 50));
    return this.db.prepare(`
      SELECT * FROM payment_outbox
      WHERE status = 'pending' AND next_attempt_at <= ?
      ORDER BY created_at ASC
      LIMIT ?
    `).all(new Date().toISOString(), max).map((row) => ({
      id: String(row.id),
      topic: String(row.topic),
      aggregateId: String(row.aggregate_id),
      payload: parseJson(row.payload_json, {}),
      attempts: Number(row.attempts || 0),
      createdAt: String(row.created_at)
    }));
  }

  completeOutbox(eventId, messageId) {
    return this.transaction(() => {
      const at = this.now();
      const row = this.db.prepare(`
        SELECT topic, aggregate_id FROM payment_outbox WHERE id = ?
      `).get(String(eventId || ''));
      if (!row) throw new Error('outbox event not found');
      this.db.prepare(`
        UPDATE payment_outbox
        SET status = 'delivered', delivered_at = ?, last_error = ''
        WHERE id = ?
      `).run(at, String(eventId));
      if (row.topic === 'transfer.created' && messageId) {
        this.db.prepare(`
          UPDATE payment_transfers SET message_id = ?, updated_at = ?
          WHERE id = ?
        `).run(String(messageId), at, String(row.aggregate_id));
      }
      return true;
    });
  }

  completeOutboxForAggregate(topic, aggregateId, reference) {
    return this.transaction(() => {
      const row = this.db.prepare(`
        SELECT id FROM payment_outbox
        WHERE topic = ? AND aggregate_id = ? AND status = 'pending'
        ORDER BY created_at ASC LIMIT 1
      `).get(String(topic), String(aggregateId));
      if (!row) return false;
      this.db.prepare(`
        UPDATE payment_outbox
        SET status = 'delivered', delivered_at = ?, last_error = ''
        WHERE id = ?
      `).run(this.now(), String(row.id));
      return true;
    });
  }

  retryOutbox(eventId, error) {
    return this.transaction(() => {
      const row = this.db.prepare(`
        SELECT attempts FROM payment_outbox WHERE id = ?
      `).get(String(eventId || ''));
      if (!row) throw new Error('outbox event not found');
      const attempts = Number(row.attempts || 0) + 1;
      const delayMs = Math.min(5 * 60 * 1000, 1000 * Math.pow(2, Math.min(8, attempts)));
      const nextAt = new Date(Date.now() + delayMs).toISOString();
      const status = attempts >= 20 ? 'dead' : 'pending';
      this.db.prepare(`
        UPDATE payment_outbox
        SET status = ?, attempts = ?, next_attempt_at = ?, last_error = ?
        WHERE id = ?
      `).run(status, attempts, nextAt, String(error || '').slice(0, 1000), String(eventId));
      return { status, attempts, nextAt };
    });
  }

  verifyIntentIntegrity() {
    const failures = [];
    let expectedPrev = '';
    let checked = 0;
    const rows = this.db.prepare(`
      SELECT * FROM payment_intent_events ORDER BY sequence ASC
    `).all();
    for (const row of rows) {
      const event = {
        eventId: String(row.event_id),
        commandId: String(row.command_id),
        intentId: String(row.intent_id),
        type: String(row.type),
        version: Number(row.version),
        at: String(row.at),
        prevHash: String(row.prev_hash),
        data: parseJson(row.payload_json, {})
      };
      checked += 1;
      if (event.prevHash !== expectedPrev) {
        failures.push({ eventId: event.eventId, code: 'broken-chain' });
      }
      const signature = parseJson(row.signature_json, null);
      if (!this.keyring.verify(event, signature) || hash(event) !== String(row.hash)) {
        failures.push({ eventId: event.eventId, code: 'bad-signature' });
      }
      expectedPrev = String(row.hash);
    }
    if (expectedPrev !== String(this.getMeta('intent_last_hash') || '')) {
      failures.push({ eventId: 'meta', code: 'tail-mismatch' });
    }
    return { ok: failures.length === 0, checked, failures };
  }

  reconcileProviderSettlement(provider, settlementDate, lines) {
    const providerName = String(provider || '');
    const date = String(settlementDate || '');
    if (!providerName || !/^\d{4}-\d{2}-\d{2}$/.test(date)) {
      throw new Error('provider and settlement date are required');
    }
    if (!Array.isArray(lines)) throw new Error('settlement lines are required');
    return this.transaction(() => {
      const mismatches = [];
      const normalized = [];
      const seenOrders = new Set();
      for (const input of lines) {
        const row = input || {};
        const orderId = String(row.orderId || '');
        const providerRef = String(row.providerRef || row.paymentId || row.payoutId || '');
        const kind = String(row.kind || '');
        const amountCents = Number(row.amountCents);
        const feeCents = Number(row.feeCents || 0);
        const currency = String(row.currency || 'CNY');
        const status = String(row.status || '');
        if (!orderId || !providerRef || !Number.isSafeInteger(amountCents)
            || !Number.isSafeInteger(feeCents)) {
          mismatches.push({ code: 'invalid-provider-line', providerRef, orderId });
          continue;
        }
        normalized.push({
          providerRef,
          orderId,
          kind,
          amountCents,
          feeCents,
          currency,
          status,
          raw: row
        });
        seenOrders.add(orderId);
        const order = this.fundingOrder(orderId);
        if (!order) {
          mismatches.push({ code: 'missing-local-order', providerRef, orderId });
          continue;
        }
        if (order.provider !== providerName || order.kind !== kind) {
          mismatches.push({
            code: 'provider-or-kind-mismatch',
            providerRef,
            orderId,
            localProvider: order.provider,
            localKind: order.kind
          });
        }
        if (order.amountCents !== amountCents || order.feeCents !== feeCents
            || order.currency !== currency) {
          mismatches.push({
            code: 'amount-or-fee-mismatch',
            providerRef,
            orderId,
            localAmountCents: order.amountCents,
            providerAmountCents: amountCents,
            localFeeCents: order.feeCents,
            providerFeeCents: feeCents
          });
        }
        if (order.providerRef && order.providerRef !== providerRef) {
          mismatches.push({
            code: 'provider-ref-mismatch',
            providerRef,
            orderId,
            localProviderRef: order.providerRef
          });
        }
        if (order.status !== status) {
          mismatches.push({
            code: 'status-mismatch',
            providerRef,
            orderId,
            localStatus: order.status,
            providerStatus: status
          });
        }
      }
      const candidates = this.db.prepare(`
        SELECT * FROM payment_funding_orders
        WHERE provider = ? AND settled_at LIKE ?
        ORDER BY settled_at ASC
      `).all(providerName, date + '%');
      for (const candidate of candidates) {
        if (!seenOrders.has(String(candidate.id))) {
          mismatches.push({
            code: 'missing-provider-line',
            orderId: String(candidate.id),
            localStatus: String(candidate.status),
            providerRef: String(candidate.provider_ref || '')
          });
        }
      }
      const runId = this.newId('set');
      const at = this.now();
      const report = {
        provider: providerName,
        settlementDate: date,
        providerLines: normalized.length,
        localLines: candidates.length,
        mismatches,
        ok: mismatches.length === 0
      };
      this.db.prepare(`
        INSERT INTO payment_settlement_runs(
          id, provider, settlement_date, status, provider_lines, local_lines,
          mismatch_count, report_json, created_at
        ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)
      `).run(
        runId,
        providerName,
        date,
        report.ok ? 'matched' : 'mismatched',
        normalized.length,
        candidates.length,
        mismatches.length,
        stableJson(report),
        at
      );
      const insertLine = this.db.prepare(`
        INSERT INTO payment_settlement_lines(
          run_id, provider_ref, order_id, kind, amount_cents, fee_cents,
          currency, status, raw_json
        ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)
      `);
      for (const line of normalized) {
        insertLine.run(
          runId,
          line.providerRef,
          line.orderId,
          line.kind,
          line.amountCents,
          line.feeCents,
          line.currency,
          line.status,
          stableJson(line.raw)
        );
      }
      return Object.assign({ runId, createdAt: at }, report);
    });
  }

  readiness() {
    const ledger = this.verifyIntegrity();
    const intents = this.verifyIntentIntegrity();
    const pending = this.db.prepare(`
      SELECT COUNT(*) AS count FROM payment_outbox
      WHERE status IN ('pending', 'dead')
    `).get();
    return {
      ok: ledger.ok && intents.ok,
      ledger,
      intents,
      outboxPending: Number(pending && pending.count) || 0,
      schemaVersion: this.getMeta('schema_version')
    };
  }
}

module.exports = {
  PaymentDatabase,
  cents,
  money,
  stableJson
};
