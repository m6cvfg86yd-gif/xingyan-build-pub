'use strict';

const fs = require('fs');
const path = require('path');
const { canonical, hash } = require('./shard-snapshot');

async function request(base, method, route, value) {
  const response = await fetch(String(base).replace(/\/+$/, '') + route, {
    method,
    headers: value === undefined ? undefined : { 'Content-Type': 'application/json' },
    body: value === undefined ? undefined : JSON.stringify(value)
  });
  const data = await response.json();
  if (!response.ok || data.ok === false) {
    const error = new Error(data.error || 'cell request failed');
    error.status = response.status;
    error.data = data;
    throw error;
  }
  return data;
}

class RemoteGroupMigrationWorker {
  constructor(options) {
    const opts = options || {};
    this.routeStore = opts.routeStore;
    this.sourceUrl = String(opts.sourceUrl || '');
    this.targetUrl = String(opts.targetUrl || '');
    this.stateDir = path.resolve(String(opts.stateDir || ''));
    this.pageSize = Math.max(1, Math.min(500, Number(opts.pageSize) || 200));
    if (!this.routeStore) throw new Error('routeStore is required');
    if (!this.sourceUrl || !this.targetUrl) throw new Error('sourceUrl and targetUrl are required');
    if (!opts.stateDir) throw new Error('stateDir is required');
    fs.mkdirSync(this.stateDir, { recursive: true });
    this.checkpointFile = path.join(this.stateDir, 'remote-migrations.json');
  }

  checkpoints() {
    try { return JSON.parse(fs.readFileSync(this.checkpointFile, 'utf8')); }
    catch (_) { return {}; }
  }

  checkpoint(groupId) {
    return this.checkpoints()[String(groupId || '')] || null;
  }

  save(groupId, value) {
    const rows = this.checkpoints();
    rows[String(groupId || '')] = Object.assign({ updatedAt: new Date().toISOString() }, value);
    const temporary = this.checkpointFile + '.tmp';
    fs.writeFileSync(temporary, JSON.stringify(rows, null, 2), 'utf8');
    fs.renameSync(temporary, this.checkpointFile);
  }

  async messages(base, groupId) {
    const rows = [];
    let cursor = 0;
    while (true) {
      const page = await request(base, 'GET',
        '/internal/groups/' + encodeURIComponent(groupId)
        + '/message-page?afterSeq=' + cursor + '&limit=500');
      rows.push(...page.messages);
      if (!page.messages.length || page.lastSeq <= cursor) break;
      cursor = page.lastSeq;
      if (!page.hasMore) break;
    }
    return rows;
  }

  async metadata(base, groupId) {
    return request(base, 'GET',
      '/internal/groups/' + encodeURIComponent(groupId) + '/export-metadata');
  }

  async compare(groupId) {
    const [sourceMessages, targetMessages, sourceMeta, targetMeta] = await Promise.all([
      this.messages(this.sourceUrl, groupId),
      this.messages(this.targetUrl, groupId),
      this.metadata(this.sourceUrl, groupId),
      this.metadata(this.targetUrl, groupId)
    ]);
    const parts = {
      messages: { source: hash(sourceMessages), target: hash(targetMessages) },
      membership: { source: hash(sourceMeta.membership), target: hash(targetMeta.membership) },
      deletions: { source: hash(sourceMeta.deletions), target: hash(targetMeta.deletions) },
      cursors: { source: hash(sourceMeta.cursors), target: hash(targetMeta.cursors) }
    };
    return {
      ok: Object.values(parts).every((row) => row.source === row.target),
      parts,
      sourceHash: hash(parts),
      targetHash: hash(Object.fromEntries(Object.entries(parts).map(([key, value]) => [
        key,
        { source: value.target, target: value.target }
      ])))
    };
  }

  async migrate(options) {
    const opts = options || {};
    const groupId = String(opts.groupId || '');
    const sourceCellId = String(opts.sourceCellId || '');
    const targetCellId = String(opts.targetCellId || '');
    const epoch = Math.floor(Number(opts.epoch) || 0);
    if (!groupId || !sourceCellId || !targetCellId || epoch <= 0) {
      throw new Error('group, cells and epoch are required');
    }
    const prior = this.checkpoint(groupId);
    if (prior && prior.status === 'done' && prior.epoch === epoch) {
      return Object.assign({ resumed: true }, prior.report, { checkpoint: prior });
    }
    let route = this.routeStore.get(groupId);
    if (!route || route.status !== 'migrating' || route.epoch !== epoch) {
      if (!route) {
        throw new Error('group route is not assigned');
      }
      const begun = this.routeStore.set(Object.assign({}, route, {
        epoch,
        status: 'migrating',
        sourceCellId,
        targetCellId
      }));
      if (!begun.ok) return { ok: false, error: 'cannot begin migration', route: begun.route };
      route = begun.route;
    }

    const sourceMeta = await this.metadata(this.sourceUrl, groupId);
    await request(this.targetUrl, 'POST',
      '/internal/groups/' + encodeURIComponent(groupId) + '/import-metadata', {
      epoch,
      membership: sourceMeta.membership,
      deletions: sourceMeta.deletions,
      cursors: sourceMeta.cursors
    });

    let scanSeq = prior && prior.epoch === epoch ? prior.scanSeq : 0;
    let pages = 0;
    while (true) {
      const page = await request(this.sourceUrl, 'GET',
        '/internal/groups/' + encodeURIComponent(groupId)
        + '/message-page?afterSeq=' + scanSeq + '&limit=' + this.pageSize);
      for (const message of page.messages) {
        await request(this.targetUrl, 'POST',
          '/internal/groups/' + encodeURIComponent(groupId) + '/mirror', {
          epoch,
          senderId: message.senderId,
          message
        });
      }
      if (page.messages.length) scanSeq = page.lastSeq;
      pages += 1;
      this.save(groupId, {
        sourceCellId,
        targetCellId,
        epoch,
        scanSeq,
        status: 'running'
      });
      if (typeof opts.afterPage === 'function') {
        await opts.afterPage({ groupId, scanSeq, pages });
      }
      if (!page.hasMore) break;
    }

    const comparison = await this.compare(groupId);
    const report = {
      ok: comparison.ok,
      groupId,
      sourceCellId,
      targetCellId,
      epoch,
      scanSeq,
      pages,
      comparison
    };
    if (comparison.ok && opts.finalize !== false) {
      const completed = this.routeStore.set({
        groupId,
        cellId: targetCellId,
        epoch,
        status: 'active'
      });
      report.ok = completed.ok;
      report.route = completed.route;
    }
    this.save(groupId, {
      sourceCellId,
      targetCellId,
      epoch,
      scanSeq,
      status: report.ok ? 'done' : 'failed',
      report
    });
    return report;
  }
}

module.exports = { RemoteGroupMigrationWorker };
