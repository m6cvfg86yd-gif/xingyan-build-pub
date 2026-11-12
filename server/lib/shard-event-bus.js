'use strict';

const fs = require('fs');
const path = require('path');

class ShardEventBus {
  constructor(options) {
    const opts = options || {};
    this.dataDir = String(opts.dataDir || '');
    if (!this.dataDir) throw new Error('event bus dataDir is required');
    this.shardCount = Math.max(1, Math.floor(Number(opts.shardCount) || 1));
    this.fsync = opts.fsync !== false;
  }

  file() {
    return path.join(this.dataDir, 'shard-event-bus.jsonl');
  }

  publish(event) {
    if (!event || !event.eventId) throw new Error('eventId is required');
    fs.mkdirSync(path.dirname(this.file()), { recursive: true });
    const envelope = Object.assign({}, event, {
      publishedAt: event.publishedAt || new Date().toISOString()
    });
    const fd = fs.openSync(this.file(), 'a');
    try {
      fs.writeSync(fd, JSON.stringify(envelope) + '\n', null, 'utf8');
      if (this.fsync) fs.fsyncSync(fd);
    } finally {
      fs.closeSync(fd);
    }
    return envelope;
  }

  read(offset) {
    if (!fs.existsSync(this.file())) return [];
    const rows = [];
    const eventIds = new Set();
    const lines = fs.readFileSync(this.file(), 'utf8').split('\n');
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
    const cursorFile = path.join(this.dataDir, 'shard-event-cursor.json');
    let cursor = 0;
    try {
      const saved = JSON.parse(fs.readFileSync(cursorFile, 'utf8'));
      cursor = Math.max(0, Number(saved.cursor) || 0);
    } catch (error) {
      if (error && error.code !== 'ENOENT') {
        throw new Error('shard event cursor corruption: ' + String(error.message || error));
      }
      cursor = 0;
    }
    const rows = this.read(cursor);
    if (!rows.length && cursor > this.read(0).length) {
      throw new Error('shard event cursor is beyond the event log');
    }
    for (const event of rows) {
      const result = cluster.apply(event.entityType, event.entityId, event);
      if (result.status !== 'applied' && result.status !== 'duplicate') {
        throw new Error('shard event replay failed at ' + event.eventId
          + ': ' + result.status);
      }
      cursor += 1;
    }
    const temporary = cursorFile + '.tmp';
    fs.writeFileSync(temporary, JSON.stringify({ cursor }), 'utf8');
    fs.renameSync(temporary, cursorFile);
    return { replayed: rows.length, cursor };
  }
}

module.exports = { ShardEventBus };
