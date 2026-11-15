'use strict';

const assert = require('assert');
const { EventEmitter } = require('events');
const { APNsHTTP2Pool } = require('../lib/apns-http2-pool');

let active = 0;
let peak = 0;
let connections = 0;

function session() {
  const value = new EventEmitter();
  value.close = () => value.emit('close');
  value.request = () => {
    const req = new EventEmitter();
    req.setEncoding = () => {};
    req.close = () => req.emit('error', new Error('closed'));
    req.end = () => {
      active += 1;
      peak = Math.max(peak, active);
      setTimeout(() => {
        active -= 1;
        req.emit('response', { ':status': 200 });
        req.emit('end');
      }, 1);
    };
    return req;
  };
  return value;
}

const pool = new APNsHTTP2Pool({
  jwtProvider: () => 'jwt',
  topicProvider: () => 'com.example.app',
  poolSize: 8,
  maxConcurrentPerSession: 200,
  maxQueue: 50000,
  http2: {
    connect() {
      connections += 1;
      return session();
    }
  }
});

async function main() {
  const count = 20000;
  const started = process.hrtime.bigint();
  const results = await Promise.all(Array.from({ length: count }, (_, index) =>
    pool.send('token-' + index, index % 2 === 0, {
      aps: { alert: { title: 'T', body: 'B' } }
    })
  ));
  const elapsedMs = Number(process.hrtime.bigint() - started) / 1e6;
  assert.ok(results.every((row) => row.ok));
  assert.ok(connections <= 16);
  assert.strictEqual(pool.snapshot().sent, count);
  pool.close();
  console.log('apns-http2-pool-scale: passed ' + JSON.stringify({
    count,
    elapsedMs: Math.round(elapsedMs),
    perSecond: Math.round(count / (elapsedMs / 1000)),
    connections,
    peak,
    rssMB: Math.round(process.memoryUsage().rss / 1048576)
  }));
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
