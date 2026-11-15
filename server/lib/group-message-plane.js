'use strict';

class GroupMessagePlane {
  constructor(options) {
    const opts = options || {};
    this.writePipeline = opts.writePipeline;
    this.membership = opts.membership;
    this.realtime = opts.realtime;
    this.pushQueue = opts.pushQueue;
    this.presence = opts.presence || null;
    if (!this.writePipeline) throw new Error('writePipeline is required');
    if (!this.membership) throw new Error('membership is required');
    if (!this.realtime) throw new Error('realtime is required');
    if (!this.pushQueue) throw new Error('pushQueue is required');
    this.largeGroupThreshold = Math.max(1, Number(opts.largeGroupThreshold) || 500);
    this.pushPartitionSize = Math.max(1, Number(opts.pushPartitionSize) || 1000);
    this.schedule = typeof opts.schedule === 'function'
      ? opts.schedule
      : (work) => setTimeout(work, 0);
    this.jobs = [];
    this.running = false;
    this.idleWaiters = [];
    this.lastFanoutError = '';
    this.fanoutStats = {
      smallGroupEvents: 0,
      largeGroupSignals: 0,
      pushPartitions: 0,
      userPushes: 0
    };
  }

  async deliver(groupId, senderId, message, options) {
    const group = String(groupId || '');
    const sender = String(senderId || '');
    if (!group || !sender) return { ok: false, error: 'groupId and senderId are required' };
    const membership = await this.membership.get(group, sender);
    if (!membership || membership.joinedSeq == null
        || (membership.leftSeq != null && Number(membership.leftSeq) > 0)) {
      return { ok: false, denied: true, error: 'sender is not an active group member' };
    }
    const result = await this.writePipeline.append(group, Object.assign({}, message, {
      senderId: sender
    }));
    if (!result.ok && !result.durable) return result;
    let fanout = 'duplicate';
    if (!result.duplicate) {
      this.enqueueFanout(group, result.message, result.seq);
      fanout = 'scheduled';
    }
    return Object.assign({}, result, {
      fanout,
      groupId: group,
      message: result.message
    });
  }

  canRead(groupId, userId, seq) {
    if (typeof this.membership.canReadSync === 'function') {
      return this.membership.canReadSync(
        String(groupId || ''),
        String(userId || ''),
        Number(seq) || 0
      ) === true;
    }
    const membership = this.membership.getSync
      ? this.membership.getSync(String(groupId || ''), String(userId || ''))
      : null;
    if (!membership) return false;
    const messageSeq = Number(seq) || 0;
    const joined = Number(membership.joinedSeq) || 0;
    const left = Number(membership.leftSeq) || 0;
    return messageSeq >= joined && (!left || messageSeq < left);
  }

  unreadCount(latestSeq, readSeq, clearedSeq) {
    const latest = Math.max(0, Number(latestSeq) || 0);
    const read = Math.max(0, Number(readSeq) || 0);
    const cleared = Math.max(0, Number(clearedSeq) || 0);
    return Math.max(0, latest - Math.max(read, cleared));
  }

  enqueueFanout(groupId, message, seq) {
    this.jobs.push({
      groupId,
      message,
      seq: Number(seq) || 0
    });
    this.scheduleRun();
  }

  fanoutExisting(groupId, message, seq) {
    this.enqueueFanout(
      String(groupId || ''),
      Object.assign({}, message || {}),
      Number(seq) || 0
    );
    return { status: 'scheduled' };
  }

  scheduleRun() {
    if (this.running) return;
    this.running = true;
    this.schedule(() => {
      this.run()
        .catch((error) => {
          this.lastFanoutError = String(error && error.message || error);
        })
        .finally(() => {
          this.running = false;
          if (this.jobs.length) this.scheduleRun();
          else this.resolveIdle();
        });
    });
  }

  async run() {
    while (this.jobs.length) {
      const job = this.jobs.shift();
      const count = Number(await this.membership.countActive(job.groupId, job.seq)) || 0;
      if (count <= this.largeGroupThreshold) {
        await this.fanoutSmallGroup(job, count);
      } else {
        await this.fanoutLargeGroup(job, count);
      }
    }
  }

  async fanoutSmallGroup(job, count) {
    const members = await this.membership.activeMembers(job.groupId, job.seq, 0, count);
    const event = {
      type: 'group.message',
      groupId: job.groupId,
      seq: job.seq,
      messageId: String(job.message && job.message.id || '')
    };
    for (const member of members) {
      const userId = String(member.userId || member.id || '');
      if (!userId) continue;
      const online = !this.presence || await this.presence.isOnline(userId);
      if (online) {
        await this.realtime.notifyUser(userId, event);
        this.fanoutStats.smallGroupEvents += 1;
      } else {
        await this.pushQueue.enqueueUser(userId, event);
        this.fanoutStats.userPushes += 1;
      }
    }
  }

  async fanoutLargeGroup(job, count) {
    const event = {
      type: 'group.updated',
      groupId: job.groupId,
      seq: job.seq,
      messageId: String(job.message && job.message.id || '')
    };
    await this.realtime.publishGroupSignal(job.groupId, event);
    this.fanoutStats.largeGroupSignals += 1;
    const partitions = Math.ceil(count / this.pushPartitionSize);
    for (let partition = 0; partition < partitions; partition += 1) {
      await this.pushQueue.enqueuePartition({
        groupId: job.groupId,
        seq: job.seq,
        partition,
        size: count,
        pageSize: this.pushPartitionSize
      });
      this.fanoutStats.pushPartitions += 1;
    }
  }

  waitForIdle() {
    if (!this.running && !this.jobs.length) return Promise.resolve();
    return new Promise((resolve) => this.idleWaiters.push(resolve));
  }

  resolveIdle() {
    const waiters = this.idleWaiters.splice(0);
    waiters.forEach((resolve) => resolve());
  }
}

module.exports = { GroupMessagePlane };
