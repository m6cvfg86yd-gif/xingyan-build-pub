'use strict';

const fs = require('fs');
const path = require('path');

function parseCellEndpoints(value) {
  const out = {};
  String(value || '').split(',').forEach((entry) => {
    const raw = entry.trim();
    const split = raw.indexOf('=');
    if (split <= 0) return;
    const cellId = raw.slice(0, split).trim();
    const baseUrl = raw.slice(split + 1).trim().replace(/\/+$/, '');
    if (!cellId) return;
    try {
      const parsed = new URL(baseUrl);
      if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') return;
      out[cellId] = baseUrl;
    } catch (_) { }
  });
  return out;
}

class RemoteGroupCellShadow {
  constructor(options) {
    const opts = options || {};
    this.cellId = String(opts.cellId || '').trim();
    this.baseUrl = String(opts.baseUrl || '').trim().replace(/\/+$/, '');
    this.internalToken = String(opts.internalToken || '');
    this.timeoutMs = Math.max(250, Number(opts.timeoutMs) || 3000);
    this.fetchImpl = opts.fetchImpl || fetch;
    this.reportFile = opts.reportFile ? path.resolve(String(opts.reportFile)) : '';
    if (!this.cellId) throw new Error('shadow cellId is required');
    if (!this.baseUrl) throw new Error('shadow baseUrl is required');
    const parsed = new URL(this.baseUrl);
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
      throw new Error('shadow baseUrl must use http or https');
    }
    this.endpointName = parsed.origin;
    this.groups = new Map();
    this.tail = Promise.resolve();
    this.pending = 0;
    this.report = {
      observedMessages: 0,
      importedMessages: 0,
      duplicateMessages: 0,
      deniedMessages: 0,
      conflicts: 0,
      errors: []
    };
    this.lastError = '';
  }

  async request(route, method, value) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.timeoutMs);
    timeout.unref();
    const headers = {};
    if (value !== undefined) headers['Content-Type'] = 'application/json';
    if (this.internalToken) headers['X-Internal-Token'] = this.internalToken;
    try {
      const response = await this.fetchImpl(this.baseUrl + route, {
        method,
        headers,
        body: value === undefined ? undefined : JSON.stringify(value),
        signal: controller.signal
      });
      let data = {};
      try {
        data = await response.json();
      } catch (_) {
        data = {};
      }
      if (!response.ok || data.ok === false) {
        const error = new Error(data.error || 'cell request failed');
        error.status = response.status;
        error.data = data;
        throw error;
      }
      return data;
    } finally {
      clearTimeout(timeout);
    }
  }

  groupRoute(groupId) {
    return '/internal/groups/' + encodeURIComponent(groupId);
  }

  async ensureMembership(groupId, memberIds, seq) {
    const normalized = Array.from(new Set(
      (memberIds || []).map((userId) => String(userId || '')).filter(Boolean)
    ));
    const currentSeq = Math.max(1, Math.floor(Number(seq) || 1));
    let group = this.groups.get(groupId);
    if (!group) {
      group = { members: new Map() };
      this.groups.set(groupId, group);
      for (const userId of normalized) {
        await this.request(this.groupRoute(groupId) + '/join', 'POST', {
          userId,
          joinedSeq: 1
        });
        group.members.set(userId, 1);
      }
      return;
    }

    const next = new Set(normalized);
    for (const userId of normalized) {
      if (group.members.has(userId)) continue;
      await this.request(this.groupRoute(groupId) + '/join', 'POST', {
        userId,
        joinedSeq: currentSeq
      });
      group.members.set(userId, currentSeq);
    }
    for (const userId of Array.from(group.members.keys())) {
      if (next.has(userId)) continue;
      await this.request(this.groupRoute(groupId) + '/leave', 'POST', {
        userId,
        leftSeq: currentSeq
      });
      group.members.delete(userId);
    }
  }

  observe(options) {
    const opts = options || {};
    const chat = opts.chat || {};
    const message = opts.message || {};
    const snapshot = {
      groupId: String(chat.id || ''),
      senderId: String(opts.senderId || message.senderId || ''),
      memberIds: Array.from(chat.memberIds || []),
      message: Object.assign({}, message)
    };
    this.pending += 1;
    const work = this.tail.then(() => this.observeNow(snapshot));
    this.tail = work.then(() => {
      this.pending -= 1;
    }, () => {
      this.pending -= 1;
    });
    return work;
  }

  async observeNow(options) {
    const groupId = options.groupId;
    const senderId = options.senderId;
    const message = options.message;
    this.report.observedMessages += 1;
    if (!groupId || !senderId || !(Number(message.seq) > 0)) {
      return this.recordFailure({
        groupId,
        messageId: String(message.id || ''),
        seq: Number(message.seq) || 0,
        error: 'groupId, senderId and positive seq are required'
      });
    }
    const memberIds = options.memberIds.includes(senderId)
      ? options.memberIds : options.memberIds.concat(senderId);
    try {
      await this.ensureMembership(groupId, memberIds, Number(message.seq));
      const result = await this.request(
        this.groupRoute(groupId) + '/shadow',
        'POST',
        { senderId, message }
      );
      this.report.importedMessages += Number(result.imported && result.imported.imported) || 0;
      if (result.fanout === 'duplicate') this.report.duplicateMessages += 1;
      return result;
    } catch (error) {
      const data = error && error.data || {};
      if (data.denied) this.report.deniedMessages += 1;
      if (data.conflict) this.report.conflicts += 1;
      return this.recordFailure({
        groupId,
        messageId: String(message.id || ''),
        seq: Number(message.seq) || 0,
        error: String(error && error.message || error)
      });
    }
  }

  recordFailure(row) {
    this.lastError = String(row.error || 'shadow mirror failed');
    if (this.report.errors.length < 500) this.report.errors.push(row);
    return { ok: false, error: this.lastError };
  }

  async health() {
    return this.request('/internal/health', 'GET');
  }

  async waitForIdle() {
    await this.tail;
  }

  snapshot() {
    return {
      version: 1,
      cellId: this.cellId,
      endpoint: this.endpointName,
      groups: this.groups.size,
      pending: this.pending,
      lastError: this.lastError,
      report: Object.assign({}, this.report, {
        errors: this.report.errors.slice()
      })
    };
  }

  writeReport(file) {
    const target = path.resolve(String(file || this.reportFile || ''));
    if (!target) return '';
    fs.mkdirSync(path.dirname(target), { recursive: true });
    const temporary = target + '.' + process.pid + '.tmp';
    fs.writeFileSync(temporary, JSON.stringify(this.snapshot(), null, 2), 'utf8');
    fs.renameSync(temporary, target);
    return target;
  }

  async close() {
    await this.waitForIdle();
    return this.writeReport();
  }
}

module.exports = {
  RemoteGroupCellShadow,
  parseCellEndpoints
};
