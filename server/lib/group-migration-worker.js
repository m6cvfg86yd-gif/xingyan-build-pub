'use strict';

const fs = require('fs');
const path = require('path');
const { DatabaseSync } = require('node:sqlite');
const { canonical, hash } = require('./shard-snapshot');

class GroupMigrationWorker {
  constructor(options) {
    const opts = options || {};
    this.router = opts.router;
    this.stateDir = path.resolve(String(opts.stateDir || ''));
    this.pageSize = Math.max(1, Math.min(5000, Number(opts.pageSize) || 500));
    if (!this.router) throw new Error('router is required');
    if (!opts.stateDir) throw new Error('stateDir is required');
    fs.mkdirSync(this.stateDir, { recursive: true });
    this.db = new DatabaseSync(path.join(this.stateDir, 'group-migrations.sqlite3'));
    this.db.exec(`
      PRAGMA journal_mode = WAL;
      PRAGMA synchronous = FULL;
      CREATE TABLE IF NOT EXISTS group_migrations (
        group_id TEXT PRIMARY KEY,
        source_cell TEXT NOT NULL,
        target_cell TEXT NOT NULL,
        epoch INTEGER NOT NULL,
        scan_seq INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL,
        source_hash TEXT NOT NULL DEFAULT '',
        target_hash TEXT NOT NULL DEFAULT '',
        report_json TEXT NOT NULL DEFAULT '',
        updated_at TEXT NOT NULL
      );
    `);
  }

  get(groupId) {
    const row = this.db.prepare(`
      SELECT * FROM group_migrations WHERE group_id = ?
    `).get(String(groupId || ''));
    if (!row) return null;
    return {
      groupId: String(row.group_id),
      sourceCell: String(row.source_cell),
      targetCell: String(row.target_cell),
      epoch: Number(row.epoch) || 0,
      scanSeq: Number(row.scan_seq) || 0,
      status: String(row.status || ''),
      sourceHash: String(row.source_hash || ''),
      targetHash: String(row.target_hash || ''),
      report: row.report_json ? JSON.parse(row.report_json) : null,
      updatedAt: String(row.updated_at || '')
    };
  }

  save(groupId, value) {
    const row = Object.assign({}, value);
    this.db.prepare(`
      INSERT INTO group_migrations
        (group_id, source_cell, target_cell, epoch, scan_seq, status,
         source_hash, target_hash, report_json, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(group_id) DO UPDATE SET
        source_cell = excluded.source_cell,
        target_cell = excluded.target_cell,
        epoch = excluded.epoch,
        scan_seq = excluded.scan_seq,
        status = excluded.status,
        source_hash = excluded.source_hash,
        target_hash = excluded.target_hash,
        report_json = excluded.report_json,
        updated_at = excluded.updated_at
    `).run(
      String(groupId || ''),
      String(row.sourceCell || ''),
      String(row.targetCell || ''),
      Math.max(0, Number(row.epoch) || 0),
      Math.max(0, Number(row.scanSeq) || 0),
      String(row.status || 'running'),
      String(row.sourceHash || ''),
      String(row.targetHash || ''),
      row.report ? JSON.stringify(row.report) : '',
      new Date().toISOString()
    );
  }

  async collectMessages(cell, groupId) {
    const rows = [];
    let cursor = 0;
    while (true) {
      const page = cell.reliability.messagesAfter(groupId, cursor, 500);
      if (!page.length) break;
      rows.push(...page);
      const next = Number(page[page.length - 1].seq) || cursor;
      if (next <= cursor) break;
      cursor = next;
      if (page.length < 500) break;
    }
    return rows;
  }

  async compare(source, target, groupId) {
    const sourceMessages = await this.collectMessages(source, groupId);
    const targetMessages = await this.collectMessages(target, groupId);
    const sourceMembership = source.membership.listPeriods(groupId);
    const targetMembership = target.membership.listPeriods(groupId);
    const sourceDeletions = source.deletions.exportGroup(groupId);
    const targetDeletions = target.deletions.exportGroup(groupId);
    const sourceCursors = source.reliability.exportDeviceCursors(groupId);
    const targetCursors = target.reliability.exportDeviceCursors(groupId);
    const parts = {
      messages: {
        source: hash(sourceMessages),
        target: hash(targetMessages),
        sourceCount: sourceMessages.length,
        targetCount: targetMessages.length
      },
      membership: {
        source: hash(sourceMembership),
        target: hash(targetMembership),
        sourceCount: sourceMembership.length,
        targetCount: targetMembership.length
      },
      deletions: {
        source: hash(sourceDeletions),
        target: hash(targetDeletions)
      },
      cursors: {
        source: hash(sourceCursors),
        target: hash(targetCursors),
        sourceCount: sourceCursors.length,
        targetCount: targetCursors.length
      }
    };
    if (parts.messages.source !== parts.messages.target) {
      const sourceById = new Map(sourceMessages.map((row) => [row.id, row]));
      const targetById = new Map(targetMessages.map((row) => [row.id, row]));
      const ids = Array.from(new Set([...sourceById.keys(), ...targetById.keys()])).sort();
      const diffs = [];
      for (const id of ids) {
        const left = sourceById.get(id);
        const right = targetById.get(id);
        if (!left || !right || canonical(left) !== canonical(right)) {
          const fieldDiffs = {};
          if (left && right) {
            const keys = new Set([...Object.keys(left), ...Object.keys(right)]);
            for (const key of keys) {
              if (canonical(left[key]) === canonical(right[key])) continue;
              fieldDiffs[key] = {
                source: left[key],
                target: right[key]
              };
            }
          }
          diffs.push({
            id,
            sourceSeq: left ? Number(left.seq) || 0 : 0,
            targetSeq: right ? Number(right.seq) || 0 : 0,
            sourceHash: left ? hash(left) : '',
            targetHash: right ? hash(right) : '',
            fields: fieldDiffs
          });
          if (diffs.length >= 100) break;
        }
      }
      parts.messages.diffs = diffs;
    }
    const failed = Object.keys(parts).filter((key) =>
      parts[key].source !== parts[key].target
    );
    const sourceHash = hash(parts);
    const targetHash = hash(Object.fromEntries(Object.entries(parts).map(([key, value]) => [
      key,
      Object.assign({}, value, {
        source: value.target,
        target: value.target
      })
    ])));
    return {
      ok: failed.length === 0,
      failed,
      parts,
      sourceHash,
      targetHash
    };
  }

  async migrate(options) {
    const opts = options || {};
    const groupId = String(opts.groupId || '');
    const sourceCellId = String(opts.sourceCellId || '');
    const targetCellId = String(opts.targetCellId || '');
    const epoch = Math.floor(Number(opts.epoch) || 0);
    const source = this.router.cells[sourceCellId];
    const target = this.router.cells[targetCellId];
    if (!groupId || !source || !target) {
      throw new Error('valid group, source cell and target cell are required');
    }
    const prior = this.get(groupId);
    if (prior && prior.status === 'done'
        && prior.sourceCell === sourceCellId
        && prior.targetCell === targetCellId
        && prior.epoch === epoch) {
      return Object.assign({ resumed: true }, prior.report, { checkpoint: prior });
    }
    const route = this.router.route(groupId);
    if (!route || route.status !== 'migrating'
        || route.targetCellId !== targetCellId || route.epoch !== epoch) {
      const begun = this.router.beginMigration(groupId, targetCellId, epoch);
      if (!begun.ok) {
        return {
          ok: false,
          error: 'cannot begin migration',
          route: begun.route
        };
      }
    }

    for (const period of source.membership.listPeriods(groupId)) {
      target.membership.importPeriod(period);
    }
    target.deletions.importGroup(groupId, source.deletions.exportGroup(groupId));
    target.reliability.importDeviceCursors(
      source.reliability.exportDeviceCursors(groupId)
    );

    let scanSeq = prior && prior.sourceCell === sourceCellId
      && prior.targetCell === targetCellId && prior.epoch === epoch
      ? prior.scanSeq
      : 0;
    let pageCount = 0;
    while (true) {
      const page = source.reliability.messagesAfter(groupId, scanSeq, this.pageSize);
      if (!page.length) break;
      for (const message of page) {
        const result = await target.mirror(groupId, message.senderId, message, {
          fanout: false
        });
        if (!result.ok) {
          this.save(groupId, {
            sourceCell: sourceCellId,
            targetCell: targetCellId,
            epoch,
            scanSeq,
            status: 'failed'
          });
          return {
            ok: false,
            error: result.error || 'message mirror failed',
            messageId: message.id,
            seq: message.seq
          };
        }
      }
      scanSeq = Number(page[page.length - 1].seq) || scanSeq;
      pageCount += 1;
      this.save(groupId, {
        sourceCell: sourceCellId,
        targetCell: targetCellId,
        epoch,
        scanSeq,
        status: 'running'
      });
      if (typeof opts.afterPage === 'function') {
        await opts.afterPage({
          groupId,
          scanSeq,
          pageCount,
          sourceCell: source,
          targetCell: target
        });
      }
      if (page.length < this.pageSize) break;
    }

    const comparison = await this.compare(source, target, groupId);
    const report = {
      ok: comparison.ok,
      groupId,
      sourceCellId,
      targetCellId,
      epoch,
      scanSeq,
      pages: pageCount,
      comparison
    };
    if (!comparison.ok) {
      this.save(groupId, {
        sourceCell: sourceCellId,
        targetCell: targetCellId,
        epoch,
        scanSeq,
        status: 'mismatch',
        sourceHash: comparison.sourceHash,
        targetHash: comparison.targetHash,
        report
      });
      return report;
    }
    if (opts.finalize !== false) {
      const completed = this.router.completeMigration(groupId, epoch);
      if (!completed.ok) {
        report.ok = false;
        report.error = 'epoch completion rejected';
        report.route = completed.route;
      } else {
        report.route = completed.route;
      }
    }
    this.save(groupId, {
      sourceCell: sourceCellId,
      targetCell: targetCellId,
      epoch,
      scanSeq,
      status: report.ok ? 'done' : 'failed',
      sourceHash: comparison.sourceHash,
      targetHash: comparison.targetHash,
      report
    });
    return report;
  }

  close() {
    if (!this.db) return;
    this.db.close();
    this.db = null;
  }
}

module.exports = { GroupMigrationWorker };
