'use strict';

const assert = require('assert');
const { EventEmitter } = require('events');
const { APNsHTTP2Pool } = require('../lib/apns-http2-pool');

let active = 0;
let peak = 0;
let connections = 0;
let requests = 0;

function fakeSession() {
  const session = new EventEmitter();
  session.closed = false;
  session.close = () => {
    if (session.closed) return;
    session.closed = true;
    session.emit('close');
  };
  session.request = (headers) => {
    const req = new EventEmitter();
    req.headers = headers;
    req.setEncoding = () => {};
    req.close = () => req.emit('error', new Error('closed'));
    req.end = () => {
      requests += 1;
      active += 1;
      peak = Math.max(peak, active);
      setTimeout(() => {
        active -= 1;
        req.emit('response', { ':status': 200 });
        req.emit('end');
      }, 2);
    };
    return req;
  };
  return session;
}

const pool = new APNsHTTP2Pool({
  jwtProvider: () => 'jwt',
  topicProvider: () => 'com.example.app',
  poolSize: 3,
  maxConcurrentPerSession: 4,
  http2: {
    connect() {
      connections += 1;
      return fakeSession();
    }
  }
});

async function main() {
  const jobs = Array.from({ length: 200 }, (_, index) =>
    pool.send('token-' + index, index % 2 === 0, {
      aps: { alert: { title: 'T', body: 'B' } }
    })
  );
  const results = await Promise.all(jobs);
  assert.ok(results.every((row) => row.ok && row.status === 200));
  assert.strictEqual(requests, 200);
  assert.ok(connections <= 6, 'connections=' + connections);
  assert.ok(peak <= 24, 'peak=' + peak);
  const stats = pool.snapshot();
  assert.strictEqual(stats.sent, 200);
  assert.strictEqual(stats.queueLength, 0);
  assert.strictEqual(stats.active, 0);
  pool.close();
  console.log('apns-http2-pool: passed ' + JSON.stringify({
    requests,
    connections,
    peak
  }));
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
