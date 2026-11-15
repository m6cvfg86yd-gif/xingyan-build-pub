'use strict';

class GroupNotificationWorker {
  constructor(options) {
    const opts = options || {};
    this.membership = opts.membership;
    this.pushProvider = opts.pushProvider;
    this.presence = opts.presence || null;
    if (!this.membership) throw new Error('membership is required');
    if (!this.pushProvider) throw new Error('pushProvider is required');
    this.batchSize = Math.max(1, Math.min(5000, Number(opts.batchSize) || 500));
  }

  async process(job) {
    const groupId = String(job && job.groupId || '');
    const seq = Math.max(1, Math.floor(Number(job && job.seq) || 0));
    const partition = Math.max(0, Math.floor(Number(job && job.partition) || 0));
    const pageSize = Math.max(1, Math.min(
      this.batchSize,
      Math.floor(Number(job && job.pageSize) || this.batchSize)
    ));
    if (!groupId) throw new Error('groupId is required');
    const offset = partition * pageSize;
    const members = await this.membership.activeMembers(groupId, seq, offset, pageSize);
    let sent = 0;
    let skippedOnline = 0;
    let skippedOfflineUnknown = 0;
    for (const member of members) {
      const userId = String(member.userId || member.id || '');
      if (!userId) continue;
      if (this.presence) {
        const online = await this.presence.isOnline(userId);
        if (online) {
          skippedOnline += 1;
          continue;
        }
      }
      const result = await this.pushProvider.send({
        userId,
        groupId,
        seq,
        messageId: String(job.messageId || ''),
        idempotencyKey: groupId + ':' + seq + ':' + userId,
        kind: 'group.message'
      });
      if (result && result.skipped) skippedOfflineUnknown += 1;
      else sent += 1;
    }
    return {
      groupId,
      seq,
      partition,
      offset,
      scanned: members.length,
      sent,
      skippedOnline,
      skippedOfflineUnknown,
      hasMore: members.length === pageSize
    };
  }

  async processAll(jobs) {
    const results = [];
    for (const job of Array.isArray(jobs) ? jobs : []) {
      results.push(await this.process(job));
    }
    return results;
  }
}

module.exports = { GroupNotificationWorker };
