'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { canonical, hash } = require('./shard-snapshot');

class PaymentIntentEngine {
  constructor(options) {
    const opts = options || {};
    this.file = String(opts.file || '');
    this.keyring = opts.keyring;
    this.tokens = opts.tokens;
    this.now = typeof opts.now === 'function' ? opts.now : () => new Date().toISOString();
    if (!this.file) throw new Error('payment intent journal is required');
    if (!this.keyring) throw new Error('payment keyring is required');
    if (!this.tokens) throw new Error('payment token vault is required');
    this.intents = new Map();
    this.eventsById = new Map();
    this.commands = new Map();
    this.usedNonces = new Set();
    this.lastHash = '';
    this.entries = 0;
    this.load();
  }

  load() {
    if (!fs.existsSync(this.file)) return;
    const lines = fs.readFileSync(this.file, 'utf8').split('\n');
    for (let index = 0; index < lines.length; index += 1) {
      const line = lines[index].trim();
      if (!line) continue;
      let event;
      try { event = JSON.parse(line); }
      catch (_) { throw new Error('payment intent journal corruption at line ' + (index + 1)); }
      const unsigned = Object.assign({}, event);
      delete unsigned.signature;
      delete unsigned.hash;
      if (!this.keyring.verify(unsigned, event.signature)
          || event.prevHash !== this.lastHash
          || hash(unsigned) !== event.hash) {
        throw new Error('payment intent journal integrity failure at line ' + (index + 1));
      }
      this.applyEvent(event, false);
      this.lastHash = event.hash;
      this.entries += 1;
    }
  }

  append(event) {
    const unsigned = Object.assign({}, event, {
      prevHash: this.lastHash
    });
    const signature = this.keyring.sign(unsigned);
    const sealed = Object.assign({}, unsigned, {
      signature,
      hash: hash(unsigned)
    });
    fs.mkdirSync(path.dirname(this.file), { recursive: true });
    const fd = fs.openSync(this.file, 'a');
    try {
      fs.writeSync(fd, JSON.stringify(sealed) + '\n', null, 'utf8');
      fs.fsyncSync(fd);
    } finally {
      fs.closeSync(fd);
    }
    this.applyEvent(sealed, true);
    this.lastHash = sealed.hash;
    this.entries += 1;
    return this.cloneIntent(sealed.intentId);
  }

  cloneIntent(intentId) {
    const value = this.intents.get(String(intentId || ''));
    return value ? JSON.parse(JSON.stringify(value)) : null;
  }

  create(input) {
    const row = input || {};
    const intentId = String(row.intentId || '');
    const commandId = String(row.commandId || '');
    const duplicate = this.commands.get(commandId);
    if (duplicate) return Object.assign(this.cloneIntent(duplicate), { idempotent: true });
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
    if (this.intents.has(intentId)) throw new Error('payment intent already exists');
    return this.append({
      eventId: this.eventId(intentId, commandId),
      commandId,
      intentId,
      type: 'created',
      version: 1,
      userId: String(row.userId),
      merchantId: String(row.merchantId),
      deviceId: String(row.deviceId),
      amountCents,
      currency: String(row.currency),
      metadata,
      createdAt: this.now()
    });
  }

  authorize(input) {
    const row = input || {};
    const intent = this.requireIntent(row.intentId);
    const duplicate = this.commands.get(String(row.commandId || ''));
    if (duplicate) return Object.assign(this.cloneIntent(intent.id), { idempotent: true });
    if (intent.status !== 'created') throw new Error('payment intent is not authorizable');
    const expected = {
      intentId: intent.id,
      userId: intent.userId,
      merchantId: intent.merchantId,
      deviceId: intent.deviceId,
      amountCents: intent.amountCents,
      currency: intent.currency,
      nonce: String(row.nonce || ''),
      expiresAt: String(row.expiresAt || '')
    };
    if (!expected.nonce || expected.nonce.length < 16) throw new Error('authorization nonce is required');
    const expiresAt = Date.parse(expected.expiresAt);
    const at = Date.parse(this.now());
    if (!Number.isFinite(expiresAt) || expiresAt <= at || expiresAt > at + 5 * 60 * 1000) {
      throw new Error('authorization has expired or has an invalid lifetime');
    }
    if (this.usedNonces.has(expected.nonce)) throw new Error('authorization nonce was already used');
    const verified = this.tokens.verifyAuthorization(row.tokenId, expected, row.signature);
    if (!verified.ok) throw new Error(verified.reason);
    return this.append({
      eventId: this.eventId(intent.id, row.commandId),
      commandId: String(row.commandId || ''),
      intentId: intent.id,
      type: 'authorized',
      version: intent.version + 1,
      tokenId: String(row.tokenId),
      nonce: expected.nonce,
      network: verified.token.network,
      last4: verified.token.last4,
      authorizedAt: this.now()
    });
  }

  capture(input) {
    const row = input || {};
    let intent = this.requireIntent(row.intentId);
    const duplicate = this.commands.get(String(row.commandId || '') + ':captured');
    if (duplicate && intent.status === 'captured') {
      return Object.assign(this.cloneIntent(intent.id), { idempotent: true });
    }
    if (intent.status !== 'authorized' && intent.status !== 'capture_pending') {
      throw new Error('payment intent is not capturable');
    }
    if (typeof row.settle !== 'function') throw new Error('idempotent ledger settlement is required');
    if (intent.status === 'authorized') {
      intent = this.append({
        eventId: this.eventId(intent.id, row.commandId + ':pending'),
        commandId: String(row.commandId || '') + ':pending',
        intentId: intent.id,
        type: 'capture_pending',
        version: intent.version + 1,
        ledgerRef: String(row.ledgerRef || ('intent:capture:' + intent.id)),
        pendingAt: this.now()
      });
    }
    let settlement;
    try {
      settlement = row.settle({
        intentId: intent.id,
        userId: intent.userId,
        merchantId: intent.merchantId,
        amountCents: intent.amountCents,
        currency: intent.currency,
        ledgerRef: intent.ledgerRef
      });
    } catch (error) {
      throw new Error('ledger settlement failed: ' + String(error.message || error));
    }
    if (!settlement || settlement.ok !== true || !settlement.reference) {
      throw new Error('ledger settlement was not confirmed');
    }
    return this.append({
      eventId: this.eventId(intent.id, row.commandId + ':captured'),
      commandId: String(row.commandId || '') + ':captured',
      intentId: intent.id,
      type: 'captured',
      version: intent.version + 1,
      settlementReference: String(settlement.reference),
      capturedAt: this.now()
    });
  }

  refund(input) {
    const row = input || {};
    let intent = this.requireIntent(row.intentId);
    const commandId = String(row.commandId || '');
    const duplicate = this.commands.get(commandId + ':refunded');
    if (duplicate) return Object.assign(this.cloneIntent(intent.id), { idempotent: true });
    if (!['captured', 'partially_refunded', 'refund_pending'].includes(intent.status)) {
      throw new Error('payment intent is not refundable');
    }
    const requestedCents = Number(row.amountCents);
    const amountCents = intent.status === 'refund_pending'
      ? intent.pendingRefundCents
      : requestedCents;
    if (intent.status === 'refund_pending' && Number.isSafeInteger(requestedCents)
        && requestedCents !== amountCents) {
      throw new Error('refund retry amount does not match the pending refund');
    }
    if (!Number.isSafeInteger(amountCents) || amountCents <= 0
        || amountCents > intent.amountCents - intent.refundedCents) {
      throw new Error('invalid refund amount');
    }
    if (typeof row.settle !== 'function') throw new Error('idempotent refund settlement is required');
    if (intent.status !== 'refund_pending') {
      intent = this.append({
        eventId: this.eventId(intent.id, commandId + ':pending'),
        commandId: commandId + ':pending',
        intentId: intent.id,
        type: 'refund_pending',
        version: intent.version + 1,
        amountCents,
        ledgerRef: String(row.ledgerRef || ('intent:refund:' + intent.id + ':' + commandId)),
        pendingAt: this.now()
      });
    }
    const settlement = row.settle({
      intentId: intent.id,
      userId: intent.userId,
      merchantId: intent.merchantId,
      amountCents,
      currency: intent.currency,
      ledgerRef: intent.ledgerRef
    });
    if (!settlement || settlement.ok !== true || !settlement.reference) {
      throw new Error('refund settlement was not confirmed');
    }
    const refundedCents = intent.refundedCents + amountCents;
    return this.append({
      eventId: this.eventId(intent.id, commandId + ':refunded'),
      commandId: commandId + ':refunded',
      intentId: intent.id,
      type: refundedCents === intent.amountCents ? 'refunded' : 'partially_refunded',
      version: intent.version + 1,
      amountCents,
      refundedCents,
      settlementReference: String(settlement.reference),
      refundedAt: this.now()
    });
  }

  void(input) {
    const intent = this.requireIntent(input && input.intentId);
    if (intent.status !== 'authorized') throw new Error('payment intent is not voidable');
    return this.append({
      eventId: this.eventId(intent.id, input.commandId),
      commandId: String(input.commandId || ''),
      intentId: intent.id,
      type: 'voided',
      version: intent.version + 1,
      voidedAt: this.now()
    });
  }

  dispute(input) {
    const intent = this.requireIntent(input && input.intentId);
    if (!['captured', 'partially_refunded', 'refunded'].includes(intent.status)) {
      throw new Error('payment intent is not disputable');
    }
    return this.append({
      eventId: this.eventId(intent.id, input.commandId),
      commandId: String(input.commandId || ''),
      intentId: intent.id,
      type: 'disputed',
      version: intent.version + 1,
      disputeId: String(input.disputeId || ''),
      reason: String(input.reason || ''),
      disputedAt: this.now()
    });
  }

  eventId(intentId, commandId) {
    const id = String(commandId || '');
    if (!id) throw new Error('commandId is required');
    return 'pie_' + crypto.createHash('sha256')
      .update(String(intentId) + '|' + id).digest('hex');
  }

  requireIntent(intentId) {
    const intent = this.intents.get(String(intentId || ''));
    if (!intent) throw new Error('payment intent not found');
    return intent;
  }

  applyEvent(event, live) {
    if (!event || !event.intentId || !event.type) throw new Error('invalid payment intent event');
    if (this.commands.has(event.commandId)) {
      throw new Error('duplicate payment command');
    }
    let intent = this.intents.get(event.intentId);
    if (event.type === 'created') {
      if (intent) throw new Error('duplicate payment intent');
      intent = {
        id: event.intentId,
        userId: event.userId,
        merchantId: event.merchantId,
        deviceId: event.deviceId,
        amountCents: event.amountCents,
        currency: event.currency,
        metadata: event.metadata || {},
        refundedCents: 0,
        status: 'created',
        version: event.version,
        createdAt: event.createdAt
      };
    } else {
      if (!intent || event.version !== intent.version + 1) {
        throw new Error('payment intent version sequence is invalid');
      }
      intent.version = event.version;
      if (event.type === 'authorized') {
        intent.status = 'authorized';
        intent.tokenId = event.tokenId;
        intent.nonce = event.nonce;
        intent.last4 = event.last4;
        intent.authorizedAt = event.authorizedAt;
        this.usedNonces.add(event.nonce);
      } else if (event.type === 'capture_pending') {
        intent.status = 'capture_pending';
        intent.ledgerRef = event.ledgerRef;
      } else if (event.type === 'captured') {
        intent.status = 'captured';
        intent.settlementReference = event.settlementReference;
        intent.capturedAt = event.capturedAt;
      } else if (event.type === 'voided') {
        intent.status = 'voided';
      } else if (event.type === 'refund_pending') {
        intent.status = 'refund_pending';
        intent.pendingRefundCents = event.amountCents;
        intent.ledgerRef = event.ledgerRef;
      } else if (event.type === 'partially_refunded') {
        intent.status = 'partially_refunded';
        intent.refundedCents = event.refundedCents;
        intent.pendingRefundCents = 0;
      } else if (event.type === 'refunded') {
        intent.status = 'refunded';
        intent.refundedCents = event.refundedCents;
        intent.pendingRefundCents = 0;
      } else if (event.type === 'disputed') {
        intent.status = 'disputed';
        intent.disputeId = event.disputeId;
      } else {
        throw new Error('unknown payment intent event type');
      }
    }
    this.intents.set(intent.id, intent);
    this.eventsById.set(event.eventId, event);
    this.commands.set(event.commandId, intent.id);
    if ((intent.status === 'voided' || intent.status === 'refunded')
        && live && event.type !== 'voided' && event.type !== 'refunded') {
      throw new Error('invalid transition after terminal payment state');
    }
  }
}

module.exports = { PaymentIntentEngine };
