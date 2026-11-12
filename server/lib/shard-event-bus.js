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
    for (const line of fs.readFileSync(this.file(), 'utf8').split('\n')) {
      if (!line.trim()) continue;
      try { rows.push(JSON.parse(line)); } catch (_) { /* skip corrupt line */ }
    }
    return rows.slice(Math.max(0, Number(offset) || 0));
  }

  replayInto(cluster) {
    const cursorFile = path.join(this.dataDir, 'shard-event-cursor.json');
    let cursor = 0;
    try {
      const saved = JSON.parse(fs.readFileSync(cursorFile, 'utf8'));
      cursor = Math.max(0, Number(saved.cursor) || 0);
    } catch (_) { cursor = 0; }
    const rows = this.read(cursor);
    for (const event of rows) {
      cluster.apply(event.entityType, event.entityId, event);
      cursor += 1;
    }
    fs.writeFileSync(cursorFile, JSON.stringify({ cursor }), 'utf8');
    return { replayed: rows.length, cursor };
  }
}

module.exports = { ShardEventBus };
