'use strict';

const fs = require('fs');
const path = require('path');
const { MessageReliabilityStore } = require('./message-reliability');
const { MessageWritePipeline } = require('./message-write-pipeline');
const { GroupMembershipStore } = require('./group-membership-store');
const { GroupMessagePlane } = require('./group-message-plane');
const { GroupTimelineService } = require('./group-timeline-service');
const { GroupDeletionStore } = require('./group-deletion-store');

function safeThreadName(groupId) {
  return String(groupId || '').replace(/[^A-Za-z0-9._-]/g, '_') + '.jsonl';
}

class JsonlThreadStore {
  constructor(dataDir) {
    this.dir = path.join(dataDir, 'threads');
    fs.mkdirSync(this.dir, { recursive: true });
    this.ids = new Map();
  }

  file(groupId) {
    return path.join(this.dir, safeThreadName(groupId));
  }

  ensureIds(groupId) {
    const key = String(groupId || '');
    if (this.ids.has(key)) return this.ids.get(key);
    const found = new Set();
    const file = this.file(key);
    try {
      const lines = fs.readFileSync(file, 'utf8').split('\n').filter(Boolean);
      lines.forEach((line) => {
        try {
          const row = JSON.parse(line);
          if (row && row.id) found.add(String(row.id));
        } catch (_) { /* corrupt rows are handled by the audit tool */ }
      });
    } catch (_) { /* new thread */ }
    this.ids.set(key, found);
    return found;
  }

  async read(groupId) {
    try {
      return fs.readFileSync(this.file(groupId), 'utf8')
        .split('\n')
        .filter(Boolean)
        .map((line) => JSON.parse(line));
    } catch (_) {
      return [];
    }
  }

  async hasMessage(groupId, messageId) {
    return this.ensureIds(groupId).has(String(messageId || ''));
  }

  async append(groupId, message) {
    const id = String(message && message.id || '');
    const ids = this.ensureIds(groupId);
    if (ids.has(id)) return;
    fs.appendFileSync(this.file(groupId), JSON.stringify(message) + '\n', 'utf8');
    ids.add(id);
  }
}

class GroupMessageCell {
  constructor(options) {
    const opts = options || {};
    this.cellId = String(opts.cellId || '');
    this.dataDir = path.resolve(String(opts.dataDir || ''));
    if (!this.cellId) throw new Error('cellId is required');
    if (!this.dataDir) throw new Error('dataDir is required');
    fs.mkdirSync(this.dataDir, { recursive: true });
    this.reliability = new MessageReliabilityStore({
      databaseFile: path.join(this.dataDir, 'message-reliability.sqlite3'),
      now: opts.now,
      uid: opts.uid
    });
    this.membership = new GroupMembershipStore({
      databaseFile: path.join(this.dataDir, 'group-membership.sqlite3'),
      now: opts.now
    });
    this.deletions = new GroupDeletionStore({
      databaseFile: path.join(this.dataDir, 'group-deletions.sqlite3'),
      now: opts.now
    });
    this.threadStore = new JsonlThreadStore(this.dataDir);
    this.writePipeline = new MessageWritePipeline({
      reliability: this.reliability,
      threadStore: this.threadStore,
      now: opts.now
    });
    this.plane = new GroupMessagePlane({
      writePipeline: this.writePipeline,
      membership: this.membership,
      realtime: opts.realtime,
      pushQueue: opts.pushQueue,
      presence: opts.presence,
      largeGroupThreshold: opts.largeGroupThreshold,
      pushPartitionSize: opts.pushPartitionSize,
      schedule: opts.schedule
    });
    this.timeline = new GroupTimelineService({
      reliability: this.reliability,
      membership: this.membership,
      cleared: opts.cleared,
      deletions: this.deletions
    });
  }

  join(groupId, userId, joinedSeq) {
    return this.membership.join(groupId, userId, joinedSeq);
  }

  leave(groupId, userId, leftSeq) {
    return this.membership.leave(groupId, userId, leftSeq);
  }

  send(groupId, senderId, message) {
    return this.plane.deliver(groupId, senderId, message);
  }

  read(options) {
    return this.timeline.read(options);
  }

  unread(groupId, userId, deviceId) {
    return this.timeline.unread(groupId, userId, deviceId);
  }

  acknowledge(groupId, userId, deviceId, seq) {
    return this.timeline.acknowledge(groupId, userId, deviceId, seq);
  }

  markRead(groupId, userId, deviceId, seq) {
    return this.timeline.markRead(groupId, userId, deviceId, seq);
  }

  hideForUser(groupId, userId, messageId) {
    return this.deletions.hideForUser(groupId, userId, messageId);
  }

  clearForUser(groupId, userId, seq) {
    return this.deletions.clearForUser(groupId, userId, seq);
  }

  recall(groupId, messageId, seq, actorUserId) {
    return this.deletions.recall(groupId, messageId, seq, actorUserId);
  }

  takedown(groupId, messageId, seq, actorUserId, reason) {
    return this.deletions.takedown(groupId, messageId, seq, actorUserId, reason);
  }

  waitForFanout() {
    return this.plane.waitForIdle();
  }

  stats() {
    return {
      cellId: this.cellId,
      dataDirName: path.basename(this.dataDir),
      fanout: Object.assign({}, this.plane.fanoutStats),
      lastFanoutError: this.plane.lastFanoutError
    };
  }

  close() {
    this.membership.close();
    this.deletions.close();
    this.reliability.close();
  }
}

module.exports = {
  GroupMessageCell,
  JsonlThreadStore
};
