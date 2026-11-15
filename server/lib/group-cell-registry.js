'use strict';

const crypto = require('crypto');

function digest(value) {
  return crypto.createHash('sha256').update(String(value)).digest('hex');
}

function normalizeCells(input) {
  const rows = Array.isArray(input)
    ? input
    : Object.keys(input || {}).map((cellId) =>
      Object.assign({ cellId }, input[cellId] || {})
    );
  const seen = new Set();
  return rows.map((row) => {
    const cellId = String(row && row.cellId || '').trim();
    const baseUrl = String(row && row.baseUrl || '').trim().replace(/\/+$/, '');
    if (!cellId || seen.has(cellId)) throw new Error('unique cellId is required');
    seen.add(cellId);
    const parsed = new URL(baseUrl);
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
      throw new Error('cell baseUrl must use http or https');
    }
    return {
      cellId,
      baseUrl,
      endpoint: parsed.origin,
      internalToken: String(row.internalToken || ''),
      capacityWeight: Math.max(0, Number(row.capacityWeight) || 0),
      usedWeight: Math.max(0, Number(row.usedWeight) || 0),
      draining: row.draining === true
    };
  }).sort((left, right) => left.cellId < right.cellId ? -1
    : (left.cellId > right.cellId ? 1 : 0));
}

class GroupCellRegistry {
  constructor(options) {
    const opts = options || {};
    this.cells = new Map(normalizeCells(opts.cells || []).map((cell) =>
      [cell.cellId, cell]
    ));
    if (!this.cells.size) throw new Error('at least one cell is required');
    this.timeoutMs = Math.max(250, Number(opts.timeoutMs) || 2500);
    this.fetchImpl = opts.fetchImpl || fetch;
    this.now = typeof opts.now === 'function' ? opts.now : Date.now;
    this.states = new Map();
    for (const cellId of this.cells.keys()) {
      this.states.set(cellId, {
        healthy: false,
        checking: null,
        consecutiveFailures: 0,
        lastCheckedAt: 0,
        lastHealthyAt: 0,
        latencyMs: 0,
        lastError: '',
        stats: {}
      });
    }
    this.timer = null;
  }

  setUsedWeight(cellId, value) {
    const cell = this.cells.get(String(cellId || ''));
    if (!cell) throw new Error('cell is not registered');
    cell.usedWeight = Math.max(0, Number(value) || 0);
  }

  async check(cellId) {
    const id = String(cellId || '');
    const cell = this.cells.get(id);
    const state = this.states.get(id);
    if (!cell || !state) throw new Error('cell is not registered');
    if (state.checking) return state.checking;
    state.checking = this.checkNow(cell, state).finally(() => {
      state.checking = null;
    });
    return state.checking;
  }

  async checkNow(cell, state) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.timeoutMs);
    timeout.unref();
    const started = this.now();
    const headers = {};
    if (cell.internalToken) headers['X-Internal-Token'] = cell.internalToken;
    try {
      const response = await this.fetchImpl(cell.baseUrl + '/internal/health', {
        method: 'GET',
        headers,
        signal: controller.signal
      });
      let data = {};
      try { data = await response.json(); } catch (_) { }
      if (!response.ok || data.ok !== true) {
        throw new Error(data.error || 'cell health check failed');
      }
      const checkedAt = this.now();
      state.healthy = true;
      state.consecutiveFailures = 0;
      state.lastCheckedAt = checkedAt;
      state.lastHealthyAt = checkedAt;
      state.latencyMs = Math.max(0, checkedAt - started);
      state.lastError = '';
      state.stats = data.stats || {};
      return this.snapshotCell(cell.cellId);
    } catch (error) {
      state.healthy = false;
      state.consecutiveFailures += 1;
      state.lastCheckedAt = this.now();
      state.latencyMs = Math.max(0, state.lastCheckedAt - started);
      state.lastError = String(error && error.message || error);
      return this.snapshotCell(cell.cellId);
    } finally {
      clearTimeout(timeout);
    }
  }

  async checkAll() {
    await Promise.all(Array.from(this.cells.keys()).map((cellId) => this.check(cellId)));
    return this.snapshot();
  }

  get(cellId, options) {
    const opts = options || {};
    const cell = this.cells.get(String(cellId || ''));
    const state = this.states.get(String(cellId || ''));
    if (!cell || !state) return null;
    if (opts.requireHealthy && !state.healthy) return null;
    if (cell.draining) return null;
    if (opts.requireCapacity && cell.capacityWeight > 0
        && cell.usedWeight >= cell.capacityWeight) return null;
    return Object.assign({}, cell, {
      healthy: state.healthy,
      latencyMs: state.latencyMs,
      remainingWeight: cell.capacityWeight > 0
        ? Math.max(0, cell.capacityWeight - cell.usedWeight)
        : null
    });
  }

  select(groupId, weight) {
    const requested = Math.max(0, Number(weight) || 0);
    const candidates = Array.from(this.cells.keys())
      .map((cellId) => this.get(cellId, {
        requireHealthy: true,
        requireCapacity: true
      }))
      .filter((cell) => cell && (cell.capacityWeight <= 0
        || cell.remainingWeight >= requested));
    if (!candidates.length) return null;
    candidates.sort((left, right) => {
      if (left.usedWeight !== right.usedWeight) return left.usedWeight - right.usedWeight;
      const leftHash = digest(String(groupId || '') + '\0' + left.cellId);
      const rightHash = digest(String(groupId || '') + '\0' + right.cellId);
      return leftHash < rightHash ? -1 : (leftHash > rightHash ? 1
        : (left.cellId < right.cellId ? -1 : 1));
    });
    return candidates[0];
  }

  snapshotCell(cellId) {
    const cell = this.cells.get(cellId);
    const state = this.states.get(cellId);
    return {
      cellId,
      endpoint: cell.endpoint,
      healthy: state.healthy,
      draining: cell.draining,
      consecutiveFailures: state.consecutiveFailures,
      lastCheckedAt: state.lastCheckedAt,
      lastHealthyAt: state.lastHealthyAt,
      latencyMs: state.latencyMs,
      lastError: state.lastError,
      capacityWeight: cell.capacityWeight,
      usedWeight: cell.usedWeight,
      remainingWeight: cell.capacityWeight > 0
        ? Math.max(0, cell.capacityWeight - cell.usedWeight)
        : null,
      stats: state.stats
    };
  }

  snapshot() {
    return {
      cells: Array.from(this.cells.keys()).map((cellId) => this.snapshotCell(cellId))
    };
  }

  start(intervalMs) {
    if (this.timer) return;
    const period = Math.max(1000, Number(intervalMs) || 15000);
    this.checkAll().catch(() => { });
    this.timer = setInterval(() => {
      this.checkAll().catch(() => { });
    }, period);
    this.timer.unref();
  }

  stop() {
    if (!this.timer) return;
    clearInterval(this.timer);
    this.timer = null;
  }
}

module.exports = {
  GroupCellRegistry,
  normalizeCells
};
