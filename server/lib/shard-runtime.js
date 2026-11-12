'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

function stableShard(key, shardCount) {
  const count = Math.max(1, Math.floor(Number(shardCount) || 1));
  const digest = crypto.createHash('sha256').update(String(key || '')).digest();
  return digest.readUInt32BE(0) % count;
}

function clone(value) {
  return value == null ? value : JSON.parse(JSON.stringify(value));
}

class ShardDirectory {
  constructor(options) {
    this.shardCount = Math.max(1, Math.floor(Number(options && options.shardCount) || 1));
    this.file = options && options.file ? String(options.file) : '';
    this.readJson = options && options.readJson;
    this.writeJson = options && options.writeJson;
    this.assignments = {};
    this.load();
  }

  load() {
    if (!this.file || typeof this.readJson !== 'function') return;
    const raw = this.readJson(this.file, { assignments: {} });
    this.assignments = raw && raw.assignments && typeof raw.assignments === 'object'
      ? raw.assignments
      : {};
  }

  save() {
    if (!this.file || typeof this.writeJson !== 'function') return;
    fs.mkdirSync(path.dirname(this.file), { recursive: true });
    this.writeJson(this.file, { assignments: this.assignments });
  }

  shardFor(kind, id) {
    const entityKind = String(kind || 'entity');
    const entityId = String(id || '');
    if (!entityId) throw new Error('entity id is required');
    const key = entityKind + ':' + entityId;
    if (Number.isInteger(this.assignments[key])) {
      return this.assignments[key] % this.shardCount;
    }
    const shard = stableShard(key, this.shardCount);
    this.assignments[key] = shard;
    this.save();
    return shard;
  }

  userShard(userId) {
    return this.shardFor('user', userId);
  }

  chatShard(chatId) {
    return this.shardFor('chat', chatId);
  }
}

class VersionedEntityLog {
  constructor(options) {
    this.file = String(options && options.file || '');
    this.fsync = !options || options.fsync !== false;
    this.strict = !options || options.strict !== false;
    this.entities = new Map();
    this.eventIds = new Set();
    this.eventsById = new Map();
    if (!this.file) throw new Error('entity log file is required');
    this.load();
    if (this.strict) {
      const integrity = this.verify();
      if (!integrity.ok) {
        throw new Error('shard event log integrity failed: ' + JSON.stringify(integrity.failures.slice(0, 5)));
      }
    }
  }

  load() {
    if (!fs.existsSync(this.file)) return;
    const rows = fs.readFileSync(this.file, 'utf8').split('\n').filter(Boolean);
    for (const raw of rows) {
      let event;
      try { event = JSON.parse(raw); } catch (_) { continue; }
      if (!event || !event.eventId || this.eventIds.has(event.eventId)) continue;
      this.applyLoaded(event);
    }
  }

  validate(event) {
    if (!event || typeof event !== 'object') throw new Error('invalid event');
    const eventId = String(event.eventId || '');
    const entityType = String(event.entityType || '');
    const entityId = String(event.entityId || '');
    const version = Number(event.version);
    if (!eventId) throw new Error('eventId is required');
    if (!entityType || !entityId) throw new Error('entity identity is required');
    if (!Number.isSafeInteger(version) || version <= 0) throw new Error('version must be a positive integer');
    return { eventId, entityType, entityId, version };
  }

  entityKey(entityType, entityId) {
    return entityType + ':' + entityId;
  }

  applyLoaded(event) {
    const { eventId } = this.validate(event);
    const key = this.entityKey(event.entityType, event.entityId);
    this.eventIds.add(eventId);
    this.eventsById.set(eventId, clone(event));
    this.entities.set(key, {
      entityType: event.entityType,
      entityId: event.entityId,
      version: Number(event.version),
      deleted: event.deleted === true,
      payload: clone(event.payload || {}),
      lastEventId: eventId,
      writerShard: Number(event.writerShard)
    });
  }

  append(event) {
    fs.mkdirSync(path.dirname(this.file), { recursive: true });
    const fd = fs.openSync(this.file, 'a');
    try {
      fs.writeSync(fd, JSON.stringify(event) + '\n', null, 'utf8');
      if (this.fsync) fs.fsyncSync(fd);
    } finally {
      fs.closeSync(fd);
    }
  }

  apply(event, options) {
    const identity = this.validate(event);
    if (this.eventIds.has(identity.eventId)) {
      return { status: 'duplicate', state: this.get(identity.entityType, identity.entityId) };
    }
    if (options && options.expectedShard != null
        && event.writerShard != null
        && Number(event.writerShard) !== Number(options.expectedShard)) {
      return { status: 'wrong-shard' };
    }

    const key = this.entityKey(identity.entityType, identity.entityId);
    const current = this.entities.get(key);
    if (current) {
      if (identity.version < current.version) return { status: 'stale', state: clone(current) };
      if (identity.version === current.version) return { status: 'conflict', state: clone(current) };
      if (current.deleted && event.allowAfterTombstone !== true) {
        return { status: 'tombstoned', state: clone(current) };
      }
    }

    this.append(event);
    const state = {
      entityType: identity.entityType,
      entityId: identity.entityId,
      version: identity.version,
      deleted: event.deleted === true,
      payload: clone(event.payload || {}),
      lastEventId: identity.eventId,
      writerShard: Number(event.writerShard)
    };
    this.entities.set(key, state);
    this.eventIds.add(identity.eventId);
    this.eventsById.set(identity.eventId, clone(event));
    return { status: 'applied', state: clone(state) };
  }

  get(entityType, entityId) {
    const state = this.entities.get(this.entityKey(entityType, entityId));
    return state ? clone(state) : null;
  }

  list(entityType) {
    return Array.from(this.entities.values())
      .filter((state) => state.entityType === entityType)
      .map((state) => clone(state));
  }

  event(eventId) {
    return this.eventsById.get(String(eventId || '')) || null;
  }

  verify() {
    if (!fs.existsSync(this.file)) return { ok: true, events: 0, entities: 0, failures: [] };
    const failures = [];
    const ids = new Set();
    const versions = new Map();
    const tombstones = new Set();
    let events = 0;
    const lines = fs.readFileSync(this.file, 'utf8').split('\n');
    lines.forEach((raw, index) => {
      if (!raw.trim()) return;
      let event;
      try { event = JSON.parse(raw); }
      catch (_) {
        failures.push({ line: index + 1, code: 'corrupt-json' });
        return;
      }
      events += 1;
      let identity;
      try { identity = this.validate(event); }
      catch (error) {
        failures.push({ line: index + 1, code: 'invalid-event', message: error.message });
        return;
      }
      if (ids.has(identity.eventId)) {
        failures.push({ line: index + 1, code: 'duplicate-event-id', eventId: identity.eventId });
        return;
      }
      ids.add(identity.eventId);
      const key = this.entityKey(identity.entityType, identity.entityId);
      const lastVersion = Number(versions.get(key) || 0);
      if (identity.version <= lastVersion) {
        failures.push({
          line: index + 1,
          code: identity.version === lastVersion ? 'duplicate-version' : 'version-regression',
          entity: key,
          version: identity.version,
          previousVersion: lastVersion
        });
      }
      if (tombstones.has(key) && event.allowAfterTombstone !== true) {
        failures.push({ line: index + 1, code: 'tombstone-bypass', entity: key });
      }
      versions.set(key, Math.max(lastVersion, identity.version));
      if (event.deleted === true) tombstones.add(key);
      else if (event.allowAfterTombstone === true) tombstones.delete(key);
    });
    return {
      ok: failures.length === 0,
      events,
      entities: versions.size,
      failures
    };
  }
}

class ShardCluster {
  constructor(options) {
    const opts = options || {};
    this.shardCount = Math.max(1, Math.floor(Number(opts.shardCount) || 1));
    this.dataDir = String(opts.dataDir || '');
    if (!this.dataDir) throw new Error('cluster dataDir is required');
    this.directory = opts.directory || new ShardDirectory({
      shardCount: this.shardCount,
      file: path.join(this.dataDir, 'shard-assignments.json'),
      readJson: opts.readJson,
      writeJson: opts.writeJson
    });
    this.readJson = opts.readJson;
    this.writeJson = opts.writeJson;
    this.logs = new Map();
  }

  log(shard) {
    const index = Number(shard);
    if (!this.logs.has(index)) {
      this.logs.set(index, new VersionedEntityLog({
        file: path.join(this.dataDir, 'shard-' + index + '-events.jsonl'),
        fsync: true
      }));
    }
    return this.logs.get(index);
  }

  ownerShard(entityType, entityId) {
    return this.directory.shardFor(entityType, entityId);
  }

  apply(entityType, entityId, event) {
    const owner = this.ownerShard(entityType, entityId);
    const next = Object.assign({}, event, {
      entityType,
      entityId,
      writerShard: owner
    });
    return this.log(owner).apply(next, { expectedShard: owner });
  }

  get(entityType, entityId) {
    return this.log(this.ownerShard(entityType, entityId)).get(entityType, entityId);
  }

  list(entityType) {
    const rows = [];
    for (let shard = 0; shard < this.shardCount; shard += 1) {
      rows.push(...this.log(shard).list(entityType));
    }
    return rows;
  }

  event(entityType, entityId, eventId) {
    return this.log(this.ownerShard(entityType, entityId)).event(eventId);
  }

  verify() {
    const shards = [];
    let ok = true;
    for (let shard = 0; shard < this.shardCount; shard += 1) {
      const result = this.log(shard).verify();
      if (!result.ok) ok = false;
      shards.push(Object.assign({ shard }, result));
    }
    return { ok, shards };
  }
}

module.exports = { stableShard, ShardDirectory, VersionedEntityLog, ShardCluster };
