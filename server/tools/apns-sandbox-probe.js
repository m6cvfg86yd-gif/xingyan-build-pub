#!/usr/bin/env node
'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { APNsHTTP2Pool } = require('../lib/apns-http2-pool');

function arg(name, fallback) {
  const index = process.argv.indexOf('--' + name);
  return index >= 0 ? process.argv[index + 1] : fallback;
}

function percentile(values, ratio) {
  const sorted = values.slice().sort((left, right) => left - right);
  const index = Math.min(sorted.length - 1,
    Math.max(0, Math.ceil(sorted.length * ratio) - 1));
  return sorted.length ? sorted[index] : 0;
}

const keyPath = path.resolve(String(arg('key-path', '')));
const keyId = String(arg('key-id', process.env.APNS_KEY_ID || ''));
const teamId = String(arg('team-id', process.env.APNS_TEAM_ID || ''));
const bundleId = String(arg('bundle-id', process.env.APNS_BUNDLE_ID || ''));
const deviceToken = String(arg('device-token', process.env.APNS_DEVICE_TOKEN || ''));
const count = Math.max(1, Math.min(10000, Number(arg('count', '100')) || 100));
if (!arg('key-path', '') || !keyId || !teamId || !bundleId || !deviceToken) {
  throw new Error('key-path, key-id, team-id, bundle-id and device-token are required');
}
const key = fs.readFileSync(keyPath, 'utf8');
let jwt = '';
let jwtAt = 0;

function token() {
  const now = Date.now();
  if (jwt && now - jwtAt < 50 * 60 * 1000) return jwt;
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
  const head = encode({ alg: 'ES256', kid: keyId });
  const claims = encode({ iss: teamId, iat: Math.floor(now / 1000) });
  const signing = head + '.' + claims;
  const signature = crypto.sign('sha256', Buffer.from(signing), {
    key,
    dsaEncoding: 'ieee-p1363'
  }).toString('base64url');
  jwt = signing + '.' + signature;
  jwtAt = now;
  return jwt;
}

const pool = new APNsHTTP2Pool({
  jwtProvider: token,
  topicProvider: () => bundleId,
  poolSize: Number(arg('pool-size', '4')) || 4,
  maxConcurrentPerSession: Number(arg('max-concurrent', '200')) || 200,
  maxQueue: Math.max(count, Number(arg('max-queue', '50000')) || 50000),
  requestTimeoutMs: Number(arg('timeout-ms', '8000')) || 8000
});

async function main() {
  const started = process.hrtime.bigint();
  const runId = crypto.randomUUID();
  const durations = [];
  const results = await Promise.all(Array.from({ length: count }, async (_, index) => {
    const requestStarted = process.hrtime.bigint();
    const result = await pool.send(deviceToken, true, {
      aps: {
        alert: {
          title: '星言 APNs 沙盒测试',
          body: '探针 ' + (index + 1) + '/' + count
        },
        sound: 'default'
      },
      probeRun: runId,
      probeIndex: index
    });
    durations.push(Number(process.hrtime.bigint() - requestStarted) / 1e6);
    return result;
  }));
  const elapsedMs = Number(process.hrtime.bigint() - started) / 1e6;
  const succeeded = results.filter((row) => row.ok).length;
  console.log(JSON.stringify({
    count,
    succeeded,
    failed: count - succeeded,
    elapsedMs: Math.round(elapsedMs),
    perSecond: Math.round(count / (elapsedMs / 1000)),
    p50Ms: Math.round(percentile(durations, 0.50)),
    p95Ms: Math.round(percentile(durations, 0.95)),
    p99Ms: Math.round(percentile(durations, 0.99)),
    transport: pool.snapshot(),
    firstFailure: results.find((row) => !row.ok) || null
  }, null, 2));
  if (succeeded !== count) process.exitCode = 2;
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
}).finally(() => {
  pool.close();
});
