'use strict';

const fs = require('fs');
const path = require('path');
const { GroupMessageCell } = require('./group-message-cell');

class GroupMessageShadow {
  constructor(options) {
    const opts = options || {};
    if (!opts.dataDir) throw new Error('shadow dataDir is required');
    this.rootDir = path.resolve(String(opts.dataDir));
    this.largeGroupThreshold = opts.largeGroupThreshold;
    this.pushPartitionSize = opts.pushPartitionSize;
    this.now = opts.now;
    this.uid = opts.uid;
    this.cells = new Map();
    this.groups = new Map();
    this.report = {
      observedMessages: 0,
      importedMessages: 0,
      duplicateMessages: 0,
      deniedMessages: 0,
      conflicts: 0,
      errors: []
    };
  }

  cell(cellId) {
    const id = String(cellId || 'shadow-cell');
    if (this.cells.has(id)) return this.cells.get(id);
    const realtime = {
      userEvents: [],
      groupSignals: [],
      async notifyUser(userId, event) {
        this.userEvents.push({ userId, event });
      },
      async publishGroupSignal(groupId, event) {
        this.groupSignals.push({ groupId, event });
      }
    };
    const pushQueue = {
      jobs: [],
      async enqueueUser(userId, event) {
        this.jobs.push({ kind: 'user', userId, event });
      },
      async enqueuePartition(job) {
        this.jobs.push({ kind: 'partition', job });
      }
    };
    const cell = new GroupMessageCell({
      cellId: id,
      dataDir: path.join(this.rootDir, id),
      realtime,
      pushQueue,
      presence: null,
      largeGroupThreshold: this.largeGroupThreshold,
      pushPartitionSize: this.pushPartitionSize,
      schedule: (work) => setImmediate(work),
      now: this.now,
      uid: this.uid
    });
    this.cells.set(id, cell);
    return cell;
  }

  ensureGroup(cellId, chat) {
    const groupId = String(chat && chat.id || '');
    const key = String(cellId || 'shadow-cell') + '|' + groupId;
    if (this.groups.has(key)) return;
    const cell = this.cell(cellId);
    const members = Array.from(new Set(chat && chat.memberIds || []));
    members.forEach((userId) => cell.join(groupId, String(userId), 1));
    this.groups.set(key, { groupId, members: members.length });
  }

  observe(options) {
    const opts = options || {};
    const cellId = String(opts.cellId || 'shadow-cell');
    const chat = opts.chat || {};
    const message = opts.message || {};
    this.ensureGroup(cellId, chat);
    const cell = this.cell(cellId);
    const result = cell.mirror(chat.id, opts.senderId || message.senderId, message);
    this.report.observedMessages += 1;
    if (result.ok) {
      this.report.importedMessages += Number(result.imported && result.imported.imported) || 0;
      this.report.duplicateMessages += result.fanout === 'duplicate' ? 1 : 0;
    } else if (result.denied) {
      this.report.deniedMessages += 1;
    } else if (result.conflict) {
      this.report.conflicts += 1;
    }
    if (!result.ok && this.report.errors.length < 500) {
      this.report.errors.push({
        groupId: String(chat.id || ''),
        messageId: String(message.id || ''),
        seq: Number(message.seq) || 0,
        error: String(result.error || 'mirror failed')
      });
    }
    return result;
  }

  async waitForFanout() {
    await Promise.all(Array.from(this.cells.values()).map((cell) => cell.waitForFanout()));
  }

  snapshot() {
    const cells = Array.from(this.cells.values()).map((cell) => cell.stats());
    return {
      version: 1,
      rootName: path.basename(this.rootDir),
      groups: this.groups.size,
      cells,
      report: Object.assign({}, this.report, {
        errors: this.report.errors.slice()
      })
    };
  }

  writeReport(file) {
    const target = path.resolve(String(file || path.join(this.rootDir, 'shadow-report.json')));
    fs.mkdirSync(path.dirname(target), { recursive: true });
    const temporary = target + '.' + process.pid + '.tmp';
    fs.writeFileSync(temporary, JSON.stringify(this.snapshot(), null, 2), 'utf8');
    fs.renameSync(temporary, target);
    return target;
  }

  close() {
    for (const cell of this.cells.values()) cell.close();
    this.cells.clear();
  }
}

module.exports = { GroupMessageShadow };
