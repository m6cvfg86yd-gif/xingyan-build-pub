'use strict';

class PaymentAudit {
  constructor(options) {
    this.ledger = options.ledger;
    this.readState = options.readState;
    this.writeState = options.writeState;
    this.stateName = options.stateName || 'payment-audit-state.json';
    this.uid = options.uid;
    this.now = options.now;
    this.onAlert = options.onAlert || (() => {});
    this.state = this.load();
  }

  load() {
    let state = {};
    try { state = this.readState(this.stateName, {}) || {}; } catch (_) { state = {}; }
    return {
      version: 1,
      runs: Array.isArray(state.runs) ? state.runs.slice(0, 500) : [],
      tickets: Array.isArray(state.tickets) ? state.tickets.slice(0, 500) : [],
      lastRunAt: String(state.lastRunAt || ''),
      lastOkAt: String(state.lastOkAt || ''),
      lastFailureAt: String(state.lastFailureAt || '')
    };
  }

  save() {
    this.writeState(this.stateName, this.state);
  }

  run(kind, users, bizBalanceOf) {
    const started = Date.now();
    const at = this.now();
    const reconciliation = this.ledger.reconcile(users, bizBalanceOf);
    const activeKeys = new Set();
    let newTickets = 0;
    let updatedTickets = 0;

    for (const diff of reconciliation.differences || []) {
      const key = [diff.kind || 'wallet', diff.userId || '', diff.username || ''].join(':');
      activeKeys.add(key);
      let ticket = this.state.tickets.find((row) => row.key === key && row.status === 'open');
      if (!ticket) {
        ticket = {
          id: this.uid('pat'),
          key,
          status: 'open',
          severity: 'critical',
          kind: diff.kind || 'wallet',
          userId: diff.userId || '',
          username: diff.username || '',
          firstSeenAt: at,
          lastSeenAt: at,
          occurrences: 1,
          difference: diff.difference,
          balance: diff.balance,
          ledger: diff.ledger,
          runs: 1
        };
        this.state.tickets.unshift(ticket);
        newTickets += 1;
      } else {
        ticket.lastSeenAt = at;
        ticket.occurrences = (Number(ticket.occurrences) || 0) + 1;
        ticket.difference = diff.difference;
        ticket.balance = diff.balance;
        ticket.ledger = diff.ledger;
        ticket.runs = (Number(ticket.runs) || 0) + 1;
        updatedTickets += 1;
      }
    }

    let resolvedTickets = 0;
    for (const ticket of this.state.tickets) {
      if (ticket.status !== 'open' || activeKeys.has(ticket.key)) continue;
      ticket.status = 'resolved';
      ticket.resolvedAt = at;
      ticket.resolution = '自动审计已确认余额与账本恢复一致';
      resolvedTickets += 1;
    }

    if (!reconciliation.integrity.ok) {
      const key = 'ledger:integrity';
      activeKeys.add(key);
      let ticket = this.state.tickets.find((row) => row.key === key && row.status === 'open');
      if (!ticket) {
        ticket = {
          id: this.uid('pat'),
          key,
          status: 'open',
          severity: 'critical',
          kind: 'integrity',
          firstSeenAt: at,
          lastSeenAt: at,
          occurrences: 1,
          runs: 1,
          failures: reconciliation.integrity.failures.slice(0, 50)
        };
        this.state.tickets.unshift(ticket);
        newTickets += 1;
      } else {
        ticket.lastSeenAt = at;
        ticket.occurrences = (Number(ticket.occurrences) || 0) + 1;
        ticket.runs = (Number(ticket.runs) || 0) + 1;
        ticket.failures = reconciliation.integrity.failures.slice(0, 50);
        updatedTickets += 1;
      }
    } else {
      const ticket = this.state.tickets.find((row) => row.key === 'ledger:integrity' && row.status === 'open');
      if (ticket) {
        ticket.status = 'resolved';
        ticket.resolvedAt = at;
        ticket.resolution = '链式账本完整性校验恢复通过';
        resolvedTickets += 1;
      }
    }

    const row = {
      id: this.uid('par'),
      kind: String(kind || 'scheduled'),
      at,
      durationMs: Date.now() - started,
      ok: !!reconciliation.ok,
      entries: reconciliation.entries,
      usersChecked: Array.isArray(users) ? users.length : 0,
      differences: (reconciliation.differences || []).length,
      newTickets,
      updatedTickets,
      resolvedTickets,
      integrityOk: !!reconciliation.integrity.ok,
      integrityChecked: Number(reconciliation.integrity.checked) || 0,
      ledgerTotalCents: reconciliation.ledgerTotalCents
    };
    this.state.runs.unshift(row);
    this.state.runs = this.state.runs.slice(0, 500);
    this.state.tickets = this.state.tickets.slice(0, 500);
    this.state.lastRunAt = at;
    if (row.ok) this.state.lastOkAt = at;
    else this.state.lastFailureAt = at;
    this.save();

    if (!row.ok) {
      try { this.onAlert(row, this.state.tickets.filter((ticket) => ticket.status === 'open')); }
      catch (_) { /* 告警失败不能回滚审计结果。 */ }
    }
    return row;
  }

  summary() {
    return {
      lastRunAt: this.state.lastRunAt,
      lastOkAt: this.state.lastOkAt,
      lastFailureAt: this.state.lastFailureAt,
      latestRun: this.state.runs[0] || null,
      openTickets: this.state.tickets.filter((row) => row.status === 'open'),
      runs: this.state.runs.slice(0, 50)
    };
  }
}

module.exports = { PaymentAudit };
