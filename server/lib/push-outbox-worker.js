'use strict';

class PushOutboxWorker {
  constructor(options) {
    const opts = options || {};
    this.outbox = opts.outbox;
    this.send = opts.send;
    this.logMany = typeof opts.logMany === 'function' ? opts.logMany : () => {};
    this.onBadToken = typeof opts.onBadToken === 'function' ? opts.onBadToken : async () => {};
    this.batchSize = Math.max(1, Math.min(500, Number(opts.batchSize) || 200));
    this.leaseMs = Math.max(1000, Number(opts.leaseMs) || 30000);
    if (!this.outbox) throw new Error('outbox is required');
    if (typeof this.send !== 'function') throw new Error('send is required');
    this.running = false;
  }

  async runOnce() {
    if (this.running) return { skipped: true, claimed: 0 };
    this.running = true;
    try {
      const jobs = this.outbox.claim(this.batchSize, this.leaseMs);
      if (!jobs.length) return { skipped: false, claimed: 0 };
      const outcomes = await Promise.all(jobs.map(async (job) => {
        let result;
        try {
          result = await this.send(job.deviceToken, job.env === 'sandbox', job.payload);
        } catch (error) {
          result = {
            ok: false,
            status: 0,
            reason: String(error && error.message || error)
          };
        }
        const bad = result.status === 400 || result.status === 410
          || /BadDeviceToken|Unregistered|DeviceTokenNotForTopic/.test(
            String(result.reason || '')
          );
        return { job, result, bad };
      }));

      const completeIds = [];
      const retries = [];
      const logs = [];
      const badTokens = [];
      for (const outcome of outcomes) {
        const { job, result, bad } = outcome;
        if (result.ok || bad) completeIds.push(job.id);
        else {
          retries.push({
            id: job.id,
            attempts: job.attempts,
            error: result.reason || 'apns failed',
            delayMs: Math.min(60000, 1000 * Math.pow(2, job.attempts))
          });
        }
        if (bad) badTokens.push({ userId: job.userId, token: job.deviceToken });
        logs.push({
          userId: job.userId,
          kind: job.kind,
          ok: !!result.ok,
          status: result.status,
          reason: String(result.reason || '').slice(0, 120),
          outbox: true,
          removedToken: bad
        });
      }
      if (completeIds.length) this.outbox.completeMany(completeIds);
      if (retries.length) this.outbox.retryMany(retries);
      for (const row of badTokens) {
        try { await this.onBadToken(row.userId, row.token); } catch (_) { }
      }
      this.logMany(logs);
      return {
        skipped: false,
        claimed: jobs.length,
        completed: completeIds.length,
        retried: retries.length,
        badTokens: badTokens.length
      };
    } finally {
      this.running = false;
    }
  }
}

module.exports = { PushOutboxWorker };
