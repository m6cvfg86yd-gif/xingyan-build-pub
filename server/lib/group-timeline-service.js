'use strict';

class GroupTimelineService {
  constructor(options) {
    const opts = options || {};
    this.reliability = opts.reliability;
    this.membership = opts.membership;
    this.cleared = opts.cleared || null;
    if (!this.reliability) throw new Error('reliability is required');
    if (!this.membership) throw new Error('membership is required');
  }

  clearance(groupId, userId) {
    if (!this.cleared) return 0;
    if (typeof this.cleared.get === 'function') {
      return Math.max(0, Number(this.cleared.get(groupId, userId)) || 0);
    }
    return 0;
  }

  async read(options) {
    const opts = options || {};
    const groupId = String(opts.groupId || '');
    const userId = String(opts.userId || '');
    const afterSeq = Math.max(0, Math.floor(Number(opts.afterSeq) || 0));
    const limit = Math.max(1, Math.min(500, Math.floor(Number(opts.limit) || 200)));
    const period = this.membership.getLatest(groupId, userId);
    if (!period) {
      return {
        ok: false,
        denied: true,
        error: 'user has never been a group member',
        messages: [],
        lastSeq: afterSeq,
        hasMore: false
      };
    }
    const joined = Math.max(1, Number(period.joinedSeq) || 1);
    const left = Math.max(0, Number(period.leftSeq) || 0);
    const start = Math.max(afterSeq, joined - 1, this.clearance(groupId, userId));
    if (left && start >= left) {
      return {
        ok: true,
        messages: [],
        lastSeq: start,
        hasMore: false,
        membership: period
      };
    }
    const candidates = this.reliability.messagesAfter(
      groupId,
      start,
      Math.min(500, limit + 1)
    );
    const visible = candidates.filter((message) => {
      const seq = Number(message.seq) || 0;
      return seq >= joined && (!left || seq < left);
    });
    const page = visible.slice(0, limit);
    return {
      ok: true,
      messages: page,
      lastSeq: page.length ? Number(page[page.length - 1].seq) : start,
      hasMore: visible.length > limit,
      membership: period
    };
  }

  unread(groupId, userId, deviceId) {
    const period = this.membership.get(groupId, userId);
    if (!period) return 0;
    const latest = this.reliability.lastSequence(groupId);
    const cursor = deviceId
      ? this.reliability.deviceCursor(userId, deviceId, groupId)
      : { deliveredSeq: 0, readSeq: 0 };
    const floor = Math.max(
      Number(period.joinedSeq) - 1,
      Number(cursor.readSeq) || 0,
      this.clearance(groupId, userId)
    );
    return Math.max(0, latest - floor);
  }

  acknowledge(groupId, userId, deviceId, seq) {
    return this.reliability.ackDevice(
      userId,
      deviceId,
      groupId,
      Math.max(0, Number(seq) || 0)
    );
  }

  markRead(groupId, userId, deviceId, seq) {
    return this.reliability.markDeviceRead(
      userId,
      deviceId,
      groupId,
      Math.max(0, Number(seq) || 0)
    );
  }
}

module.exports = { GroupTimelineService };
