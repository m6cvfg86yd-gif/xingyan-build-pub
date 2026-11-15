'use strict';

const http2 = require('http2');

class APNsHTTP2Pool {
  constructor(options) {
    const opts = options || {};
    this.jwtProvider = opts.jwtProvider;
    this.topicProvider = opts.topicProvider;
    if (typeof this.jwtProvider !== 'function') throw new Error('jwtProvider is required');
    if (typeof this.topicProvider !== 'function') throw new Error('topicProvider is required');
    this.sandboxHost = String(opts.sandboxHost || 'https://api.sandbox.push.apple.com');
    this.prodHost = String(opts.prodHost || 'https://api.push.apple.com');
    this.poolSize = Math.max(1, Math.min(32, Number(opts.poolSize) || 4));
    this.maxConcurrentPerSession = Math.max(
      1,
      Math.min(1000, Number(opts.maxConcurrentPerSession) || 200)
    );
    this.maxQueue = Math.max(1, Number(opts.maxQueue) || 50000);
    this.requestTimeoutMs = Math.max(1000, Number(opts.requestTimeoutMs) || 8000);
    this.http2 = opts.http2 || http2;
    this.sessions = new Map();
    this.queue = [];
    this.roundRobin = 0;
    this.closed = false;
    this.stats = {
      queued: 0,
      active: 0,
      sent: 0,
      failed: 0,
      overflow: 0,
      reconnects: 0
    };
  }

  hosts(sandbox) {
    return sandbox ? this.sandboxHost : this.prodHost;
  }

  sessionsFor(host) {
    const key = String(host);
    if (!this.sessions.has(key)) this.sessions.set(key, []);
    return this.sessions.get(key);
  }

  createSession(host) {
    const session = this.http2.connect(host);
    session.__apnsActive = 0;
    session.__apnsAlive = true;
    const remove = () => {
      session.__apnsAlive = false;
      const rows = this.sessionsFor(host);
      const index = rows.indexOf(session);
      if (index >= 0) rows.splice(index, 1);
      this.pump();
    };
    session.once('error', remove);
    session.once('close', remove);
    session.once('goaway', () => {
      try { session.close(); } catch (_) { }
      remove();
    });
    return session;
  }

  sessionFor(host) {
    const rows = this.sessionsFor(host);
    let available = rows.filter((session) =>
      session.__apnsAlive !== false
      && session.__apnsActive < this.maxConcurrentPerSession
    );
    if (available.length) {
      const session = available[this.roundRobin % available.length];
      this.roundRobin += 1;
      return session;
    }
    if (rows.length < this.poolSize) {
      const session = this.createSession(host);
      rows.push(session);
      return session;
    }
    return null;
  }

  send(deviceToken, sandbox, payload) {
    if (this.closed) return Promise.resolve({
      ok: false,
      status: 0,
      reason: 'apns pool closed'
    });
    if (this.queue.length >= this.maxQueue) {
      this.stats.overflow += 1;
      return Promise.resolve({
        ok: false,
        status: 0,
        reason: 'apns queue full'
      });
    }
    return new Promise((resolve) => {
      this.queue.push({
        token: String(deviceToken || ''),
        sandbox: sandbox === true,
        payload,
        resolve
      });
      this.stats.queued += 1;
      this.pump();
    });
  }

  pump() {
    if (this.closed) return;
    while (this.queue.length) {
      const job = this.queue[0];
      const host = this.hosts(job.sandbox);
      const session = this.sessionFor(host);
      if (!session) break;
      this.queue.shift();
      this.stats.active += 1;
      session.__apnsActive += 1;
      this.dispatch(session, host, job).finally(() => {
        session.__apnsActive = Math.max(0, session.__apnsActive - 1);
        this.stats.active = Math.max(0, this.stats.active - 1);
        this.pump();
      });
    }
  }

  dispatch(session, host, job) {
    return new Promise((resolve) => {
      let finished = false;
      let req = null;
      const finish = (result) => {
        if (finished) return;
        finished = true;
        if (result.ok) this.stats.sent += 1;
        else this.stats.failed += 1;
        job.resolve(result);
        resolve(result);
      };
      const timer = setTimeout(() => {
        try { if (req) req.close(); } catch (_) { }
        finish({ ok: false, status: 0, reason: 'timeout' });
      }, this.requestTimeoutMs);
      timer.unref();
      try {
        req = session.request({
          ':method': 'POST',
          ':path': '/3/device/' + job.token,
          authorization: 'bearer ' + this.jwtProvider(),
          'apns-topic': String(this.topicProvider() || ''),
          'apns-push-type': 'alert',
          'apns-priority': '10',
          'apns-expiration': String(Math.floor(Date.now() / 1000) + 3600),
          'content-type': 'application/json'
        });
      } catch (error) {
        clearTimeout(timer);
        try { session.close(); } catch (_) { }
        finish({
          ok: false,
          status: 0,
          reason: String(error && error.message || error)
        });
        return;
      }
      let status = 0;
      let text = '';
      req.on('response', (headers) => {
        status = Number(headers && headers[':status']) || 0;
      });
      if (typeof req.setEncoding === 'function') req.setEncoding('utf8');
      req.on('data', (chunk) => {
        if (text.length < 400) text += String(chunk || '');
      });
      req.on('end', () => {
        clearTimeout(timer);
        finish({ ok: status === 200, status, reason: text });
      });
      req.on('error', (error) => {
        clearTimeout(timer);
        finish({
          ok: false,
          status,
          reason: String(error && error.message || error)
        });
      });
      try {
        req.end(JSON.stringify(job.payload));
      } catch (error) {
        clearTimeout(timer);
        finish({
          ok: false,
          status: 0,
          reason: String(error && error.message || error)
        });
      }
    });
  }

  snapshot() {
    const sessions = [];
    for (const [host, rows] of this.sessions.entries()) {
      sessions.push({
        host,
        sessions: rows.length,
        active: rows.reduce((sum, session) => sum + (session.__apnsActive || 0), 0)
      });
    }
    return Object.assign({}, this.stats, {
      queueLength: this.queue.length,
      poolSize: this.poolSize,
      maxConcurrentPerSession: this.maxConcurrentPerSession,
      sessions
    });
  }

  close() {
    if (this.closed) return;
    this.closed = true;
    for (const rows of this.sessions.values()) {
      rows.forEach((session) => {
        try { session.close(); } catch (_) { }
      });
    }
    this.sessions.clear();
    const queued = this.queue.splice(0);
    queued.forEach((job) => job.resolve({
      ok: false,
      status: 0,
      reason: 'apns pool closed'
    }));
  }
}

module.exports = { APNsHTTP2Pool };
