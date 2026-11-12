'use strict';

const crypto = require('crypto');

function commandFingerprint(entityType, entityId, operation, payload) {
  return crypto.createHash('sha256').update(JSON.stringify({
    entityType: String(entityType || ''),
    entityId: String(entityId || ''),
    operation: String(operation || ''),
    payload: payload || {}
  })).digest('hex');
}

class ShardMutationGateway {
  constructor(options) {
    this.cluster = options && options.cluster;
    this.bus = options && options.bus;
    this.uid = options && options.uid;
    this.now = options && options.now;
    this.leaseManager = options && options.leaseManager;
    if (!this.cluster) throw new Error('cluster is required');
    if (typeof this.uid !== 'function') throw new Error('uid is required');
    if (typeof this.now !== 'function') this.now = () => new Date().toISOString();
  }

  read(entityType, entityId) {
    const ownerShard = this.cluster.ownerShard(entityType, entityId);
    return {
      ownerShard,
      state: this.cluster.get(entityType, entityId)
    };
  }

  submit(command) {
    const input = command || {};
    const entityType = String(input.entityType || '');
    const entityId = String(input.entityId || '');
    const operation = String(input.operation || '');
    if (!entityType || !entityId || !operation) {
      return { status: 'invalid' };
    }
    const eventId = String(input.eventId || this.uid('evt'));
    const payload = input.payload || {};
    const ownerShard = this.cluster.ownerShard(entityType, entityId);
    let writerEpoch = null;
    if (this.leaseManager) {
      const lease = this.leaseManager.validate(ownerShard);
      if (!lease.ok) {
        return {
          status: 'fenced',
          reason: lease.reason,
          eventId,
          ownerShard
        };
      }
      writerEpoch = Number(lease.lease.epoch);
    }
    const previous = this.cluster.event(entityType, entityId, eventId);
    if (previous) {
      const same = commandFingerprint(entityType, entityId, operation, payload)
        === commandFingerprint(entityType, entityId, previous.operation, previous.payload);
      return {
        status: same ? 'duplicate' : 'idempotency-conflict',
        eventId,
        ownerShard,
        state: this.cluster.get(entityType, entityId)
      };
    }

    const current = this.cluster.get(entityType, entityId);
    const currentVersion = current ? Number(current.version) || 0 : 0;
    if (input.expectedVersion != null && Number(input.expectedVersion) !== currentVersion) {
      return {
        status: 'version-conflict',
        eventId,
        ownerShard,
        expectedVersion: Number(input.expectedVersion),
        currentVersion,
        state: current
      };
    }

    const version = currentVersion + 1;
    const event = {
      eventId,
      entityType,
      entityId,
      version,
      operation,
      payload,
      deleted: input.deleted === true,
      allowAfterTombstone: input.allowAfterTombstone === true,
      writerEpoch,
      createdAt: input.createdAt || this.now()
    };
    const result = this.cluster.apply(entityType, entityId, event);
    if (result.status === 'applied' && this.bus) {
      this.bus.publish(Object.assign({}, event, {
        writerShard: ownerShard,
        topologyId: this.cluster.topologyId
      }));
    }
    return Object.assign({}, result, {
      eventId,
      ownerShard,
      version,
      fingerprint: commandFingerprint(entityType, entityId, operation, payload)
    });
  }
}

module.exports = { ShardMutationGateway, commandFingerprint };
