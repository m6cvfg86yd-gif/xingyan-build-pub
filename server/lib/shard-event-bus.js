'use strict';

const fs = require('fs');
const path = require('path');

class ShardEventBus {
  constructor(options) {
    const opts = options || {};
    this.dataDir = String(opts.dataDir || '');
    if (!this.dataDir) throw new Error('event bus dataDir is required');
    this.shardCount = Math.max(1, Math.floor(Number(opts.shardCount) || 1));
    this.topologyId = String(opts.topologyId || 'shards-' + this.shardCount);
    this.fsync = opts.fsync !== false;
  }

  shardOf(event) {
    const value = Math.floor(Number(event && event.writerShard));
    return Number.isInteger(value) && value >= 0 && value < this.shardCount ? value : 0;
  }

  file(shard) {
    const index = Math.floor(Number(shard) || 0);
    if (!Number.isInteger(index) || index < 0 || index >= this.shardCount) {
      throw new Error('shard event bus shard is out of range');
    }
    const safeTopology = this.topologyId.replace(/[^A-Za-z0-9._-]/g, '_');
    return path.join(this.dataDir, 'topologies', safeTopology,
      'shard-event-bus-' + index + '.jsonl');
  }

  publish(event) {
    if (!event || !event.eventId) throw new Error('eventId is required');
    const envelope = Object.assign({}, event, {
      publishedAt: event.publishedAt || new Date().toISOString()
    });
    const file = this.file(this.shardOf(envelope));
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const fd = fs.openSync(file, 'a');
    try {
      fs.writeSync(fd, JSON.stringify(envelope) + '\n', null, 'utf8');
      if (this.fsync) fs.fsyncSync(fd);
    } finally {
      fs.closeSync(fd);
    }
    return envelope;
  }

  read(offset, shard) {
    const file = this.file(shard);
    if (!fs.existsSync(file)) return [];
    const rows = [];
    const eventIds = new Set();
    const lines = fs.readFileSync(file, 'utf8').split('\n');
    for (let index = 0; index < lines.length; index += 1) {
      const line = lines[index];
      if (!line.trim()) continue;
      let event;
      try {
        event = JSON.parse(line);
      } catch (error) {
        throw new Error('shard event bus corruption at line ' + (index + 1)
          + ': ' + String(error && error.message || error));
      }
      if (!event || !event.eventId || !event.entityType || !event.entityId
          || !Number.isSafeInteger(Number(event.version)) || Number(event.version) <= 0) {
        throw new Error('shard event bus invalid event at line ' + (index + 1));
      }
      if (event.topologyId && String(event.topologyId) !== this.topologyId) {
        throw new Error('shard event bus topology mismatch at line ' + (index + 1));
      }
      if (eventIds.has(event.eventId)) {
        throw new Error('shard event bus duplicate event at line ' + (index + 1)
          + ': ' + event.eventId);
      }
      eventIds.add(event.eventId);
      rows.push(event);
    }
    return rows.slice(Math.max(0, Number(offset) || 0));
  }

  replayInto(cluster) {
    if (cluster.topologyId && cluster.topologyId !== this.topologyId) {
      throw new Error('event bus topology mismatch');
    }
    const safeTopology = this.topologyId.replace(/[^A-Za-z0-9._-]/g, '_');
    const cursorFile = path.join(this.dataDir, 'topologies', safeTopology,
      'shard-event-cursor.json');
    let cursors = {};
    try {
      const saved = JSON.parse(fs.readFileSync(cursorFile, 'utf8'));
      cursors = saved && saved.shards && typeof saved.shards === 'object'
        ? Object.assign({}, saved.shards)
        : { 0: saved && saved.cursor };
    } catch (error) {
      if (error && error.code !== 'ENOENT') {
        throw new Error('shard event cursor corruption: ' + String(error.message || error));
      }
      cursors = {};
    }
    let replayed = 0;
    for (let shard = 0; shard < this.shardCount; shard += 1) {
      const cursor = Math.max(0, Number(cursors[shard]) || 0);
      const rows = this.read(cursor, shard);
      if (!rows.length && cursor > this.read(0, shard).length) {
        throw new Error('shard event cursor is beyond the event log for shard ' + shard);
      }
      let next = cursor;
      for (const event of rows) {
        const result = cluster.apply(event.entityType, event.entityId, event);
        if (result.status !== 'applied' && result.status !== 'duplicate') {
          throw new Error('shard event replay failed at ' + event.eventId
            + ': ' + result.status);
        }
        next += 1;
        replayed += 1;
      }
      cursors[shard] = next;
    }
    const temporary = cursorFile + '.tmp';
    fs.writeFileSync(temporary, JSON.stringify({ shards: cursors }), 'utf8');
    fs.renameSync(temporary, cursorFile);
    return { replayed, cursors };
  }
}

module.exports = { ShardEventBus };
